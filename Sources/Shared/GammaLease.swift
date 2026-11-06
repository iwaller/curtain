import Foundation
import Darwin

/// One gamma owner per user across the menu app, CLI and duplicate instances.
/// Keep the file in place: unlinking a locked inode would permit two independent locks.
@MainActor
final class GammaLease {
    private let url: URL
    private var descriptor: Int32 = -1

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Curtain/gamma.lock")) {
        self.url = url
    }

    func acquire() -> Bool {
        guard descriptor < 0 else { return true }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { return false }
        let candidate = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard candidate >= 0 else { return false }
        var info = stat()
        guard fstat(candidate, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, flock(candidate, LOCK_EX | LOCK_NB) == 0 else {
            _ = close(candidate)
            return false
        }
        descriptor = candidate
        return true
    }

    func release() {
        guard descriptor >= 0 else { return }
        _ = close(descriptor) // Kernel releases the lock on exit/SIGKILL too; helpers do not inherit it.
        descriptor = -1
    }

    deinit { if descriptor >= 0 { _ = close(descriptor) } }
}
