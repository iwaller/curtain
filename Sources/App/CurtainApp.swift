import AppKit

@main
@MainActor
enum CurtainMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        Log.openFile(at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Curtain/curtain.log"))
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--input-probe") {
            let seconds = args.dropFirst(index + 1).first.flatMap(Double.init) ?? 120
            InputProbe.verbose = args.contains("--verbose")
            InputProbe.run(seconds: min(max(seconds, 5), 600))
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = CurtainController()
        app.delegate = controller
        app.run()
        withExtendedLifetime(controller) {}
    }
}

/// Menu bar controller and curtain state machine.
///
///   open --close--> closed (gamma zero, sleep guard) --hardware input / menu--> unlocking
///   unlocking --auth ok--> open;  unlocking --20 s idle--> closed
///   any state --system lock / sleep / quit / signal / safety timeout--> open
///   cleanup refused after guardian F --> recovering --guardian exit--> open / process exit
@MainActor
final class CurtainController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    enum State: String { case open, closed, unlocking, recovering }

    private static let unlockIdleTimeout: TimeInterval = 20
    /// After the user cancels Touch ID, ignore hand movement for a while: cancelling means "not now".
    private static let cancelCooldown: TimeInterval = 3
    /// Right after closing, the hand that clicked the menu is still on the trackpad: input is
    /// swallowed but does not open the unlock screen yet.
    private static let closeGrace: TimeInterval = 2
    private var ignoreHardwareUntil = Date.distantPast
    /// Opened from the menu (e.g. over UU): synthetic input then also counts as activity,
    /// because remote keystrokes may not come from a hardware source.
    private var unlockFromMenuSession = false

    private let blackout = GammaBlackout()
    private let sleepGuard = SleepGuard()
    private let unlockUI = UnlockUI()
    private var hardwareMonitor: HardwareActivityMonitor!
    /// Swallows physical input while closed; falls back to `hardwareMonitor` without Accessibility.
    private let inputGuard = InputGuard()
    private let recoveryWatchdog = RecoveryWatchdog()
    private var lastIdleRestart = Date.distantPast
    private var sessionWatcher: SessionWatcher?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem!
    private var closeItem: NSMenuItem!
    private var unlockItem: NSMenuItem!
    private var guardWarningItem: NSMenuItem!
    private var safetyTimer: Timer?
    private var idleTimer: Timer?
    private var signals: [DispatchSourceSignal] = []
    private(set) var state = State.open

    /// Development-only upper bound for a closed curtain; `defaults write local.zjf.curtain devSafetyTimeoutSeconds 0` disables it.
    private var safetyTimeout: TimeInterval {
        UserDefaults.standard.object(forKey: "devSafetyTimeoutSeconds") as? Double ?? 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGHUP, SIG_IGN)
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    guard self.forceOpen(reason: "signal \(number)") else { return }
                    NSApp.terminate(nil)
                }
            }
            source.resume()
            signals.append(source)
        }
        hardwareMonitor = HardwareActivityMonitor { [weak self] type in
            self?.hardwareActivity(kind: "\(type.rawValue)",
                                   isClick: [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type))
        }
        inputGuard.onGaveUp = { [weak self] in
            guard let self, self.state != .open else { return }
            self.hardwareMonitor.start() // keep waking on mouse input even though nothing is blocked
            self.refreshMenu()
        }
        inputGuard.onHardwareEvent = { [weak self] type in
            self?.hardwareActivity(kind: "\(type.rawValue)",
                                   isClick: [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type))
        }
        unlockUI.onSuccess = { [weak self] method in self?.unlocked(method: method) }
        unlockUI.onActivity = { [weak self] fromHardware in
            // Agent input reaching the panel must not keep the screen lit past the idle timeout.
            guard let self, fromHardware || self.unlockFromMenuSession else { return }
            self.restartIdleTimer()
        }
        unlockUI.onCancel = { [weak self] reason in
            guard let self else { return }
            self.ignoreHardwareUntil = Date().addingTimeInterval(Self.cancelCooldown)
            self.relock(reason: "\(reason) cooldown=\(Self.cancelCooldown)s")
        }
        sessionWatcher = SessionWatcher { [weak self] reason in
            self?.forceOpen(reason: reason)
        }
        recoveryWatchdog.onFailure = { [weak self] in self?.forceOpen(reason: "watchdog-lost") }
        blackout.onFailure = { [weak self] in self?.forceOpen(reason: "gamma-protection-lost") }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentChanged(reason: "display-configuration-changed", displaysChanged: true) }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentChanged(reason: "active-space-changed", displaysChanged: false) }
        }
        buildStatusItem()
        log("launched pid=\(getpid()) safetyTimeout=\(safetyTimeout)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        forceOpen(reason: "terminate")
        sessionWatcher?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        log("terminated")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        forceOpen(reason: "terminate-request") ? .terminateNow : .terminateCancel
    }

    // MARK: Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        closeItem = NSMenuItem(title: "拉上幕布", action: #selector(closeFromMenu), keyEquivalent: "")
        unlockItem = NSMenuItem(title: "解锁…", action: #selector(unlockFromMenu), keyEquivalent: "")
        [closeItem, unlockItem].forEach { $0.target = self; menu.addItem($0) }
        guardWarningItem = NSMenuItem(title: "未拦截键盘鼠标：需要在系统设置中给 Curtain 开启辅助功能", action: nil, keyEquivalent: "")
        guardWarningItem.isEnabled = false
        menu.addItem(guardWarningItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Curtain", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        refreshMenu()
    }

    private func refreshMenu() {
        closeItem.isEnabled = state == .open
        unlockItem.isEnabled = state == .closed
        guardWarningItem.isHidden = state == .open || inputGuard.isActive
        // Quitting restores the screen, so it needs the same authentication as unlocking.
        statusItem.menu?.items.last?.isEnabled = state == .open
        let symbol = state == .open ? "curtains.open" : "curtains.closed"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Curtain") {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = state == .open ? "幕" : "幕●"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshMenu() }

    @objc private func closeFromMenu() {
        // Let the menu finish dismissing before the screen goes dark.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.close() }
    }

    @objc private func unlockFromMenu() { beginUnlock(trigger: "menu") }

    @objc private func quit() {
        guard forceOpen(reason: "quit") else { return }
        NSApp.terminate(nil)
    }

    // MARK: Transitions

    private func setState(_ new: State, _ detail: String) {
        log("state \(state.rawValue) -> \(new.rawValue) \(detail)")
        state = new
        refreshMenu()
    }

    private func close() {
        guard state == .open else { return }
        BackdropArt.prepare() // render the unlock-screen wallpaper while nobody is waiting for it
        guard recoveryWatchdog.start() else {
            guard forceOpen(reason: "watchdog-start-failed") else { return }
            showCloseFailure("故障恢复保护未能启动。请重新安装 Curtain 后再试。")
            return
        }
        guard sleepGuard.acquire() else {
            guard forceOpen(reason: "sleep-guard-start-failed") else { return }
            showCloseFailure("无法阻止显示器自动睡眠，请稍后重试。")
            return
        }
        guard blackout.start() else {
            guard forceOpen(reason: "gamma-start-failed") else { return }
            if blackout.startFailure == .ownershipUnavailable {
                showCloseFailure("无法取得幕布控制权。请确认没有其他 Curtain 或实验进程正在使用幕布，再重试。")
            } else {
                showCloseFailure("无法确认所有显示器均已遮挡，已恢复显示。请检查外接显示器或显示驱动。")
            }
            return
        }
        if !inputGuard.setMode(.block) {
            hardwareMonitor.start() // still wake on mouse input, without blocking
        }
        if safetyTimeout > 0 {
            safetyTimer = Timer.scheduledTimer(withTimeInterval: safetyTimeout, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.forceOpen(reason: "dev-safety-timeout") }
            }
        }
        ignoreHardwareUntil = Date().addingTimeInterval(Self.closeGrace)
        setState(.closed, "menu grace=\(Self.closeGrace)s")
    }

    private func hardwareActivity(kind: String, isClick: Bool) {
        switch state {
        case .closed:
            guard Date() >= ignoreHardwareUntil else { return }
            beginUnlock(trigger: "hardware type=\(kind)")
        case .unlocking:
            if Date().timeIntervalSince(lastIdleRestart) > 1 { restartIdleTimer() }
            // The tap also sees clicks on Curtain's own controls; only clicks elsewhere retry Touch ID.
            if isClick, !unlockUI.controlsContainMouse() { unlockUI.hardwareClick() }
        case .open, .recovering:
            break
        }
    }

    private func beginUnlock(trigger: String) {
        guard state == .closed, !blackout.isProtectionFailed else { return }
        unlockFromMenuSession = trigger == "menu"
        setState(.unlocking, trigger)
        let shown = unlockUI.show(autoBiometrics: !unlockFromMenuSession) { [weak self] in
            guard let self, self.state == .unlocking else { return false }
            guard self.unlockUI.displayLayoutIsCurrent else {
                self.ignoreHardwareUntil = Date().addingTimeInterval(Self.closeGrace)
                self.relock(reason: "display-configuration-changed-before-show")
                return false
            }
            guard self.recoveryWatchdog.permitsUnlockPresentation() else {
                self.forceOpen(reason: "watchdog-presentation-denied")
                return false
            }
            self.blackout.stop() // backdrop already covers the desktop
            // Physical input reaches the unlock screen from now on; until here it stays swallowed,
            // so the waking click cannot land on an app hidden behind the backdrop.
            if self.inputGuard.isActive { self.inputGuard.setMode(.observe) }
            return true
        }
        if shown {
            restartIdleTimer()
        } else if state == .unlocking {
            setState(.closed, "unlock-ui-unavailable")
        }
    }

    private func restartIdleTimer() {
        guard state == .unlocking else { return }
        lastIdleRestart = Date()
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.unlockIdleTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.relock(reason: "unlock-idle-timeout") }
        }
    }

    private func relock(reason: String) {
        guard state == .unlocking else { return }
        idleTimer?.invalidate()
        idleTimer = nil
        guard blackout.start() else { // zero gamma before removing the backdrop
            forceOpen(reason: "gamma-relock-failed")
            return
        }
        if inputGuard.isActive { inputGuard.setMode(.block) }
        unlockUI.hide()
        setState(.closed, reason)
    }

    private func environmentChanged(reason: String, displaysChanged: Bool) {
        log("environment-change reason=\(reason) state=\(state.rawValue)")
        if state == .unlocking {
            // AppKit may also notify for a color/profile change; unchanged geometry still covers.
            if displaysChanged, unlockUI.displayLayoutIsCurrent { return }
            // Old frames/Space membership no longer prove coverage. Return to the display pipeline
            // before removing old windows; next wake builds the UI from a fresh screen snapshot.
            ignoreHardwareUntil = Date().addingTimeInterval(Self.closeGrace)
            relock(reason: reason)
        } else if state == .closed, displaysChanged {
            blackout.refresh(reason: reason)
        }
    }

    private func showCloseFailure(_ detail: String) {
        log("close-failed \(detail)")
        let alert = NSAlert()
        alert.messageText = "无法拉上幕布"
        alert.informativeText = detail
        alert.runModal()
    }

    private func unlocked(method: String) {
        guard state == .unlocking else { return }
        guard finishOpen() else { return }
        setState(.open, "unlocked method=\(method)")
    }

    @discardableResult
    private func forceOpen(reason: String) -> Bool {
        let wasOpen = state == .open
        guard finishOpen() else { return false }
        if !wasOpen { setState(.open, "forced reason=\(reason)") }
        return true
    }

    private func finishOpen() -> Bool {
        guard recoveryWatchdog.stop() else {
            idleTimer?.invalidate()
            idleTimer = nil
            safetyTimer?.invalidate()
            safetyTimer = nil
            if inputGuard.isActive { inputGuard.setMode(.block) }
            if state != .recovering { setState(.recovering, "watchdog-recovery-committed") }
            return false
        }
        idleTimer?.invalidate()
        idleTimer = nil
        safetyTimer?.invalidate()
        safetyTimer = nil
        inputGuard.stop()
        hardwareMonitor?.stop()
        blackout.stop()
        if unlockUI.isShowing { unlockUI.hide() }
        sleepGuard.release()
        return true
    }
}
