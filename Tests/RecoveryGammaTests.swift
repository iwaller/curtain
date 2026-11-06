import Foundation
import CoreGraphics
import Darwin

@MainActor
final class RecoveryGammaDriver: DisplayGamma {
    var displays: [CGDirectDisplayID]? = [1, 2]
    var failing: Set<CGDirectDisplayID> = []
    var black: Set<CGDirectDisplayID> = []
    var restores = 0
    var writes = 0
    func onlineDisplays() -> [CGDirectDisplayID]? { displays }
    func setBlack(_ display: CGDirectDisplayID) -> CGError {
        writes += 1
        if failing.contains(display) { return .failure }
        black.insert(display)
        return .success
    }
    func isBlack(_ display: CGDirectDisplayID) -> Bool { black.contains(display) }
    func restore() { restores += 1; black.removeAll() }
}

@main
@MainActor
enum RecoveryGammaTests {
    static func main() {
        let args = CommandLine.arguments
        let scenario = args[2], policy = args[3]
        let leaseURL = URL(fileURLWithPath: args[4])
        let driver = RecoveryGammaDriver()
        let gamma = GammaBlackout(driver: driver, lease: GammaLease(url: leaseURL))
        let guardian = RecoveryWatchdog(helperURL: URL(fileURLWithPath: args[1]))
        var failureCallbacks = 0
        var deferred = false
        func finish() {
            guard guardian.stop() else { deferred = true; return }
            gamma.stop()
        }
        gamma.onFailure = { failureCallbacks += 1; finish() }
        guardian.onFailure = { finish() }

        // Relock begins with gamma stopped but a still-live privacy session/guardian.
        if scenario.hasPrefix("relock") { precondition(gamma.start()); gamma.stop() }
        precondition(guardian.start())
        if scenario.hasPrefix("refresh") || scenario.hasPrefix("active-start") { precondition(gamma.start()) }
        if policy != "normal" { Thread.sleep(forTimeInterval: 10.4) }
        let baseline = driver.restores
        if scenario.hasSuffix("enumeration") {
            driver.displays = nil
        } else {
            driver.black.remove(2)
            driver.failing = [2]
        }
        if scenario.hasPrefix("refresh") {
            gamma.refresh(reason: "combined-regression")
        } else {
            precondition(!gamma.start())
            // Both first-close and relock callers must ask the guardian before rollback.
            finish()
        }
        if policy == "normal" {
            precondition(!deferred && driver.restores == baseline + 1 && !gamma.isActive && !gamma.isProtectionFailed)
            let released = GammaLease(url: leaseURL)
            precondition(released.acquire())
            released.release()
            print("PASS normal failure cleanup \(scenario)")
            return
        }

        precondition(deferred && driver.restores == baseline && gamma.isActive && gamma.isProtectionFailed)
        let contender = GammaLease(url: leaseURL)
        precondition(!contender.acquire()) // Retain ownership while cleanup is refused.
        let writes = driver.writes, callbacks = failureCallbacks
        gamma.refresh(reason: "must-not-repeat")
        precondition(!gamma.start())
        RunLoop.main.run(until: Date().addingTimeInterval(0.16))
        precondition(driver.restores == baseline && driver.writes == writes && failureCallbacks == callbacks)
        if scenario.hasPrefix("refresh") || scenario.hasPrefix("active-start") || scenario.hasSuffix("write") {
            precondition(driver.black.contains(1)) // Still-valid gamma must remain untouched.
        }
        FileHandle.standardOutput.write(Data("HELD_UNTIL_GUARDIAN_DECISION \(scenario) restores=\(driver.restores)\n".utf8))

        if policy == "guardian-exit" {
            // The only direct child is this test's guardian (pgrep excludes itself).
            let query = Process(), pipe = Pipe()
            query.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            query.arguments = ["-P", String(getpid())]
            query.standardOutput = pipe
            try! query.run()
            query.waitUntilExit()
            let pid = Int32(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines))!
            precondition(kill(pid, SIGKILL) == 0)
            let until = Date().addingTimeInterval(2)
            while gamma.isActive && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            precondition(!gamma.isActive && !gamma.isProtectionFailed && driver.restores == baseline + 1)
            precondition(contender.acquire())
            contender.release()
            print("PASS guardian exit permits exactly one deferred rollback")
            return
        }
        Thread.sleep(forTimeInterval: 5)
        preconditionFailure("Committed guardian should end this disposable test process")
    }
}
