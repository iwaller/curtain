import Foundation

/// Timestamped log line to stdout and, when configured, to a log file.
/// Never logs page content, passwords or accessibility trees.
enum Log {
    nonisolated(unsafe) static var file: FileHandle?

    static func openFile(at url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        file = try? FileHandle(forWritingTo: url)
        _ = try? file?.seekToEnd()
    }
}

func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = "\(formatter.string(from: Date())) \(message)\n"
    // Diagnostics must not abort display/input recovery if a pipe closes or the log disk is full.
    try? FileHandle.standardOutput.write(contentsOf: Data(line.utf8))
    try? Log.file?.write(contentsOf: Data(line.utf8))
}
