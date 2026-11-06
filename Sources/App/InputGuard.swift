import AppKit
import CoreGraphics

/// Session-level event tap that swallows physical keyboard/mouse/trackpad input while the curtain
/// is closed, and only observes it while the unlock screen is up. Design: docs/subsystems/input-guard.md.
///
/// Physical input = source PID 0 and HID-system source state (verified on-site 2026-11-06, also
/// through Karabiner). Codex Computer Use events never reach this tap; UU events carry UU's PID.
///
/// Failure means "let input through": the tap lives on the main run loop, so if the main thread
/// hangs, macOS disables the tap; it is removed on exit; it never blocks while the screen is locked;
/// Ctrl+Cmd+Q always passes so the user can reach the system lock screen.
@MainActor
final class InputGuard {
    enum Mode: String { case off, block, observe }

    /// Physical input worth reacting to (wake / unlock-screen activity). Called asynchronously on main.
    var onHardwareEvent: (@MainActor (CGEventType) -> Void)?
    /// The tap kept being disabled and blocking was abandoned; the caller must wake by other means.
    var onGaveUp: (@MainActor () -> Void)?

    private(set) var mode = Mode.off
    var isActive: Bool { tap != nil && !gaveUp }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var blocked = 0
    private var disables: [Date] = []
    private var gaveUp = false
    private var lockedCache: (value: Bool, at: Date) = (false, .distantPast)
    private var notifyPending = false

    private static let maskTypes: [UInt32] = [
        CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue,
        CGEventType.mouseMoved.rawValue,
        CGEventType.leftMouseDown.rawValue, CGEventType.leftMouseUp.rawValue, CGEventType.leftMouseDragged.rawValue,
        CGEventType.rightMouseDown.rawValue, CGEventType.rightMouseUp.rawValue, CGEventType.rightMouseDragged.rawValue,
        CGEventType.otherMouseDown.rawValue, CGEventType.otherMouseUp.rawValue, CGEventType.otherMouseDragged.rawValue,
        CGEventType.scrollWheel.rawValue,
        14, // NX_SYSDEFINED: volume, brightness, media keys
        18, 19, 20, 29, 30, 31, 32, 34, // rotate, begin/end gesture, gesture, magnify, swipe, smart magnify, pressure
    ]
    private static let upTypes: Set<UInt32> = [
        CGEventType.keyUp.rawValue, CGEventType.leftMouseUp.rawValue,
        CGEventType.rightMouseUp.rawValue, CGEventType.otherMouseUp.rawValue,
    ]
    private static let qKeyCode: Int64 = 12

    /// Creates the tap (if needed) and switches mode. Returns false when the tap cannot be created
    /// (no Accessibility permission); the caller then falls back to observing without blocking.
    @discardableResult
    func setMode(_ new: Mode) -> Bool {
        if new == .off { stop(); return true }
        if tap == nil, !gaveUp, !create() { return false }
        if new != mode { log("input-guard mode \(mode.rawValue) -> \(new.rawValue)") }
        mode = new
        notifyPending = false
        return !gaveUp
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
            log("input-guard stopped blocked=\(blocked)")
        }
        tap = nil
        source = nil
        mode = .off
        blocked = 0
        disables.removeAll()
        gaveUp = false
        notifyPending = false
    }

    private func create() -> Bool {
        // The dedicated guide explains permission before opening Settings. Do not let tap
        // creation request a second system prompt during an already-dark privacy session.
        guard AXIsProcessTrusted() else {
            log("input-guard unavailable accessibility=false")
            return false
        }
        var mask: CGEventMask = 0
        for type in Self.maskTypes { mask |= 1 << CGEventMask(type) }
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: Self.callback, userInfo: info) else {
            log("input-guard unavailable accessibility=\(AXIsProcessTrusted())")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        // Main run loop on purpose: a hung main thread makes macOS disable the tap (fail open).
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        log("input-guard started")
        return true
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let guardian = Unmanaged<InputGuard>.fromOpaque(info).takeUnretainedValue()
        let pass = MainActor.assumeIsolated { guardian.shouldPass(type: type, event: event) }
        return pass ? Unmanaged.passUnretained(event) : nil
    }

    private func shouldPass(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleDisabled(type)
            return true
        }
        guard mode != .off, !gaveUp else { return true }
        let hardware = event.getIntegerValueField(.eventSourceUnixProcessID) == 0
            && event.getIntegerValueField(.eventSourceStateID) == Int64(CGEventSourceStateID.hidSystemState.rawValue)
        guard hardware else { return true }   // Codex, UU and other synthetic input
        guard !screenIsLocked() else { return true } // never stand between the user and the login screen

        let isUp = Self.upTypes.contains(type.rawValue)
        if mode == .observe {
            if !isUp { notify(type) }
            return true
        }
        // mode == .block
        if isUp { return true } // releases are harmless and avoid stuck keys/buttons
        if isLockShortcut(type: type, event: event) { return true }
        blocked += 1
        notify(type)
        return false
    }

    /// Ctrl+Cmd+Q and the modifier presses that build it, so the system lock screen stays reachable.
    private func isLockShortcut(type: CGEventType, event: CGEvent) -> Bool {
        let flags = event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn])
        switch type {
        case .flagsChanged:
            return flags.isSubset(of: [.maskControl, .maskCommand])
        case .keyDown:
            return event.getIntegerValueField(.keyboardEventKeycode) == Self.qKeyCode
                && flags == [.maskControl, .maskCommand]
        default:
            return false
        }
    }

    private func notify(_ type: CGEventType) {
        // Keep the callback short; coalesce bursts (mouse moves arrive at display rate).
        guard !notifyPending else { return }
        notifyPending = true
        DispatchQueue.main.async {
            self.notifyPending = false
            self.onHardwareEvent?(type)
        }
    }

    private func screenIsLocked() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lockedCache.at) < 0.5 { return lockedCache.value }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
        lockedCache = (locked, now)
        return locked
    }

    private func handleDisabled(_ type: CGEventType) {
        let now = Date()
        disables = disables.filter { now.timeIntervalSince($0) < 60 } + [now]
        if disables.count > 5 {
            gaveUp = true
            log("input-guard gave-up disabled=\(disables.count) in 60s; input passes")
            DispatchQueue.main.async { self.onGaveUp?() }
            return
        }
        log("input-guard re-enable after type=\(type.rawValue)")
        if let tap, mode != .off { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}
