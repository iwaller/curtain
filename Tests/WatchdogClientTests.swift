import Foundation
import Darwin

@main
@MainActor
enum WatchdogClientTests {
    static func main() {
        if CommandLine.arguments == [CommandLine.arguments[0], "--broken-log"] {
            signal(SIGPIPE, SIG_IGN)
            let pipe = Pipe()
            pipe.fileHandleForReading.closeFile()
            Log.file = pipe.fileHandleForWriting
            log("test-broken-log")
            Log.file = nil
            print("PASS broken log pipe cannot terminate recovery client")
            return
        }
        var deadline = HeartbeatDeadline(now: 100, timeout: 10)
        precondition(!deadline.expired(at: 109) && deadline.expired(at: 110))
        precondition(deadline.receive([72], now: 108))
        precondition(!deadline.expired(at: 117) && deadline.expired(at: 118))
        precondition(!deadline.receive([0], now: 200))
        precondition(deadline.receive([72, 68, 72], now: 109) && deadline.disarmed)

        let watchdog = RecoveryWatchdog(helperURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        var failures = 0
        watchdog.onFailure = { failures += 1 }
        if CommandLine.arguments[2] == "startup-failure" {
            precondition(!watchdog.start())
            watchdog.stop()
            precondition(failures == 0)
            print("PASS startup refusal/timeout leaves no active watchdog")
            return
        }
        precondition(watchdog.start())
        if CommandLine.arguments[2] == "closed-command-channel" {
            RunLoop.main.run(until: Date().addingTimeInterval(1.4))
            precondition(failures == 0 && !watchdog.stop())
            RunLoop.main.run(until: Date().addingTimeInterval(3))
            precondition(failures == 1 && watchdog.stop())
            print("PASS failed command write still respects F; only guardian exit permits failure recovery")
            return
        }
        if ["late-disarm", "recovery-helper-death"].contains(CommandLine.arguments[2]) {
            Thread.sleep(forTimeInterval: 10.4) // Stall only main; never SIGSTOP the client process.
            precondition(!watchdog.permitsUnlockPresentation())
            precondition(!watchdog.stop())
            precondition(!watchdog.stop())
            FileHandle.standardOutput.write(Data("RECOVERY_COMMITTED_MAIN_RUNNING\n".utf8))
            if CommandLine.arguments[2] == "late-disarm" {
                Thread.sleep(forTimeInterval: 10)
                preconditionFailure("Committed recovery must terminate the client")
            }
            RunLoop.main.run(until: Date().addingTimeInterval(5))
            precondition(failures == 1 && watchdog.stop())
            print("PASS guardian death after commit: client remains responsive and receives failure")
            return
        }
        if CommandLine.arguments[2] == "normal" {
            precondition(watchdog.permitsUnlockPresentation())
            precondition(!watchdog.start()) // Duplicate start must not replace the active session.
            RunLoop.main.run(until: Date().addingTimeInterval(12))
            precondition(failures == 0)
            precondition(watchdog.stop())
            // Old helper termination must not open a newly started curtain session.
            precondition(watchdog.start())
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            precondition(failures == 0)
            precondition(watchdog.stop())
            precondition(watchdog.stop())
            let missing = RecoveryWatchdog(helperURL: URL(fileURLWithPath: "/nonexistent/CurtainWatchdog"))
            precondition(!missing.start())
            print("PASS deadlines, heartbeat > 10s, disarm, restart, missing helper")
        } else {
            // The Python driver kills the helper while the main loop remains responsive.
            RunLoop.main.run(until: Date().addingTimeInterval(5))
            precondition(failures == 1)
            watchdog.stop()
            print("PASS helper death detected exactly once")
        }
    }
}
