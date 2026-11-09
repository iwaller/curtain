import Foundation
import CoreGraphics

/// The only renderer IPC payload: bounded, opaque RGBA8 pixels in sRGB.
enum BackdropPacket {
    static let maximumBytes = 24 + 1024 * 1024 * 4

    static func dimensions(_ size: CGSize) -> (width: Int, height: Int, scale: CGFloat)? {
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1, size.width <= 32768, size.height <= 32768 else { return nil }
        let scale = min(1, 1024 / max(size.width, size.height))
        return (max(1, Int((size.width * scale).rounded())), max(1, Int((size.height * scale).rounded())), scale)
    }

    static func encode(_ image: CGImage) -> Data? {
        guard image.width > 0, image.height > 0, image.width <= 1024, image.height <= 1024,
              image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              image.bytesPerRow == image.width * 4,
              let pixels = image.dataProvider?.data else { return nil }
        var data = Data()
        for value: UInt32 in [0x43525442, 1, 1, UInt32(image.width), UInt32(image.height), UInt32(image.bytesPerRow)] {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(pixels as Data)
        return data
    }

    static func decode(_ data: Data, requested: CGSize) -> CGImage? {
        guard data.count >= 24, data.count <= maximumBytes, let size = dimensions(requested) else { return nil }
        let header = data.withUnsafeBytes { bytes in
            (0..<6).map { UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)) }
        }
        guard header == [0x43525442, 1, 1, UInt32(size.width), UInt32(size.height), UInt32(size.width * 4)],
              data.count == 24 + size.width * size.height * 4 else { return nil }
        let pixels = data.subdata(in: 24..<data.count)
        guard stride(from: 3, to: pixels.count, by: 4).allSatisfy({ pixels[$0] == 255 }),
              let provider = CGDataProvider(data: pixels as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: size.width, height: size.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: size.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
