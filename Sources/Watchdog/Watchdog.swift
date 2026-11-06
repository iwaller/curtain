import Foundation
import CoreGraphics
import Darwin

func watchdogLog(_ message: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    try? FileHandle.standardError.write(contentsOf: Data("\(formatter.string(from: Date())) watchdog \(message)\n".utf8))
}

@main
enum WatchdogMain {
    static func main() {
        signal(SIGHUP, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments == [CommandLine.arguments[0], "--request-lock"] {
            let guardian = getppid()
            guard guardian > 1 else { return }
            // A failed guardian must not leave an orphaned lock request running indefinitely.
            let parentExit = DispatchSource.makeProcessSource(identifier: guardian, eventMask: .exit, queue: .global())
            parentExit.setEventHandler { _exit(0) }
            parentExit.resume()
            guard getppid() == guardian else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { _exit(1) }
            // Refuse a stale/background-session request rather than locking another user's console.
            withExtendedLifetime(parentExit) {
                if SystemScreenLock.isOnConsole { SystemScreenLock.request() }
            }
            return
        }
        guard CommandLine.arguments.count == 1, getppid() > 1, SystemScreenLock.isAvailable else {
            watchdogLog("startup-refused lock-entry=\(SystemScreenLock.isAvailable)")
            exit(1)
        }
        let parent = getppid()
        var ready: UInt8 = 82
        guard Darwin.write(STDOUT_FILENO, &ready, 1) == 1 else { exit(1) }
        var deadline = HeartbeatDeadline(now: DispatchTime.now().uptimeNanoseconds)
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        while getppid() == parent {
            let result = poll(&descriptor, 1, 100)
            if result < 0 {
                if errno == EINTR { continue }
                break
            }
            if result > 0 {
                var bytes = [UInt8](repeating: 0, count: 256)
                let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0,
                      deadline.receive(Array(bytes.prefix(count)), now: DispatchTime.now().uptimeNanoseconds) else { break }
                if deadline.disarmed {
                    var ack: UInt8 = 68
                    _ = Darwin.write(STDOUT_FILENO, &ack, 1)
                    return
                }
            }
            if deadline.expired(at: DispatchTime.now().uptimeNanoseconds) { break }
        }
        guard getppid() == parent else { return } // Parent exited: never lock a later session or recycled PID.
        recover(parent: parent)
    }

    private static func recover(parent: pid_t) {
        guard getppid() == parent else { return }
        // Commit before requesting lock. Late disarm reads F and must not restore the desktop.
        // Do not SIGSTOP the parent: a guardian crash would otherwise leave it permanently paused.
        var committed: UInt8 = 70
        _ = Darwin.write(STDOUT_FILENO, &committed, 1)
        watchdogLog("heartbeat-lost parent=\(parent) recovery-committed; requesting system lock")
        let locker = Process()
        locker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        locker.arguments = ["--request-lock"]
        locker.standardInput = FileHandle.nullDevice
        locker.standardOutput = FileHandle.nullDevice
        locker.standardError = FileHandle.standardError
        if !SystemScreenLock.isLocked {
            do { try locker.run() }
            catch { watchdogLog("lock-launch-failed error=\(error)") }
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while getppid() == parent && !SystemScreenLock.isLocked && DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(50_000)
        }
        let locked = SystemScreenLock.isLocked
        if locker.isRunning { _ = kill(locker.processIdentifier, SIGKILL) }
        guard getppid() == parent else { return }
        // Recovery of display/input wins even if locking was unavailable or failed to confirm.
        watchdogLog("lock-confirmed=\(locked); terminating parent=\(parent)")
        if kill(parent, SIGKILL) != 0 {
            watchdogLog("kill-failed errno=\(errno)")
        }
    }
}
