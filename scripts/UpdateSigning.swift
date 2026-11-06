import Foundation
import CryptoKit
import Darwin

enum SigningError: Error { case invalidArguments, invalidKey, existingFile, invalidPackage, keyMismatch }

func readPrivateKey(_ path: String) throws -> Curve25519.Signing.PrivateKey {
    let encoded = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: encoded), data.count == 32 else { throw SigningError.invalidKey }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
}

func readPublicKey(_ path: String) throws -> String {
    let text = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: text), data.count == 32,
          (try? Curve25519.Signing.PublicKey(rawRepresentation: data)) != nil else { throw SigningError.invalidKey }
    return data.base64EncodedString()
}

/// Exclusive creation prevents accidental key rotation. Secret bytes never go to stdout.
func createExclusive(_ data: Data, at url: URL, mode: mode_t) throws {
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
    guard descriptor >= 0 else { throw SigningError.existingFile }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
    catch { try? FileManager.default.removeItem(at: url); throw error }
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "generate" where args.count == 3:
        let secret = URL(fileURLWithPath: args[1]).standardizedFileURL
        let publicFile = URL(fileURLWithPath: args[2]).standardizedFileURL
        guard secret != publicFile, !FileManager.default.fileExists(atPath: secret.path),
              !FileManager.default.fileExists(atPath: publicFile.path) else { throw SigningError.existingFile }
        let directory = secret.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let key = Curve25519.Signing.PrivateKey()
        try createExclusive(Data((key.rawRepresentation.base64EncodedString() + "\n").utf8), at: secret, mode: 0o600)
        try createExclusive(Data((key.publicKey.rawRepresentation.base64EncodedString() + "\n").utf8), at: publicFile, mode: 0o644)
        print("Created private key at \(secret.path). Back it up privately; it cannot be recovered from the public key.")
        print("Public key written to \(publicFile.path). Commit only this public file.")
    case "validate-public" where args.count == 2:
        print(try readPublicKey(args[1]))
    case "sign" where args.count == 3:
        let key = try readPrivateKey(args[1])
        let zip = URL(fileURLWithPath: args[2])
        let size = try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 256 * 1024 * 1024 else { throw SigningError.invalidPackage }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xOf", zip.path, "Curtain.app/Contents/Info.plist"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let plist = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "local.zjf.curtain" else { throw SigningError.invalidPackage }
        guard info["CurtainUpdatePublicKey"] as? String == key.publicKey.rawRepresentation.base64EncodedString() else {
            throw SigningError.keyMismatch
        }
        let bytes = try Data(contentsOf: zip, options: .mappedIfSafe)
        let signature = try key.signature(for: bytes)
        guard key.publicKey.isValidSignature(signature, for: bytes) else { throw SigningError.invalidPackage }
        let signatureFile = URL(fileURLWithPath: zip.path + ".sig")
        try Data((signature.base64EncodedString() + "\n").utf8).write(to: signatureFile, options: .atomic)
        print("Signed \(zip.path). Publish Curtain.zip and Curtain.zip.sig together with a matching version tag.")
    default:
        throw SigningError.invalidArguments
    }
}

do { try run() }
catch {
    // Do not include private-key contents in diagnostics.
    let message: String
    switch error {
    case SigningError.existingFile: message = "Output already exists or cannot be created; existing keys were not overwritten."
    case SigningError.keyMismatch: message = "Private key does not match the public key embedded in the release."
    case SigningError.invalidKey: message = "Invalid Ed25519 key file."
    case SigningError.invalidPackage: message = "Invalid Curtain release archive."
    default: message = "Usage: update-signing.sh generate PRIVATE PUBLIC | validate-public PUBLIC | sign PRIVATE ZIP. Check input paths and permissions."
    }
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
