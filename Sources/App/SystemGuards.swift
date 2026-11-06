import AppKit
import IOKit.pwr_mgt

/// Keeps the display (and therefore the login session and screen saver) awake while the curtain is closed.
@MainActor
final class SleepGuard {
    private var assertion: IOPMAssertionID = 0
    private var held = false

    @discardableResult
    func acquire() -> Bool {
        guard !held else { return true }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Curtain privacy screen keeps the session awake for agents" as CFString,
            &assertion)
        held = result == kIOReturnSuccess
        log("sleep-guard acquire result=\(result) held=\(held)")
        return held
    }

    func release() {
        guard held else { return }
        let result = IOPMAssertionRelease(assertion)
        held = false
        log("sleep-guard release result=\(result)")
    }
}

/// Reports events after which the curtain must open: the system lock screen or login window
/// would otherwise be invisible behind the zeroed gamma.
@MainActor
final class SessionWatcher {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(onInterrupt: @escaping @MainActor (String) -> Void) {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let sources: [(NotificationCenter, Notification.Name, String)] = [
            (distributed, Notification.Name("com.apple.screenIsLocked"), "screen-locked"),
            (workspace, NSWorkspace.willSleepNotification, "system-will-sleep"),
            (workspace, NSWorkspace.screensDidSleepNotification, "screens-did-sleep"),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, "session-resigned"),
        ]
        for (center, name, reason) in sources {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onInterrupt(reason) }
            }
            tokens.append((center, token))
        }
    }

    func invalidate() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens.removeAll()
    }
}
