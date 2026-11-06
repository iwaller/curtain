import CoreGraphics
import Foundation

/// Blacks out every active display by zeroing its gamma transfer table.
/// The table is applied after WindowServer composition, so Space and full-screen
/// animations cannot slide it away. Quartz restores the tables when the process exits.
@MainActor
final class GammaBlackout {
    private static let tableSize: UInt32 = 256
    private let zeros = [CGGammaValue](repeating: 0, count: Int(GammaBlackout.tableSize))
    private var watchdog: Timer?
    private var reapplyCount = 0
    private(set) var isActive = false

    func start() {
        guard !isActive else { return }
        isActive = true
        reapplyCount = 0
        apply(reason: "start")
        CGDisplayRegisterReconfigurationCallback(Self.reconfigured, Unmanaged.passUnretained(self).toOpaque())
        // Night Shift, True Tone or ColorSync may rewrite the tables; check frequently.
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapplyIfReset() }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        watchdog?.invalidate()
        watchdog = nil
        CGDisplayRemoveReconfigurationCallback(Self.reconfigured, Unmanaged.passUnretained(self).toOpaque())
        CGDisplayRestoreColorSyncSettings()
        let restored = Self.activeDisplays().map { "\($0):\(Self.isBlack($0) ? "black" : "restored")" }
        log("gamma-restored reapplied=\(reapplyCount) displays=\(restored.joined(separator: ","))")
    }

    private func apply(reason: String) {
        for display in Self.activeDisplays() {
            let result = CGSetDisplayTransferByTable(display, Self.tableSize, zeros, zeros, zeros)
            log("gamma-zero reason=\(reason) display=\(display) result=\(result.rawValue) readback=\(Self.isBlack(display) ? "black" : "NOT-black")")
        }
    }

    private func reapplyIfReset() {
        for display in Self.activeDisplays() where !Self.isBlack(display) {
            reapplyCount += 1
            let result = CGSetDisplayTransferByTable(display, Self.tableSize, zeros, zeros, zeros)
            log("gamma-reset-detected display=\(display) reapply=\(reapplyCount) result=\(result.rawValue)")
        }
    }

    private static let reconfigured: CGDisplayReconfigurationCallBack = { display, flags, userInfo in
        guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
        let blackout = Unmanaged<GammaBlackout>.fromOpaque(userInfo).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard blackout.isActive else { return }
                blackout.apply(reason: "reconfigured flags=\(flags.rawValue)")
            }
        }
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private static func isBlack(_ display: CGDirectDisplayID) -> Bool {
        var red = [CGGammaValue](repeating: 1, count: Int(tableSize))
        var green = red, blue = red
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, tableSize, &red, &green, &blue, &sampleCount) == .success,
              sampleCount > 0 else { return false }
        let n = Int(sampleCount)
        return (red.prefix(n) + green.prefix(n) + blue.prefix(n)).allSatisfy { $0 < 0.001 }
    }
}
