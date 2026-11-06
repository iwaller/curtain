import AppKit
@preconcurrency import LocalAuthentication
import OpenDirectory

/// Unlock screen in the style of the macOS 26 lock screen: blurred wallpaper with a large clock,
/// and the account picture, name and a Liquid Glass password capsule near the bottom.
///
/// Two windows: an opaque backdrop drawn before gamma is restored (so the desktop never shows),
/// which ignores mouse events so agent clicks still reach the apps underneath; and a transparent,
/// non-activating panel holding the controls.
@MainActor
final class UnlockUI: NSObject, NSTextFieldDelegate {
    var onSuccess: (@MainActor (String) -> Void)?
    /// Input reached the unlock UI. The flag is true for physical keyboard/mouse events
    /// (source PID 0); agent or remote-tool events carry their sender's PID.
    var onActivity: (@MainActor (_ fromHardware: Bool) -> Void)?
    /// The user chose "not now" (Touch ID cancel or Esc). The argument is a log reason.
    var onCancel: (@MainActor (_ reason: String) -> Void)?

    private var backdrops: [NSWindow] = []
    private var clocks: [(time: NSTextField, date: NSTextField)] = []
    private var clockTimer: Timer?
    private var panel: NSPanel?
    private var avatar: NSImageView?
    private var capsule: NSView?
    private var passwordField: NSSecureTextField?
    private var submitButton: NSButton?
    private var spinner: NSProgressIndicator?
    private var statusLabel: NSTextField?
    private var touchIDButton: NSButton?
    private var localMonitor: Any?
    private var keyInputLogged = false
    private var verifying = false
    private var biometricContext: LAContext?
    private struct ScreenLayout: Equatable {
        let id: UInt32?
        let frame: NSRect
        let scale: CGFloat
    }
    private var shownLayout: [ScreenLayout] = []
    private var shownOnlineDisplays: [CGDirectDisplayID]?

    var isShowing: Bool { panel != nil }
    var displayLayoutIsCurrent: Bool {
        shownLayout == Self.layout(of: NSScreen.screens)
            && shownOnlineDisplays == SystemDisplayGamma().onlineDisplays()?.sorted()
    }

    private static func layout(of screens: [NSScreen]) -> [ScreenLayout] {
        screens.map {
            ScreenLayout(id: ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                         frame: $0.frame, scale: $0.backingScaleFactor)
        }
    }

    private static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
    private static let panelWidth: CGFloat = 380

    // MARK: Lifecycle

