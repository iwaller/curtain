import Foundation
import Darwin

/// Owns one helper per closed/unlocking session. Only the main run loop sends heartbeats.
/// The helper must acknowledge startup/disarm before we hide/restore the desktop.
@MainActor
final class RecoveryWatchdog {
    var onFailure: (() -> Void)?
    private let helperURL: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var timer: Timer?
    private var recoveryCommitted = false

    init(helperURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CurtainWatchdog")) {
        self.helperURL = helperURL
    }

    @discardableResult
    func start() -> Bool {
        guard process == nil else { return false }
        // A dead helper must turn a write into EPIPE, not terminate the application.
        signal(SIGPIPE, SIG_IGN)
        let child = Process()
        child.executableURL = helperURL
        let commands = Pipe(), replies = Pipe()
        child.standardInput = commands
        child.standardOutput = replies
        child.standardError = Log.file ?? FileHandle.standardError
        do { try child.run() }
        catch {
            log("watchdog launch-failed error=\(error)")
            return false
        }
        // Close the parent's copies of the child's endpoints, so EOF reflects real ownership.
        commands.fileHandleForReading.closeFile()
        replies.fileHandleForWriting.closeFile()
        process = child
        input = commands.fileHandleForWriting
        output = replies.fileHandleForReading
        guard receive() == 82, child.isRunning else { // R: ready, lock entry point available
            log("watchdog startup-failed")
            stop()
            return false
        }
        let descriptor = commands.fileHandleForWriting.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            stop()
            return false
        }
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.async {
                guard let self, self.process === child else { return }
                self.failed()
            }
        }
        let heartbeat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        timer = heartbeat
        log("watchdog ready pid=\(child.processIdentifier) heartbeat=1s timeout=10s")
        return true
    }

    /// False means recovery has already committed: keep the curtain in place until lock/exit.
    @discardableResult
    func stop() -> Bool {
        guard let child = process else { return true }
        if recoveryCommitted, child.isRunning { return false }
        if child.isRunning {
            _ = send(68) // D: request disarm; F may already be queued even if this write fails.
            let reply = receive()
            if reply == 70 { // F: fault committed; disarming can no longer cancel a lock request.
                markRecoveryCommitted()
                return false
            }
            if reply != 68 {
                log("watchdog disarm-failed; terminating helper")
                _ = kill(child.processIdentifier, SIGKILL)
            }
        }
        timer?.invalidate()
        timer = nil
        process = nil // Ignore this session's delayed termination callback, even after a new start.
        child.terminationHandler = nil
        input?.closeFile()
        output?.closeFile()
        input = nil
        output = nil
        recoveryCommitted = false
        log("watchdog disarmed")
        return true
    }

    /// Presentation keeps the guardian alive, but must not unblank after an already queued F.
    func permitsUnlockPresentation() -> Bool {
        guard let child = process, child.isRunning, !recoveryCommitted, let output else { return false }
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let result = poll(&descriptor, 1, 0)
        if result == 0 { return true }
        guard result > 0 else { return false }
        var byte: UInt8 = 0
        if Darwin.read(output.fileDescriptor, &byte, 1) == 1, byte == 70 { markRecoveryCommitted() }
        return false
    }

    private func markRecoveryCommitted() {
        recoveryCommitted = true
        timer?.invalidate()
        timer = nil
        log("watchdog recovery-committed; deferring display restoration")
    }

    private func beat() {
        guard let child = process else { return }
        if !child.isRunning || (!recoveryCommitted && !send(72)) { failed() } // H: heartbeat
    }

    private func failed() {
        log("watchdog connection-lost")
        guard stop() else { return }
        onFailure?()
    }

    private func send(_ byte: UInt8) -> Bool {
        guard let input else { return false }
        var byte = byte
        var count: Int
        repeat { count = Darwin.write(input.fileDescriptor, &byte, 1) } while count < 0 && errno == EINTR
        return count == 1
    }

    /// Startup/disarm only: bounded to two seconds, before any blackening/restoration.
    private func receive() -> UInt8? {
        guard let output else { return nil }
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let remaining = (deadline - min(deadline, DispatchTime.now().uptimeNanoseconds)) / 1_000_000
            let result = poll(&descriptor, 1, Int32(max(1, remaining)))
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { return nil }
            var byte: UInt8 = 0
            return Darwin.read(output.fileDescriptor, &byte, 1) == 1 ? byte : nil
        }
        return nil
    }
}
