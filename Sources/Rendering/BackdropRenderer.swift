import CoreGraphics
import Accelerate
import ImageIO

/// Bounded, color-managed CPU wallpaper processing. No windows or display-pipeline changes.
enum BackdropRenderer {
    static func render(url: URL, size requested: CGSize) -> CGImage? {
        guard let dimensions = BackdropPacket.dimensions(requested) else { return nil }
        let (width, height, reduction) = dimensions
        let size = CGSize(width: width, height: height)
        let sigma = max(0.5, 24 * reduction)
        let radius = Int(ceil(3 * sigma))
        let paddedWidth = width + 2 * radius, paddedHeight = height + 2 * radius
        // At most 1168 x 1168 x 16 bytes per buffer; products cannot overflow after the bounds above.
        let rowBytes = paddedWidth * MemoryLayout<SIMD4<Float>>.stride
        guard let file = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth > 0, sourceHeight > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        let oriented = rotated ? CGSize(width: sourceHeight, height: sourceWidth) : CGSize(width: sourceWidth, height: sourceHeight)
        let fillScale = min(1, max(size.width / oriented.width, size.height / oriented.height))
        let maxPixelSize = min(2048, ceil(max(sourceWidth, sourceHeight) * fillScale))
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(file, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary), let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let pixels = calloc(paddedHeight, rowBytes) else { return nil }
        defer { free(pixels) }
        guard let scratch = calloc(paddedHeight, rowBytes) else { return nil }
        defer { free(scratch) }
        let bitmapInfo = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: pixels, width: paddedWidth, height: paddedHeight, bitsPerComponent: 32,
                                      bytesPerRow: rowBytes, space: linear, bitmapInfo: bitmapInfo) else { return nil }
        let scale = max(size.width / CGFloat(thumbnail.width), size.height / CGFloat(thumbnail.height))
        let rect = CGRect(x: (CGFloat(paddedWidth) - CGFloat(thumbnail.width) * scale) / 2,
                          y: (CGFloat(paddedHeight) - CGFloat(thumbnail.height) * scale) / 2,
                          width: CGFloat(thumbnail.width) * scale, height: CGFloat(thumbnail.height) * scale)
        context.interpolationQuality = .high
        context.draw(thumbnail, in: rect)
        // Extend the real image edges; retain the crop's neighboring pixels before blurring.
        let values = pixels.bindMemory(to: SIMD4<Float>.self, capacity: paddedWidth * paddedHeight)
        let minX = max(0, min(paddedWidth - 1, Int(ceil(rect.minX))))
        let maxX = max(minX, min(paddedWidth - 1, Int(floor(rect.maxX)) - 1))
        let minY = max(0, min(paddedHeight - 1, Int(ceil(rect.minY))))
        let maxY = max(minY, min(paddedHeight - 1, Int(floor(rect.maxY)) - 1))
        for y in minY...maxY {
            for x in 0..<minX { values[y * paddedWidth + x] = values[y * paddedWidth + minX] }
            for x in (maxX + 1)..<paddedWidth { values[y * paddedWidth + x] = values[y * paddedWidth + maxX] }
        }
        for y in 0..<minY { memcpy(pixels.advanced(by: y * rowBytes), pixels.advanced(by: minY * rowBytes), rowBytes) }
        for y in (maxY + 1)..<paddedHeight { memcpy(pixels.advanced(by: y * rowBytes), pixels.advanced(by: maxY * rowBytes), rowBytes) }
        var source = vImage_Buffer(data: pixels, height: vImagePixelCount(paddedHeight), width: vImagePixelCount(paddedWidth), rowBytes: rowBytes)
        var target = vImage_Buffer(data: scratch, height: source.height, width: source.width, rowBytes: rowBytes)
        var kernel = (-radius...radius).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
        let sum = kernel.reduce(0, +)
        kernel = kernel.map { $0 / sum }
        // A separable Gaussian keeps the old blur shape without a large 2D convolution.
        let flags = vImage_Flags(kvImageEdgeExtend | kvImageDoNotTile)
        guard vImageConvolve_ARGBFFFF(&source, &target, nil, 0, 0, kernel, 1, UInt32(kernel.count), nil, flags) == kvImageNoError,
              vImageConvolve_ARGBFFFF(&target, &source, nil, 0, 0, kernel, UInt32(kernel.count), 1, nil, flags) == kvImageNoError else { return nil }
        // Work on premultiplied linear RGB; scale the brightness offset by alpha.
        for y in radius..<(radius + height) {
            for x in radius..<(radius + width) {
                let offset = y * paddedWidth + x
                let pixel = values[offset]
                let luma = pixel.x * 0.2125 + pixel.y * 0.7154 + pixel.z * 0.0721
                values[offset] = SIMD4((pixel.x - luma) * 1.2 + luma - 0.08 * pixel.w,
                                      (pixel.y - luma) * 1.2 + luma - 0.08 * pixel.w,
                                      (pixel.z - luma) * 1.2 + luma - 0.08 * pixel.w, pixel.w)
            }
        }
        guard let image = context.makeImage(),
              let cropped = image.cropping(to: CGRect(x: radius, y: radius, width: width, height: height)),
              let output = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: srgb,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Convert to sRGB before compositing on black, matching the opaque backdrop window.
        output.setFillColor(CGColor(gray: 0, alpha: 1))
        output.fill(CGRect(origin: .zero, size: size))
        output.draw(cropped, in: CGRect(origin: .zero, size: size))
        return output.makeImage()
    }
}
