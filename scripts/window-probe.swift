// Dumps Curtain's on-screen windows (no screen-recording permission needed for bounds/layer/alpha).
import CoreGraphics
import Foundation

let deadline = Date().addingTimeInterval(Double(CommandLine.arguments.dropFirst().first ?? "600") ?? 600)
var dumps = 0
while Date() < deadline && dumps < 3 {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Curtain" }
    let layers = mine.compactMap { $0[kCGWindowLayer as String] as? Int }
    if layers.contains(where: { $0 >= 1000 }) {
        dumps += 1
        print(ISO8601DateFormatter().string(from: Date()), "dump", dumps)
        for w in mine {
            let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            print("  id=\(w[kCGWindowNumber as String] ?? "?") layer=\(w[kCGWindowLayer as String] ?? "?") alpha=\(w[kCGWindowAlpha as String] ?? "?") sharing=\(w[kCGWindowSharingState as String] ?? "?") bounds=\(b["X"] ?? "?"),\(b["Y"] ?? "?") \(b["Width"] ?? "?")x\(b["Height"] ?? "?")")
        }
        Thread.sleep(forTimeInterval: 2)
    } else {
        Thread.sleep(forTimeInterval: 0.3)
    }
}