    /// Shows the backdrop and controls. `ready` must authorize presentation before authentication.
    /// `autoBiometrics` is false for menu-triggered (remote) sessions: Touch ID is unusable over UU,
    /// and the system prompt would take keyboard focus away from the password field.
    @discardableResult
    func show(autoBiometrics: Bool, ready: @escaping @MainActor () -> Bool) -> Bool {
        guard !isShowing else { return ready() }
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? screens.first,
              !screens.isEmpty else {
            log("unlock-ui unavailable no-screens")
            return false
        }
        shownLayout = Self.layout(of: screens)
        shownOnlineDisplays = SystemDisplayGamma().onlineDisplays()?.sorted()
        backdrops = screens.map { makeBackdrop(for: $0) }
        updateClocks()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClocks() }
        }
        let panel = makePanel(remote: !autoBiometrics, screen: screen)
        self.panel = panel
        loadAvatar()
        keyInputLogged = false
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onActivity?(Self.isHardware(event))
                if event.type == .leftMouseDown, event.window === self.panel, !(self.panel?.isKeyWindow ?? false) {
                    log("unlock-ui panel-click regain-focus active=\(NSApp.isActive)")
                    self.focusPasswordField()
                }
                if event.type == .keyDown, !self.keyInputLogged {
                    self.keyInputLogged = true
                    log("unlock-ui key-input hardware=\(Self.isHardware(event))")
                }
            }
            return event
        }
        log("unlock-ui shown backdrops=\(backdrops.count) art=\(NSScreen.screens.map { BackdropArt.image(for: $0) != nil })")
        // Give WindowServer a moment to composite the backdrop before the caller restores gamma.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard self.panel === panel else { return }
            panel.orderFrontRegardless()
            self.focusPasswordField()
            guard ready() else { return }
            guard self.panel === panel else { return } // The caller may have returned to black.
            if autoBiometrics { self.startBiometrics() }
        }
        return true
    }

    /// Removes all windows. Callers must zero gamma first when returning to the black state.
    func hide() {
        biometricContext?.invalidate()
        biometricContext = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        clockTimer?.invalidate()
        clockTimer = nil
        panel?.orderOut(nil)
        panel = nil
        avatar = nil
        capsule = nil
        passwordField = nil
        submitButton = nil
        spinner = nil
        statusLabel = nil
        touchIDButton = nil
        backdrops.forEach { $0.orderOut(nil) }
        backdrops.removeAll()
        clocks.removeAll()
        shownLayout.removeAll()
        shownOnlineDisplays = nil
        verifying = false
        NSApp.hide(nil) // hand focus back to the app the agent was using
        log("unlock-ui hidden")
    }

    // MARK: Backdrop

    private func makeBackdrop(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.level = Self.level
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let content = BackdropArtView(image: BackdropArt.image(for: screen))
        let date = label("", size: 22, weight: .semibold, color: NSColor(white: 1, alpha: 0.85))
        let time = label("", size: 112, weight: .bold, color: NSColor(white: 1, alpha: 0.92), rounded: true)
        let clock = NSStackView(views: [date, time])
        clock.orientation = .vertical
        clock.spacing = -6
        clock.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(clock)
        NSLayoutConstraint.activate([
            clock.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            clock.topAnchor.constraint(equalTo: content.topAnchor, constant: screen.frame.height * 0.08),
        ])
        window.contentView = content
        clocks.append((time, date))
        window.orderFrontRegardless()
        window.display()
        return window
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jm")
        return f
    }()

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        f.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return f
    }()

    private func updateClocks() {
        let now = Date()
        let time = Self.timeFormat.string(from: now)
        let date = Self.dateFormat.string(from: now)
        for clock in clocks where clock.time.stringValue != time || clock.date.stringValue != date {
            clock.time.stringValue = time
            clock.date.stringValue = date
        }
    }

    // MARK: Controls

    private func makePanel(remote: Bool, screen: NSScreen) -> NSPanel {
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 300),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Do not set isFloatingPanel: its setter resets the level to .floating (3), which put the
        // panel behind the backdrop (1000) in the first build.
        panel.level = NSWindow.Level(rawValue: Self.level.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.appearance = NSAppearance(named: .darkAqua) // light caret and text
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.onEscape = { [weak self] in
            guard let self, !self.verifying else { return }
            log("unlock-ui escape")
            self.onCancel?("escape")
        }

        let avatar = NSImageView()
        avatar.image = symbol("person.crop.circle.fill", size: 60)
        avatar.contentTintColor = NSColor(white: 1, alpha: 0.6)
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 32
        avatar.layer?.masksToBounds = true
        avatar.widthAnchor.constraint(equalToConstant: 64).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let name = label(NSFullUserName().isEmpty ? NSUserName() : NSFullUserName(),
                         size: 15, weight: .semibold, color: .white)

        let field = NSSecureTextField()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: remote ? String(localized: "Enter login password") : String(localized: "Touch ID or login password"),
            attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.6), .font: NSFont.systemFont(ofSize: 13)])
        field.target = self
        field.action = #selector(submitPassword)
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true

        let submit = NSButton(image: symbol("arrow.right.circle.fill", size: 20), target: self,
                              action: #selector(submitPassword))
        submit.isBordered = false
        submit.contentTintColor = .white
        submit.isHidden = true // appears once something is typed, like the system lock screen
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let capsuleContent = NSView()
        for view in [field, submit, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            capsuleContent.addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: capsuleContent.leadingAnchor, constant: 16),
            field.centerYAnchor.constraint(equalTo: capsuleContent.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: capsuleContent.trailingAnchor, constant: -36),
            submit.trailingAnchor.constraint(equalTo: capsuleContent.trailingAnchor, constant: -7),
            submit.centerYAnchor.constraint(equalTo: capsuleContent.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: submit.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: submit.centerYAnchor),
        ])
        let capsule = glassCapsule(containing: capsuleContent, cornerRadius: 17)
        capsule.widthAnchor.constraint(equalToConstant: 236).isActive = true
        capsule.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let status = label("", size: 12, weight: .medium, color: NSColor(red: 1, green: 0.62, blue: 0.58, alpha: 1))
        status.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let touchID = NSButton(title: String(localized: "Use Touch ID"), image: symbol("touchid", size: 14), target: self,
                               action: #selector(retryBiometrics))
        touchID.isBordered = false
        touchID.imagePosition = .imageLeading
        touchID.imageHugsTitle = true
        touchID.font = .systemFont(ofSize: 12, weight: .medium)
        touchID.contentTintColor = NSColor(white: 1, alpha: 0.85)
        touchID.shadow = textShadow()
        touchID.isHidden = !LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)

        let footer = label(String(localized: "Screen turns black after 20 seconds of inactivity · Esc to cancel"), size: 11, weight: .regular,
                           color: NSColor(white: 1, alpha: 0.55))

        let stack = NSStackView(views: [avatar, name, capsule, status, touchID, footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(10, after: avatar)
        stack.setCustomSpacing(14, after: name)
        stack.setCustomSpacing(6, after: capsule)
        stack.setCustomSpacing(4, after: status)
        stack.setCustomSpacing(14, after: touchID)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.wantsLayer = true
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.panelWidth),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        ])
        panel.contentView = root
        let size = root.fittingSize
        let frame = screen.frame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.07,
                              width: size.width, height: size.height), display: true)

        self.avatar = avatar
        self.capsule = capsule
        passwordField = field
        submitButton = submit
        self.spinner = spinner
        statusLabel = status
        touchIDButton = touchID
        return panel
    }

    /// Liquid Glass on macOS 26+, a HUD material before that.
    private func glassCapsule(containing content: NSView, cornerRadius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    /// The account picture from the local directory, if there is one; the placeholder stays otherwise.
    private func loadAvatar() {
        let user = NSUserName()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = Self.accountPicture(user: user)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let data, let image = NSImage(data: data), let avatar = self.avatar else { return }
                    avatar.image = image
                    avatar.imageScaling = .scaleAxesIndependently
                    avatar.contentTintColor = nil
                }
            }
        }
    }

    nonisolated private static func accountPicture(user: String) -> Data? {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes)),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: user, attributes: nil)
        else { return nil }
        if let photo = (try? record.values(forAttribute: kODAttributeTypeJPEGPhoto))?.first as? Data {
            return photo
        }
        if let path = (try? record.values(forAttribute: "dsAttrTypeStandard:Picture"))?.first as? String {
            return FileManager.default.contents(atPath: path)
        }
        return nil
    }

    func controlTextDidChange(_ notification: Notification) {
        let empty = passwordField?.stringValue.isEmpty ?? true
        if !verifying { submitButton?.isHidden = empty }
        if statusLabel?.stringValue.isEmpty == false { statusLabel?.stringValue = "" }
    }

    private func setVerifying(_ on: Bool) {
        verifying = on
        passwordField?.isEnabled = !on
        submitButton?.isHidden = true
        if on { spinner?.startAnimation(nil) } else { spinner?.stopAnimation(nil) }
    }

    private func shake() {
        // Like the system lock screen: only the password capsule shakes, no message.
        capsule?.wantsLayer = true
        guard let layer = capsule?.layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -12, 12, -9, 9, -5, 5, 0]
        animation.duration = 0.42
        layer.add(animation, forKey: "shake")
    }

    // MARK: Focus

    /// Puts the caret in the password field. The panel is non-activating, so it can become key
    /// even when macOS refuses to activate Curtain (as it does for menu-triggered sessions).
    private func focusPasswordField() {
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(passwordField)
        log("unlock-ui focus active=\(NSApp.isActive) key=\(panel.isKeyWindow) level=\(panel.level.rawValue)")
    }

    /// Whether the pointer is over the unlock controls (the transparent panel near the bottom).
    func controlsContainMouse() -> Bool {
        panel?.frame.contains(NSEvent.mouseLocation) ?? false
    }

    nonisolated static func isHardware(_ event: NSEvent?) -> Bool {
        event?.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) == 0
    }

    // MARK: Touch ID

    private func startBiometrics() {
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Enter Password")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            log("unlock-ui biometrics-unavailable code=\(error?.code ?? 0)")
            touchIDButton?.isHidden = true
            return
        }
        biometricContext = context
        statusLabel?.stringValue = ""
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: String(localized: "unlock the privacy screen")) { success, error in
            let code = (error as NSError?)?.code ?? 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.biometricContext === context else { return }
                    self.biometricContext = nil
                    if success {
                        self.onSuccess?("touch-id")
                    } else if code == LAError.userCancel.rawValue {
                        log("unlock-ui biometrics-cancelled")
                        self.onCancel?("touch-id-cancelled")
                    } else {
                        // Password fallback, too many failures, or the system dismissed the prompt:
                        // keep the controls; a click starts Touch ID again.
                        log("unlock-ui biometrics-failed code=\(code)")
                        self.statusLabel?.stringValue = Self.biometricMessage(code: code)
                        self.focusPasswordField()
                    }
                }
            }
        }
    }

    private static func biometricMessage(code: Int) -> String {
        switch code {
        case LAError.userFallback.rawValue, LAError.systemCancel.rawValue, LAError.appCancel.rawValue: ""
        case LAError.biometryLockout.rawValue: String(localized: "Touch ID is locked. Enter your password.")
        case LAError.authenticationFailed.rawValue: String(localized: "Fingerprint not recognized. Try again or enter your password.")
        default: String(localized: "Touch ID is unavailable. Enter your password.")
        }
    }

    /// A physical click outside the controls while no prompt is open starts Touch ID again.
    func hardwareClick() {
        guard isShowing, biometricContext == nil, !verifying, touchIDButton?.isHidden == false else { return }
        log("unlock-ui biometrics-restart by-click")
        startBiometrics()
    }

    @objc private func retryBiometrics() {
        onActivity?(Self.isHardware(NSApp.currentEvent))
        guard biometricContext == nil, !verifying else { return }
        startBiometrics()
    }

    // MARK: Password

    @objc private func submitPassword() {
        onActivity?(Self.isHardware(NSApp.currentEvent))
        guard !verifying, let field = passwordField, !field.stringValue.isEmpty else { return }
        let password = field.stringValue
        field.stringValue = ""
        statusLabel?.stringValue = ""
        setVerifying(true)
        let user = NSUserName()
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Self.verifyLoginPassword(user: user, password: password)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.passwordField === field, self.verifying else { return }
                    if ok {
                        self.onSuccess?("password")
                    } else {
                        log("unlock-ui password-rejected")
                        // Slow down guessing.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            guard self.passwordField === field, self.verifying else { return }
                            self.setVerifying(false)
                            self.shake()
                            self.focusPasswordField()
                        }
                    }
                }
            }
        }
    }

    /// Verifies the current user's login password through OpenDirectory; nothing is stored.
    nonisolated private static func verifyLoginPassword(user: String, password: String) -> Bool {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: user, attributes: nil)
            try record.verifyPassword(password)
            return true
        } catch {
            return false
        }
    }

    // MARK: Helpers

    private func textShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                       rounded: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.shadow = textShadow()
        return field
    }

    private func symbol(_ name: String, size: CGFloat) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        return image.withSymbolConfiguration(.init(pointSize: size, weight: .regular)) ?? image
    }
}

private final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
