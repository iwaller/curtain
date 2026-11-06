import CoreGraphics
import Foundation

/// Blacks out every active display by zeroing its gamma transfer table.
/// The table is applied after WindowServer composition, so Space and full-screen
/// animations cannot slide it away. Quartz restores the tables when the process exits.
@MainActor
final class GammaBlackout {
    enum StartFailure { case ownershipUnavailable, monitorUnavailable, displayUnavailable }
    private let driver: any DisplayGamma
    private let lease: GammaLease
    private var watchdog: Timer?
    private var monitoringDisplays = false
    private var reapplyCount = 0
    /// Owns tables/lease, including a suspended failure awaiting authorized cleanup.
    private(set) var isActive = false
    /// A failed owner retains its tables/lease until the controller authorizes cleanup.
    private(set) var isProtectionFailed = false
    private(set) var startFailure: StartFailure?
    var onFailure: (() -> Void)?

    init(driver: (any DisplayGamma)? = nil, lease: GammaLease? = nil) {
        self.driver = driver ?? SystemDisplayGamma()
        self.lease = lease ?? GammaLease()
    }

    /// A failed start can own partial tables. The owner must authorize cleanup, then call stop().
    func start() -> Bool {
        startFailure = nil
        if isActive {
            guard !isProtectionFailed else {
                startFailure = .displayUnavailable
                return false
            }
            let success = apply(reason: "already-active", onlyIfNeeded: true)
            if !success { startFailure = .displayUnavailable; suspendAfterFailure() }
            return success
        }
        guard lease.acquire() else {
            startFailure = .ownershipUnavailable
            log("gamma-start-failed ownership-unavailable")
            return false
        }
        guard CGDisplayRegisterReconfigurationCallback(Self.reconfigured, Unmanaged.passUnretained(self).toOpaque()) == .success else {
            startFailure = .monitorUnavailable
            lease.release()
            log("gamma-start-failed reconfiguration-monitor-unavailable")
            return false
        }
        monitoringDisplays = true
        isActive = true
        reapplyCount = 0
        guard apply(reason: "start", onlyIfNeeded: false) else {
            startFailure = .displayUnavailable
            suspendAfterFailure()
            return false
        }
        // Night Shift, True Tone or ColorSync may rewrite the tables; check frequently.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(reason: "gamma-reset-detected") }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        return true
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        isProtectionFailed = false
        suspendMonitoring()
        driver.restore()
        let restored = (driver.onlineDisplays() ?? []).map { "\($0):\(driver.isBlack($0) ? "black" : "restored-or-unreadable")" }
        log("gamma-restored reapplied=\(reapplyCount) displays=\(restored.joined(separator: ","))")
        lease.release()
    }

    private func suspendMonitoring() {
        watchdog?.invalidate()
        watchdog = nil
        if monitoringDisplays {
            CGDisplayRemoveReconfigurationCallback(Self.reconfigured, Unmanaged.passUnretained(self).toOpaque())
            monitoringDisplays = false
        }
    }

    private func suspendAfterFailure() {
        isProtectionFailed = true
        suspendMonitoring()
        log("gamma-failed awaiting-owner-cleanup")
    }

    private func apply(reason: String, onlyIfNeeded: Bool) -> Bool {
        guard let displays = driver.onlineDisplays(), !displays.isEmpty else {
            log("gamma-unavailable reason=\(reason) no-online-displays")
            return false
        }
        var success = true
        for display in displays {
            if onlyIfNeeded && driver.isBlack(display) { continue }
            if onlyIfNeeded { reapplyCount += 1 }
            let result = driver.setBlack(display)
            let verified = driver.isBlack(display)
            log("gamma-zero reason=\(reason) display=\(display) result=\(result.rawValue) readback=\(verified ? "black" : "NOT-black")")
            if result != .success || !verified { success = false }
        }
        return success
    }

    /// Notify the owner before any restoration. A controller may need to wait for system lock.
    func refresh(reason: String) {
        guard isActive, !isProtectionFailed else { return }
        guard apply(reason: reason, onlyIfNeeded: true) else {
            log("gamma-protection-lost reason=\(reason)")
            suspendAfterFailure()
            if let onFailure { onFailure() } else { stop() } // Unguarded standalone/CLI fallback.
            return
        }
    }

    private static let reconfigured: CGDisplayReconfigurationCallBack = { display, flags, userInfo in
        guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
        let blackout = Unmanaged<GammaBlackout>.fromOpaque(userInfo).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard blackout.isActive else { return }
                blackout.refresh(reason: "reconfigured flags=\(flags.rawValue)")
            }
        }
    }

}
