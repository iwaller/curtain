import Foundation
import CoreGraphics
import Security
import Darwin

/// Cancellation never waits on the main thread. All process and pipe work stays on the art queue.
final class BackdropRenderJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let helper: URL
    private let timeout: TimeInterval

    init(helper: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CurtainRenderer"),
         timeout: TimeInterval = 5) {
        self.helper = helper
        self.timeout = timeout
    }

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func render(url: URL, size: CGSize) -> CGImage? {
        guard !isCancelled, BackdropPacket.dimensions(size) != nil,
              FileManager.default.isExecutableFile(atPath: helper.path) else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(helper as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) == errSecSuccess,
              !isCancelled else { return nil }
        let process = Process()
        let pipe = Pipe()
        let exited = DispatchSemaphore(value: 0)
        process.executableURL = helper
        process.arguments = [url.path, String(Double(size.width)), String(Double(size.height))]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in exited.signal() }
        defer {
            // Only this owned child is terminated; never target other app/helper instances.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            if process.processIdentifier > 0 { _ = exited.wait(timeout: .now() + 1) }
            process.terminationHandler = nil
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        do { try process.run(); try pipe.fileHandleForWriting.close() }
        catch { return nil }
        let fd = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        var eof = false
        while !isCancelled && ProcessInfo.processInfo.systemUptime < deadline {
            if eof {
                if !process.isRunning {
                    guard process.terminationStatus == 0 else { return nil }
                    return BackdropPacket.decode(data, requested: size)
                }
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, 25)
            if ready < 0 { if errno == EINTR { continue }; return nil }
            if ready == 0 { continue }
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { eof = true }
            else if count > 0 {
                guard data.count + count <= BackdropPacket.maximumBytes else { return nil }
                data.append(contentsOf: buffer.prefix(count))
            } else if errno != EAGAIN && errno != EINTR { return nil }
        }
        return nil
    }
}
