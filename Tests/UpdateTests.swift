import AppKit

@main
struct UpdateTests {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let currentApp = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let source = try UpdateSource(api: URL(string: "https://example.test:8300/api/releases/latest")!,
                                      page: URL(string: "https://example.test:8300/curtain/releases")!)
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label)
            passed += 1
            print("PASS \(label)")
        }
        func rejects(_ label: String, _ action: () throws -> Void) {
            do { try action(); fatalError("Accepted: \(label)") }
            catch { passed += 1; print("PASS \(label)") }
        }
        let old = AppVersion("0.1.0")!, next = AppVersion("0.2.0")!
        check(AppVersion("v1.10")! > AppVersion("1.9.9")!, "numeric version comparison")
        check(AppVersion("1.2") == AppVersion("V1.2.0"), "zero-padded equality")
        for invalid in ["", "v", "+1", "1.-1", "1..2", "1.0-beta", "１.０", "999999999999999999999999"] {
            check(AppVersion(invalid) == nil, "reject malformed version \(invalid)")
        }
        check(source.accepts(URL(string: "https://example.test:8300/attachments/1")!), "same-origin HTTPS asset")
        for invalid in ["http://example.test:8300/a", "https://other.test:8300/a", "https://example.test/a",
                        "https://user:password@example.test:8300/a", "https://example.test:8300/a#fragment", "file:///tmp/a"] {
            check(!source.accepts(URL(string: invalid)!), "reject unsafe URL \(invalid)")
        }
        func release(_ changes: [String: Any] = [:]) throws -> UpdateRelease {
            var json: [String: Any] = ["tag_name": "v0.2.0", "html_url": source.page.absoluteString,
                                       "draft": false, "prerelease": false, "body": "Notes",
                                       "assets": [["name": "Curtain.zip", "browser_download_url": "https://example.test:8300/attachments/zip"]]]
            json.merge(changes) { _, new in new }
            return try UpdateRelease.parse(JSONSerialization.data(withJSONObject: json), source: source)
        }
        let valid = try release()
        let validPackageURL = try valid.packageURL(source: source)
        check(validPackageURL.host == "example.test", "stable release and package parsed")
        rejects("draft release") { _ = try release(["draft": true]) }
        rejects("prerelease") { _ = try release(["prerelease": true]) }
        rejects("invalid release tag") { _ = try release(["tag_name": "0.2.0-beta"]) }
        rejects("foreign release page") { _ = try release(["html_url": "https://other.test/release"]) }
        rejects("missing asset") { _ = try release(["assets": []]).packageURL(source: source) }
        rejects("unsafe asset") {
            _ = try release(["assets": [["name": "Curtain.zip", "browser_download_url": "file:///tmp/package.zip"]]]).packageURL(source: source)
        }
        let stage = root.appendingPathComponent("roundtrip")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let unpacked = try UpdatePackage.unpack(root.appendingPathComponent("valid.zip"), into: stage)
        let team = UpdatePackage.teamID(of: currentApp)
        if let team {
            try UpdatePackage.verify(unpacked, expected: next, current: old, team: team)
            check(true, "system tar round-trip preserves real developer and nested signatures")
            rejects("package differs from release version") { try UpdatePackage.verify(unpacked, expected: AppVersion("0.3")!, current: old, team: team) }
            rejects("package is not newer") { try UpdatePackage.verify(unpacked, expected: next, current: next, team: team) }
            rejects("different developer identity") { try UpdatePackage.verify(unpacked, expected: next, current: old, team: "OTHERTEAM") }
            for fixture in ["wrong-id", "incompatible", "tampered", "tampered-helper", "missing-helper", "adhoc"] {
                rejects("reject \(fixture) package") { try UpdatePackage.verify(root.appendingPathComponent("\(fixture)/Curtain.app"), expected: next, current: old, team: team) }
            }
        } else { print("SKIP developer-signed acceptance: current build is ad-hoc") }
        rejects("ad-hoc current identity cannot authorize install") { try UpdatePackage.verify(unpacked, expected: next, current: old, team: nil) }
        for name in ["traversal", "absolute", "symlink", "hardlink", "foreign-root"] {
            let staging = root.appendingPathComponent("extract-\(name)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            rejects("reject \(name) archive before extracting") {
                _ = try UpdatePackage.unpack(root.appendingPathComponent("\(name).zip"), into: staging)
            }
            check(!FileManager.default.fileExists(atPath: staging.appendingPathComponent("unpacked").path), "\(name) creates no extraction output")
        }
        let manager = FileManager.default
        let original = root.appendingPathComponent("swap/Live.app")
        let candidate = root.appendingPathComponent("swap/Next.app")
        try manager.createDirectory(at: original, withIntermediateDirectories: true)
        try manager.createDirectory(at: candidate, withIntermediateDirectories: true)
        let marker = "marker"
        try Data("old".utf8).write(to: original.appendingPathComponent(marker))
        try Data("new".utf8).write(to: candidate.appendingPathComponent(marker))
        func contents(_ url: URL) -> String { String(data: try! Data(contentsOf: url.appendingPathComponent(marker)), encoding: .utf8)! }
        rejects("privacy session blocks final exchange") { try UpdatePackage.exchange(original, with: candidate, permitted: { false }) }
        check(contents(original) == "old" && contents(candidate) == "new", "privacy refusal leaves both trees intact")
        let cancelled = Task { @MainActor in
            try UpdatePackage.exchange(original, with: candidate, permitted: { true })
        }
        cancelled.cancel()
        do { try await cancelled.value; fatalError("Cancelled install succeeded") }
        catch is CancellationError { check(contents(original) == "old", "cancel before exchange never installs") }
        rejects("OS exchange failure") { try UpdatePackage.exchange(original, with: root.appendingPathComponent("absent.app"), permitted: { true }) }
        check(contents(original) == "old", "OS exchange failure protects original app")
        rejects("restart setup failure rolls back swap") {
            try UpdatePackage.exchange(original, with: candidate, permitted: { true }, afterSwap: { throw UpdateFailure.restart })
        }
        check(contents(original) == "old" && contents(candidate) == "new", "restart failure restores both original trees")
        try UpdatePackage.exchange(original, with: candidate, permitted: { true })
        check(contents(original) == "new" && contents(candidate) == "old", "successful same-volume atomic exchange retains old bundle")

        var trusted = false
        let monitor = AccessibilityPermissionMonitor(trusted: { trusted })
        var changes = [Bool]()
        monitor.onChange = { changes.append($0) }
        monitor.refresh()
        trusted = true
        monitor.refresh()
        monitor.refresh()
        trusted = false
        monitor.refresh()
        check(changes == [true, false], "permission polling reports grants/revocations once, without installing a tap")
        let guide = PermissionGuide()
        guide.canPresent = { false }
        guide.show(trusted: false)
        check(!guide.isVisible, "closed/updating presentation guard creates no permission window")
        let updater = Updater()
        updater.canUpdate = { false }
        updater.checkForUpdates()
        check(!updater.isBusy, "closed/recovering state cannot start update or network work")
        print("All \(passed) update/permission checks passed; no live installation, gamma or lock changes.")
    }
}
