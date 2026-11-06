import Foundation
import CoreGraphics
import Darwin

@MainActor
final class SimulatedDisplayGamma: DisplayGamma {
    var displays: [CGDirectDisplayID]? = [1, 2]
    var black: Set<CGDirectDisplayID> = []
    var failing: Set<CGDirectDisplayID> = []
    var ignored: Set<CGDirectDisplayID> = []
    var attempts: [CGDirectDisplayID] = []
    var restores = 0

    func onlineDisplays() -> [CGDirectDisplayID]? { displays }
    func setBlack(_ display: CGDirectDisplayID) -> CGError {
        attempts.append(display)
        if failing.contains(display) { return .failure }
        if !ignored.contains(display) { black.insert(display) }
        return .success
    }
    func isBlack(_ display: CGDirectDisplayID) -> Bool { black.contains(display) }
    func restore() { restores += 1; black.removeAll() }
}

@main
@MainActor
enum DisplayGammaTests {
    static func main() {
        if CommandLine.arguments == [CommandLine.arguments[0], "--hold-default-lease"] {
            let lease = GammaLease()
            guard lease.acquire() else { exit(7) }
            FileHandle.standardOutput.write(Data("OWNED\n".utf8))
            withExtendedLifetime(lease) { Thread.sleep(forTimeInterval: 60) }
            return
        }
        if CommandLine.arguments.count == 3, ["--try-lease", "--hold-lease"].contains(CommandLine.arguments[1]) {
            let lease = GammaLease(url: URL(fileURLWithPath: CommandLine.arguments[2]))
            guard lease.acquire() else { exit(7) }
            if CommandLine.arguments[1] == "--hold-lease" {
                FileHandle.standardOutput.write(Data("OWNED\n".utf8))
                withExtendedLifetime(lease) { Thread.sleep(forTimeInterval: 60) }
            }
            exit(0)
        }
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("artifacts/gamma-lease-tests/\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let leaseURL = folder.appendingPathComponent("owner.lock")
        func make(_ driver: SimulatedDisplayGamma) -> GammaBlackout {
            GammaBlackout(driver: driver, lease: GammaLease(url: leaseURL))
        }
        func childAcquires() -> Bool {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--try-lease", leaseURL.path]
            try! child.run()
            child.waitUntilExit()
            precondition(child.terminationStatus == 0 || child.terminationStatus == 7)
            return child.terminationStatus == 0
        }
        let owner = GammaLease(url: leaseURL)
        precondition(owner.acquire() && !childAcquires())
        owner.release()
        precondition(childAcquires())
        let holder = Process(), ready = Pipe()
        holder.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        holder.arguments = ["--hold-lease", leaseURL.path]
        holder.standardOutput = ready
        try! holder.run()
        precondition(ready.fileHandleForReading.readData(ofLength: 6) == Data("OWNED\n".utf8))
        precondition(!owner.acquire())
        _ = kill(holder.processIdentifier, SIGKILL)
        holder.waitUntilExit()
        precondition(owner.acquire()) // Crash releases ownership without removing/replacing the inode.
        owner.release()

        let shared = SimulatedDisplayGamma()
        let first = make(shared), second = make(shared)
        precondition(first.start() && !second.start() && second.startFailure == .ownershipUnavailable)
        second.stop() // A rejected owner must never restore the active owner's tables.
        precondition(shared.black == [1, 2] && shared.restores == 0)
        first.stop()
        precondition(second.start())
        second.stop()

        let driver = SimulatedDisplayGamma()
        let blackout = make(driver)
        var failures = 0
        blackout.onFailure = { [weak blackout] in failures += 1; blackout?.stop() }
        precondition(blackout.start() && driver.black == [1, 2])
        precondition(blackout.start() && driver.attempts == [1, 2])

        driver.displays = [1, 2, 3]
        precondition(blackout.start()) // Relocking an already-black session must cover a newly attached display.
        precondition(driver.black == [1, 2, 3] && driver.attempts == [1, 2, 3])
        driver.displays = [1, 3]
        blackout.refresh(reason: "test-detach")
        precondition(driver.attempts == [1, 2, 3] && failures == 0)

        // A menu/tracking run loop must continue correcting tables, even outside default mode.
        driver.black.remove(1)
        let tracking = RunLoop.Mode("CurtainGammaTestTrackingMode")
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: tracking.rawValue as CFString))
        let until = Date().addingTimeInterval(0.16)
        while Date() < until { RunLoop.main.run(mode: tracking, before: until) }
        precondition(driver.black.contains(1) && driver.attempts.last == 1)

        driver.black.remove(3)
        driver.failing.insert(3)
        blackout.refresh(reason: "test-runtime-write-failure")
        precondition(!blackout.isActive && driver.black.isEmpty && driver.restores == 1 && failures == 1)
        blackout.refresh(reason: "test-after-failure")
        blackout.stop()
        precondition(failures == 1 && driver.restores == 1)

        for ignoredWrite in [false, true] {
            let bad = SimulatedDisplayGamma()
            if ignoredWrite { bad.ignored = [2] } else { bad.failing = [2] }
            let test = make(bad)
            precondition(!test.start() && test.isActive && test.isProtectionFailed && bad.restores == 0)
            test.stop() // start failure is rolled back by its owner, not inside start().
            precondition(!test.isActive && bad.black.isEmpty && bad.restores == 1)
        }
        let unavailable = SimulatedDisplayGamma()
        let test = make(unavailable)
        precondition(test.start())
        unavailable.displays = nil
        test.refresh(reason: "test-enumeration-failure")
        precondition(!test.isActive && unavailable.black.isEmpty)
        unavailable.displays = []
        precondition(!test.start() && test.isActive && test.isProtectionFailed)
        test.stop()
        print("PASS simulated multi-display start/attach/detach, tracking timer, write/readback failure and rollback")
        print("PASS cross-process gamma ownership, rejected owner cannot restore, ownership transfers after release")
        print("No real gamma tables were changed; physical multi-display behavior remains unverified.")
    }
}
