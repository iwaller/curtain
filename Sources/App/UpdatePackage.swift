import Foundation
import Security
import Darwin
import CryptoKit

enum UpdateFailure: LocalizedError {
    case invalidRelease, noRelease, network, invalidPackage, invalidSignature, untrusted, incompatible, location, privacySession, restart, rollback

    var errorDescription: String? {
        switch self {
        case .invalidRelease: String(localized: "The release information is invalid. Try again later.")
        case .noRelease: String(localized: "No release is available yet. Check the release page or try again later.")
        case .network: String(localized: "Could not download the update. Check your network connection and try again.")
        case .invalidPackage: String(localized: "The update package is incomplete or does not match the release. The current app has not been replaced.")
        case .invalidSignature: String(localized: "The update signature is missing or invalid. The current app has not been replaced.")
        case .untrusted: String(localized: "The update package failed its integrity checks. The current app has not been replaced.")
        case .incompatible: String(localized: "The update does not support this Mac or macOS version.")
        case .location: String(localized: "Curtain cannot be replaced at its current location. Move it to a writable Applications folder and try again, or install the update manually.")
        case .privacySession: String(localized: "Unlock the privacy screen before checking for updates.")
        case .restart: String(localized: "Could not prepare to restart. The current app has been kept. Try again later.")
        case .rollback: String(localized: "The update was installed, but automatic restart failed. Quit and reopen Curtain manually. The previous version is preserved in a temporary folder.")
        }
    }
}

/// GitHub metadata and initial asset URLs are scoped to the configured repository.
/// Only asset downloads may redirect to GitHub's dedicated release storage hosts.
struct UpdateSource: Sendable {
    let api: URL
    let page: URL
    private let githubRepository: String?

    init(api: URL, page: URL) throws {
        guard Self.isHTTPS(api), Self.isHTTPS(page) else {
            throw UpdateFailure.invalidRelease
        }
        if api.host?.lowercased() == "api.github.com" {
            let parts = page.path.split(separator: "/")
            guard page.host?.lowercased() == "github.com", (api.port ?? 443) == 443,
                  (page.port ?? 443) == 443, parts.count == 3, parts[2] == "releases",
                  api.path == "/repos/\(parts[0])/\(parts[1])/releases/latest" else {
                throw UpdateFailure.invalidRelease
            }
            githubRepository = "\(parts[0])/\(parts[1])"
        } else {
            guard Self.sameOrigin(api, page) else { throw UpdateFailure.invalidRelease }
            githubRepository = nil
        }
        self.api = api
        self.page = page
    }

    func accepts(_ url: URL) -> Bool {
        guard Self.isHTTPS(url) else { return false }
        guard let repository = githubRepository else { return Self.sameOrigin(api, url) }
        let host = url.host?.lowercased()
        guard (url.port ?? 443) == 443 else { return false }
        if host == "api.github.com" { return url.path == "/repos/\(repository)/releases/latest" }
        return acceptsReleasePage(url)
    }

    func acceptsReleasePage(_ url: URL) -> Bool {
        guard let repository = githubRepository else { return accepts(url) }
        let prefix = "/\(repository)/releases"
        return Self.isHTTPS(url) && url.host?.lowercased() == "github.com" && (url.port ?? 443) == 443
            && (url.path == prefix || url.path.hasPrefix(prefix + "/"))
    }

    func acceptsAsset(_ url: URL) -> Bool {
        guard let repository = githubRepository else { return accepts(url) }
        return Self.isHTTPS(url) && url.host?.lowercased() == "github.com" && (url.port ?? 443) == 443
            && url.path.hasPrefix("/\(repository)/releases/download/")
    }

    func acceptsDownload(_ url: URL) -> Bool {
        if acceptsAsset(url) { return true }
        guard githubRepository != nil, Self.isHTTPS(url), (url.port ?? 443) == 443 else { return false }
        return ["release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host?.lowercased() ?? "")
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil
            && url.password == nil && url.fragment == nil
    }

    private static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.host?.lowercased() == b.host?.lowercased() && (a.port ?? 443) == (b.port ?? 443)
    }
}

struct UpdateRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadUrl: String
    }
    let tagName: String
    let htmlUrl: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    static func parse(_ data: Data, source: UpdateSource) throws -> UpdateRelease {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Self.self, from: data)
        guard !release.draft, !release.prerelease, AppVersion(release.tagName) != nil,
              let page = URL(string: release.htmlUrl), source.acceptsReleasePage(page) else {
            throw UpdateFailure.invalidRelease
        }
        return release
    }

    func packageURL(source: UpdateSource) throws -> URL {
        try assetURL(named: "Curtain.zip", source: source)
    }

    func signatureURL(source: UpdateSource) throws -> URL {
        do { return try assetURL(named: "Curtain.zip.sig", source: source) }
        catch { throw UpdateFailure.invalidSignature }
    }

    private func assetURL(named name: String, source: UpdateSource) throws -> URL {
        let matches = assets.filter { $0.name == name }
        guard matches.count == 1, let url = URL(string: matches[0].browserDownloadUrl), source.acceptsAsset(url) else {
            throw UpdateFailure.invalidPackage
        }
        return url
    }
}

/// Blocking filesystem/signature work runs off the main actor. Nothing here changes the live
/// bundle until the final atomic exchange. Staging must be on the same volume as that bundle.
enum UpdatePackage {
    static let bundleID = "local.zjf.curtain"

