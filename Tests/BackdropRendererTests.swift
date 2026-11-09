import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Compare against the previous Core Image appearance, including alpha and pixels outside the crop.
@MainActor
enum BackdropRendererTests {
    static func run(in directory: URL) throws {
        for (name, space, transparent) in [("srgb", CGColorSpace.sRGB, false),
                                            ("p3", CGColorSpace.displayP3, false),
                                            ("alpha", CGColorSpace.sRGB, true)] {
            let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8,
                                    bytesPerRow: 4800, space: CGColorSpace(name: space)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            for x in stride(from: 0, to: 1200, by: 4) {
                let value = CGFloat(x) / 1200
                context.setFillColor(CGColor(red: value, green: 0.25, blue: 1 - value, alpha: transparent ? 0.5 : 1))
                context.fill(CGRect(x: x, y: 0, width: 4, height: 800))
            }
            context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: 100, y: 100, width: 400, height: 500))
            let url = directory.appendingPathComponent("cpu-\(name).png")
            write(context.makeImage()!, to: url)
            compare(url, size: CGSize(width: 450, height: 300))
        }
        let edge = CGContext(data: nil, width: 1800, height: 600, bitsPerComponent: 8,
                             bytesPerRow: 7200, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        edge.setFillColor(CGColor(gray: 0, alpha: 1))
        edge.fill(CGRect(x: 0, y: 0, width: 1800, height: 600))
        // The white region ends exactly where the central square crop starts.
        edge.setFillColor(CGColor(gray: 1, alpha: 1))
        edge.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        let edgeURL = directory.appendingPathComponent("cpu-crop-edge.png")
        write(edge.makeImage()!, to: edgeURL)
        compare(edgeURL, size: CGSize(width: 300, height: 300))
        let edgePixels = pixels(BackdropRenderer.render(url: edgeURL, size: CGSize(width: 300, height: 300))!)
        precondition(edgePixels[(150 * 300 + 1) * 4] > 80, "Blur must include content outside the crop")
        print("PASS linear color, P3 conversion, transparency and pre-crop blur match the previous appearance")

        let url = directory.appendingPathComponent("cpu-srgb.png")
        for size in [CGSize(width: CGFloat.infinity, height: 100), CGSize(width: CGFloat.nan, height: 100),
                     CGSize(width: -1, height: 100), CGSize(width: 0, height: 100),
                     CGSize(width: 1e300, height: 100), CGSize(width: 100, height: CGFloat.infinity)] {
            precondition(BackdropRenderer.render(url: url, size: size) == nil, "Invalid size must fail without allocation")
        }
        for size in [CGSize(width: 1, height: 1), CGSize(width: 17, height: 23)] {
            let image = BackdropRenderer.render(url: url, size: size)!
            precondition(image.width == Int(size.width) && image.height == Int(size.height))
            precondition(pixels(image).enumerated().filter { $0.offset % 4 == 3 }.allSatisfy { $0.element == 255 })
        }
        let large = BackdropRenderer.render(url: url, size: CGSize(width: 6144, height: 3456))!
        precondition(large.width == 1024 && large.height == 576, "Large requests must preserve aspect ratio within the pixel budget")
        let portrait = BackdropRenderer.render(url: url, size: CGSize(width: 3456, height: 6144))!
        precondition(portrait.width == 576 && portrait.height == 1024)
        print("PASS invalid/tiny dimensions and bounded landscape/portrait output")

        let retained = autoreleasepool { BackdropRenderer.render(url: url, size: CGSize(width: 450, height: 300))! }
        let expected = pixels(retained)
        for _ in 0..<20 {
            autoreleasepool {
                let other = BackdropRenderer.render(url: edgeURL, size: CGSize(width: 450, height: 300))!
                _ = pixels(other)
            }
        }
        precondition(pixels(retained) == expected, "Pixels must outlive temporary buffers and subsequent renders")
        print("PASS retained image pixels survive buffer release and 20 later renders")
    }

    private static func write(_ image: CGImage, to url: URL) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
    }

    private static func pixels(_ image: CGImage) -> [UInt8] {
        var values = [UInt8](repeating: 0, count: image.width * image.height * 4)
        values.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return values
    }

    private static func compare(_ url: URL, size: CGSize) {
        let current = pixels(BackdropRenderer.render(url: url, size: size)!)
        let previous = pixels(reference(url: url, size: size)!)
        var total = 0
        for i in current.indices where i % 4 != 3 { total += abs(Int(current[i]) - Int(previous[i])) }
        let mean = Double(total) / Double(current.count / 4 * 3)
        precondition(mean < 1.5, "Appearance changed for \(url.lastPathComponent): mean RGB error \(mean)")
        precondition(current.enumerated().filter { $0.offset % 4 == 3 }.allSatisfy { $0.element == 255 })
    }

    // Reference-only: the previous production algorithm, never linked into Curtain.app.
    private static func reference(url: URL, size: CGSize) -> CGImage? {
        guard size.width > 0, size.height > 0,
              let file = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        let sourceSize = rotated ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let fillScale = min(1, max(size.width / sourceSize.width, size.height / sourceSize.height))
        // Decode only the pixels needed for the blurred backdrop. Bound unusually tall/wide
        // wallpapers too; slight upscaling after the crop is harmless at this blur radius.
        let maxPixelSize = min(2048, ceil(max(width, height) * fillScale))
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(file, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { return nil }
        let source = CIImage(cgImage: thumbnail)
        // Aspect-fill into `size`, centred.
        let scale = max(size.width / source.extent.width, size.height / source.extent.height)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let crop = CGRect(x: scaled.extent.midX - size.width / 2, y: scaled.extent.midY - size.height / 2,
                          width: size.width, height: size.height)
        let blurred = scaled.clampedToExtent()
            .applyingGaussianBlur(sigma: 24)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.2,
                kCIInputBrightnessKey: -0.08,
            ])
            .cropped(to: crop)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(blurred, from: crop)
    }
}
