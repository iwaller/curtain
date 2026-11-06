import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
@MainActor
enum BackdropArtTests {
    static func main() throws {
        let directory = URL(fileURLWithPath: "artifacts/memory-review", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A red/blue split makes orientation and aspect-fill errors observable in the output.
        let context = CGContext(data: nil, width: 2400, height: 1600, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 1200, y: 0, width: 1200, height: 1600))
        let source = context.makeImage()!
        for (name, type, orientation) in [("png", UTType.png, 1), ("jpg", UTType.jpeg, 1),
                                          ("heic", UTType.heic, 1), ("rotated.jpg", UTType.jpeg, 6)] {
            let url = directory.appendingPathComponent("fixture.\(name)")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, source, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            precondition(CGImageDestinationFinalize(destination))
            let size = orientation == 6 ? CGSize(width: 200, height: 300) : CGSize(width: 300, height: 200)
            let image = BackdropArt.render(url: url, size: size)!
            precondition(image.width == Int(size.width) && image.height == Int(size.height))
            let pixels = rgba(image)
            func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let index = (y * image.width + x) * 4
                return (Int(pixels[index]), Int(pixels[index + 2]), Int(pixels[index + 3]))
            }
            let first = orientation == 6 ? pixel(100, 30) : pixel(30, 100)
            let last = orientation == 6 ? pixel(100, 270) : pixel(270, 100)
            precondition(abs(first.0 - last.0) > 100 && abs(first.1 - last.1) > 100,
                         "Expected separated red/blue regions after orientation and blur: \(name)")
            for (x, y) in [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)] {
                precondition(pixel(x, y).2 == 255, "Backdrop corners must stay opaque")
            }
            print("PASS \(name): output dimensions, oriented color regions and opaque corners")
        }
        let missing = directory.appendingPathComponent("missing-image")
        precondition(BackdropArt.render(url: missing, size: CGSize(width: 100, height: 100)) == nil)
        let corrupt = directory.appendingPathComponent("corrupt-image")
        try Data("not an image".utf8).write(to: corrupt)
        precondition(BackdropArt.render(url: corrupt, size: CGSize(width: 100, height: 100)) == nil)
        print("PASS missing/corrupt wallpaper falls back without a result")

        // Exercise real background dispatch and main-run-loop publication without creating
        // windows, changing gamma, requesting authentication or running a privacy session.
        let screen = NSScreen.screens.first!
        BackdropArt.prepare()
        waitForArt(screen)
        let first = BackdropArt.image(for: screen)!
        BackdropArt.prepare()
        precondition(BackdropArt.image(for: screen) === first)
        BackdropArt.clear()
        precondition(BackdropArt.image(for: screen) == nil)
        print("PASS prepared art is reused within a session and removed on clear")

        BackdropArt.prepare()
        BackdropArt.clear() // Clear before the worker can publish to the main queue.
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        precondition(BackdropArt.image(for: screen) == nil)
        print("PASS late completion cannot repopulate a cleared session")

        for _ in 0..<5 {
            BackdropArt.prepare()
            BackdropArt.clear()
            BackdropArt.prepare() // The old same-key completion must not cancel the new request.
            waitForArt(screen)
            BackdropArt.clear()
            precondition(BackdropArt.image(for: screen) == nil)
        }
        print("PASS five overlapping session generations still publish and clear correctly")
    }

    static func waitForArt(_ screen: NSScreen) {
        let deadline = Date().addingTimeInterval(10)
        while BackdropArt.image(for: screen) == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(BackdropArt.image(for: screen) != nil, "Current desktop wallpaper must render within 10 seconds")
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
