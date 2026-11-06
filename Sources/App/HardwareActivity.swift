import AppKit

/// Watches global input and reports only events produced by physical hardware.
/// Agents such as Codex Computer Use and remote tools post synthetic events, which carry the
/// posting process ID; hardware events carry PID 0. Mouse events need no permission;
/// key events reach global monitors only after Accessibility/Input Monitoring is granted.
@MainActor
final class HardwareActivityMonitor {
    private var monitor: Any?
    private var loggedSyntheticPIDs = Set<Int64>()
    private let onHardwareEvent: @MainActor (NSEvent.EventType) -> Void

    init(onHardwareEvent: @escaping @MainActor (NSEvent.EventType) -> Void) {
        self.onHardwareEvent = onHardwareEvent
    }

    func start() {
        guard monitor == nil else { return }
        loggedSyntheticPIDs.removeAll()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                           .scrollWheel, .keyDown, .flagsChanged]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        log("hardware-monitor started available=\(monitor != nil)")
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let pid = event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1
        let kind = "\(event.type.rawValue)"
        if pid == 0 {
            onHardwareEvent(event.type)
        } else if loggedSyntheticPIDs.insert(pid).inserted {
            log("hardware-monitor ignored-synthetic pid=\(pid) type=\(kind)")
        }
    }
}
