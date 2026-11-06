import Foundation
import Security
import Darwin

enum UpdateFailure: LocalizedError {
    case invalidRelease, noRelease, network, invalidPackage, untrusted, incompatible, location, privacySession, restart, rollback

    var errorDescription: String? {
        switch self {
        case .invalidRelease: String(localized: "The release information is invalid. Try again later.")
        case .noRelease: String(localized: "No release is available yet. Check the release page or try again later.")
        case .network: String(localized: "Could not download the update. Check your network connection and try again.")
        case .invalidPackage: String(localized: "The update package is incomplete or does not match the release. The current app has not been replaced.")
        case .untrusted: String(localized: "The update could not be verified as coming from the same developer as Curtain. Install it manually from the release page.")
        case .incompatible: String(localized: "The update does not support this Mac or macOS version.")
        case .location: String(localized: "Curtain cannot be replaced at its current location. Move it to a writable Applications folder and try again, or install the update manually.")
        case .privacySession: String(localized: "Unlock the privacy screen before checking for updates.")
        case .restart: String(localized: "Could not prepare to restart. The current app has been kept. Try again later.")
        case .rollback: String(localized: "The update was installed, but automatic restart failed. Quit and reopen Curtain manually. The previous version is preserved in a temporary folder.")
        }
    }
}

/// Only HTTPS URLs on the configured server are used, including redirects.
struct UpdateSource: Sendable {
    let api: URL
    let page: URL

    init(api: URL, page: URL) throws {
        guard Self.isHTTPS(api), Self.isHTTPS(page), Self.sameOrigin(api, page) else {
            throw UpdateFailure.invalidRelease
        }
        self.api = api
        self.page = page
    }

    func accepts(_ url: URL) -> Bool { Self.isHTTPS(url) && Self.sameOrigin(api, url) }

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
              let page = URL(string: release.htmlUrl), source.accepts(page) else {
            throw UpdateFailure.invalidRelease
        }
        return release
    }

    func packageURL(source: UpdateSource) throws -> URL {
        let matches = assets.filter { $0.name == "Curtain.zip" }
        guard matches.count == 1, let url = URL(string: matches[0].browserDownloadUrl), source.accepts(url) else {
            throw UpdateFailure.invalidPackage
        }
        return url
    }
}

/// Blocking filesystem/signature work runs off the main actor. Nothing here changes the live
/// bundle until the final atomic exchange. Staging must be on the same volume as that bundle.
enum UpdatePackage {
    static let bundleID = "local.zjf.curtain"

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

    static func verify(_ app: URL, expected: AppVersion, current: AppVersion, team: String?) throws {
        guard let team, !team.isEmpty, team.allSatisfy({ $0.isASCII && $0.isLetter || $0.isASCII && $0.isNumber }) else {
            throw UpdateFailure.untrusted
        }
        try checkSignature(app, identifier: bundleID, team: team)
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == bundleID,
              info?["CFBundleExecutable"] as? String == "Curtain",
              info?["CFBundlePackageType"] as? String == "APPL",
              let text = info?["CFBundleShortVersionString"] as? String, let version = AppVersion(text),
              version == expected, version > current else { throw UpdateFailure.invalidPackage }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard let minimumText = info?["LSMinimumSystemVersion"] as? String, let minimum = AppVersion(minimumText),
              let host = AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"), minimum <= host else {
            throw UpdateFailure.incompatible
        }
        let executable = app.appendingPathComponent("Contents/MacOS/Curtain")
        let helper = app.appendingPathComponent("Contents/Helpers/CurtainWatchdog")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.isExecutableFile(atPath: helper.path) else { throw UpdateFailure.invalidPackage }
        // Nested signature integrity alone does not constrain the helper's signer identity.
        try checkSignature(helper, identifier: nil, team: team)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        do {
            _ = try run("/usr/bin/lipo", ["-verify_arch", architecture, executable.path])
            _ = try run("/usr/bin/lipo", ["-verify_arch", architecture, helper.path])
        } catch { throw UpdateFailure.incompatible }
    }

    private static func checkSignature(_ url: URL, identifier: String?, team: String) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateFailure.untrusted
        }
        var text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        if let identifier { text += " and identifier \"\(identifier)\"" }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            throw UpdateFailure.untrusted
        }
        let flags = SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode))
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw UpdateFailure.untrusted
        }
    }

    static func teamID(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSSigningInformation)), &info) == errSecSuccess else {
            return nil
        }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Derive trust from the running executable, rather than a possibly changed on-disk bundle.
    static var currentTeamID: String? {
        var running: SecCode?
        var code: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSSigningInformation)), &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
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
