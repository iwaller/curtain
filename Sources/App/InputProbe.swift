import ApplicationServices
import CoreGraphics
import Foundation

/// `Curtain --input-probe <seconds>`: records where input events come from, to check that physical
/// keyboard/trackpad events (also through Karabiner's virtual HID keyboard) can be told apart from
/// Codex and UU events. Uses a pass-through active tap, so it needs the same Accessibility
/// permission as the future input guard. Never logs which key was pressed, except Ctrl+Cmd+Q.
enum InputProbe {
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    nonisolated(unsafe) private static var tap: CFMachPort?
    nonisolated(unsafe) static var verbose = false

    static func run(seconds: TimeInterval) -> Never {
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        log("input-probe start seconds=\(Int(seconds)) accessibility=\(trusted) listen=\(CGPreflightListenEventAccess())")
        var mask: CGEventMask = 0
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseUp,
                                    .rightMouseDown, .leftMouseDragged, .scrollWheel]
        for type in types { mask |= 1 << type.rawValue }
        mask |= 1 << 14 // NX_SYSDEFINED: volume, brightness, media keys
        mask |= 1 << 29 // NSEventTypeGesture
        mask |= 1 << 30 // magnify
        mask |= 1 << 31 // swipe
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                              options: .defaultTap, eventsOfInterest: mask,
                                              callback: callback, userInfo: nil) else {
            log("input-probe tap-create-failed (grant Accessibility to Curtain, then run again)")
            exit(2)
        }
        tap = created
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, created, 0), .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        log("input-probe tap-ok")
        CFRunLoopRunInMode(.defaultMode, seconds, false)
        for (key, count) in counts.sorted(by: { $0.key < $1.key }) { log("input-probe total \(key) count=\(count)") }
        log("input-probe end")
        exit(0)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log("input-probe tap-disabled type=\(type.rawValue)")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let state = event.getIntegerValueField(.eventSourceStateID)
        let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
        var key = "type=\(type.rawValue) pid=\(pid) state=\(state)"
        if type == .keyDown || type == .keyUp || type == .flagsChanged { key += " kbType=\(keyboardType)" }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 12, // Q
           event.flags.contains([.maskControl, .maskCommand]) {
            log("input-probe ctrl-cmd-q pid=\(pid) state=\(state)")
        }
        counts[key, default: 0] += 1
        if counts[key] == 1 { log("input-probe new \(key)") }
        // Every event except moves/drags/gesture streams, so agent activity can be lined up in time.
        if verbose, ![CGEventType.mouseMoved, .leftMouseDragged].contains(type), ![29, 30, 31].contains(type.rawValue) {
            log("input-probe event \(key)")
        }
        return Unmanaged.passUnretained(event)
    }
}
