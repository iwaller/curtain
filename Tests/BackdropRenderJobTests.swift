import AppKit
import Darwin

enum BackdropRenderJobTests {
    static func run(in directory: URL) throws {
        let real = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CurtainRenderer")
        let fake = URL(fileURLWithPath: "build/fake-backdrop-renderer")
        let size = CGSize(width: 300, height: 200)
        let fixture = directory.appendingPathComponent("fixture.png")
        let direct = BackdropRenderer.render(url: fixture, size: size)!
        let child = BackdropRenderJob(helper: real).render(url: fixture, size: size)!
        precondition(BackdropArtTests.rgba(direct) == BackdropArtTests.rgba(child))
        let valid = BackdropPacket.encode(direct)!
        precondition(BackdropPacket.decode(valid, requested: size) != nil)
        for offset in [0, 4, 8, 12, 16, 20, 27] {
            var bad = valid; bad[offset] ^= 1
            precondition(BackdropPacket.decode(bad, requested: size) == nil)
        }
        precondition(BackdropPacket.decode(valid.dropLast(), requested: size) == nil)
        precondition(BackdropPacket.decode(valid + Data([0]), requested: size) == nil)
        precondition(BackdropPacket.decode(valid, requested: CGSize(width: 1, height: 1)) == nil)
        print("PASS renderer round-trip pixels and malformed/version/format/dimension/stride/alpha/length rejection")
        precondition(BackdropRenderJob(helper: directory.appendingPathComponent("absent")).render(url: fixture, size: size) == nil)
        let tampered = directory.appendingPathComponent("tampered-renderer")
        try? FileManager.default.removeItem(at: tampered)
        try FileManager.default.copyItem(at: real, to: tampered)
        let file = try FileHandle(forWritingTo: tampered)
        try file.seekToEnd(); try file.write(contentsOf: Data([0])); try file.close()
        precondition(BackdropRenderJob(helper: tampered).render(url: fixture, size: size) == nil)
        let cancelled = BackdropRenderJob(helper: fake)
        cancelled.cancel()
        precondition(cancelled.render(url: fixture, size: size) == nil)
        print("PASS missing/tampered helper and cancellation before launch")
        for mode in ["crash", "nonzero", "oversize", "corrupt", "hang", "valid-hang", "cancel"] {
            let input = directory.appendingPathComponent(mode)
            let pidURL = URL(fileURLWithPath: input.path + ".pid")
            try? FileManager.default.removeItem(at: pidURL)
            let job = BackdropRenderJob(helper: fake, timeout: 0.6)
            if mode == "cancel" { DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { job.cancel() } }
            let start = Date()
            precondition(job.render(url: input, size: CGSize(width: 2, height: 2)) == nil)
            precondition(Date().timeIntervalSince(start) < 2)
            let pid = Int32(try String(contentsOf: pidURL, encoding: .utf8))!
            precondition(kill(pid, 0) == -1 && errno == ESRCH, "Worker must be reaped: \(mode)")
            print("PASS \(mode): gradient fallback and owned child reaped")
        }
    }
}