    /// Publisher authentication is independent of Apple's code-signing certificates.
    /// Always verify the exact archive bytes before invoking an archive parser.
    static func verifyArchive(_ zip: URL, signature: Data, publicKey: String) throws {
        guard signature.count <= 4096,
              let encoded = String(data: signature, encoding: .utf8),
              let signed = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)), signed.count == 64,
              let rawKey = Data(base64Encoded: publicKey), rawKey.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
              let size = try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 256 * 1024 * 1024 else {
            throw UpdateFailure.invalidSignature
        }
        let bytes = try Data(contentsOf: zip, options: .mappedIfSafe)
        guard key.isValidSignature(signed, for: bytes) else { throw UpdateFailure.invalidSignature }
    }

    static func prepare(_ zip: URL, signature: Data, into staging: URL,
                        expected: AppVersion, current: AppVersion, publicKey: String) throws -> URL {
        try verifyArchive(zip, signature: signature, publicKey: publicKey)
        let candidate = try unpack(zip, into: staging)
        try verify(candidate, expected: expected, current: current, publicKey: publicKey)
        return candidate
    }

    static func checkLocation(_ app: URL) throws {
        let values = try app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard app.pathExtension == "app", values.isDirectory == true, values.isSymbolicLink != true,
              !app.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: app.path),
              FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            throw UpdateFailure.location
        }
    }

    static func unpack(_ zip: URL, into staging: URL) throws -> URL {
        // libarchive's default secure extraction rejects traversal through symlinks and '..'.
        // In addition, our own archive contract accepts ONLY regular files/directories under
        // Curtain.app; this app has no framework symlinks. Never pass tar's -P option.
        let listing = try run("/usr/bin/tar", ["-tf", zip.path])
        let names = listing.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        guard !names.isEmpty, names.count <= 10_000, names.allSatisfy({ safeArchivePath(String($0)) }) else {
            throw UpdateFailure.invalidPackage
        }
        let types = try run("/usr/bin/tar", ["-tvf", zip.path]).split(separator: "\n")
        var expandedSize: UInt64 = 0
        guard types.count == names.count, types.allSatisfy({ line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard line.first == "-" || line.first == "d", fields.count >= 9,
                  let size = UInt64(fields[4]), size <= 1024 * 1024 * 1024 else { return false }
            expandedSize += size
            return expandedSize <= 1024 * 1024 * 1024
        }) else {
            throw UpdateFailure.invalidPackage
        }
        let output = staging.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        _ = try run("/usr/bin/tar", ["-xf", zip.path, "--no-same-owner", "-C", output.path])
        let app = output.appendingPathComponent("Curtain.app", isDirectory: true)
        guard let files = FileManager.default.enumerator(at: output, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw UpdateFailure.invalidPackage
        }
        for case let file as URL in files {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw UpdateFailure.invalidPackage
            }
        }
        return app
    }

    static func safeArchivePath(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return parts.first == "Curtain.app" && !parts.contains("..") && !parts.contains(".")
            && !name.contains("\\") && !name.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true })
    }

    static func verify(_ app: URL, expected: AppVersion, current: AppVersion, publicKey: String) throws {
        try checkSignature(app, identifier: bundleID)
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == bundleID,
              info?["CFBundleExecutable"] as? String == "Curtain",
              info?["CFBundlePackageType"] as? String == "APPL",
              info?["CurtainUpdatePublicKey"] as? String == publicKey,
              let text = info?["CFBundleShortVersionString"] as? String, let version = AppVersion(text),
              version == expected, version > current else { throw UpdateFailure.invalidPackage }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard let minimumText = info?["LSMinimumSystemVersion"] as? String, let minimum = AppVersion(minimumText),
              let host = AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"), minimum <= host else {
            throw UpdateFailure.incompatible
        }
        let executable = app.appendingPathComponent("Contents/MacOS/Curtain")
        let helper = app.appendingPathComponent("Contents/Helpers/CurtainWatchdog")
        let renderer = app.appendingPathComponent("Contents/Helpers/CurtainRenderer")
        guard FileManager.default.isExecutableFile(atPath: renderer.path),
              FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.isExecutableFile(atPath: helper.path) else { throw UpdateFailure.invalidPackage }
        // The archive's Ed25519 signature authenticates all binaries, including ad-hoc code.
        try checkSignature(helper, identifier: nil)
        try checkSignature(renderer, identifier: nil)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        do {
            _ = try run("/usr/bin/lipo", ["-verify_arch", architecture, executable.path])
            _ = try run("/usr/bin/lipo", ["-verify_arch", architecture, helper.path])
            _ = try run("/usr/bin/lipo", ["-verify_arch", architecture, renderer.path])
        } catch { throw UpdateFailure.incompatible }
    }

    private static func checkSignature(_ url: URL, identifier: String?) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateFailure.untrusted
        }
        var requirement: SecRequirement?
        if let identifier,
           SecRequirementCreateWithString("identifier \"\(identifier)\"" as CFString, [], &requirement) != errSecSuccess {
            throw UpdateFailure.untrusted
        }
        let flags = SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode))
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw UpdateFailure.untrusted
        }
    }

    /// Cancellation/state checks are synchronous with the swap on the main actor. No await or
    /// user interaction is allowed between the final check and exchange.
    @MainActor
    static func exchange(_ app: URL, with candidate: URL, permitted: () -> Bool, afterSwap: () throws -> Void = {}) throws {
        try Task.checkCancellation()
        guard permitted() else { throw UpdateFailure.privacySession }
        guard renamex_np(candidate.path, app.path, UInt32(RENAME_SWAP)) == 0 else {
            throw UpdateFailure.location
        }
        do { try afterSwap() }
        catch {
            guard renamex_np(candidate.path, app.path, UInt32(RENAME_SWAP)) == 0 else { throw UpdateFailure.rollback }
            throw UpdateFailure.restart
        }
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            throw UpdateFailure.invalidPackage
        }
        return text
    }
}
