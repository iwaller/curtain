import Foundation
import CoreGraphics
import Darwin

@main
enum FakeBackdropRenderer {
    static func main() throws {
        let input = CommandLine.arguments[1]
        try String(getpid()).write(toFile: input + ".pid", atomically: true, encoding: .utf8)
        let mode = URL(fileURLWithPath: input).lastPathComponent
        if mode == "crash" { raise(SIGKILL) }
        if mode == "nonzero" { exit(1) }
        if mode == "oversize" {
            try FileHandle.standardOutput.write(contentsOf: Data(repeating: 0, count: BackdropPacket.maximumBytes + 1))
            return
        }
        if mode == "corrupt" { try FileHandle.standardOutput.write(contentsOf: Data("invalid".utf8)); return }
        if mode == "valid-hang" {
            let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            try FileHandle.standardOutput.write(contentsOf: BackdropPacket.encode(context.makeImage()!)!)
            try FileHandle.standardOutput.close()
        }
        while true { Thread.sleep(forTimeInterval: 1) }
    }
}
