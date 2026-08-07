import CoreGraphics
import Foundation
import ImageIO
import SpriteKit
import UniformTypeIdentifiers

/// PNG in, `Bitmap` out, and `Bitmap` in, `SKTexture` out.
///
/// **Every texture in this project is created through here** so that
/// `.filteringMode = .nearest` and `usesMipmaps = false` are applied in exactly
/// one place. A single texture created without nearest filtering looks wrong in
/// a way that is very hard to trace back later.
public enum PixelImage {

    public enum LoadError: Error, CustomStringConvertible {
        case unreadable(URL)

        public var description: String {
            switch self {
            case .unreadable(let url): return "could not decode \(url.path)"
            }
        }
    }

    /// Decodes to straight (un-premultiplied) RGBA8, y-down.
    public static func bitmap(contentsOf url: URL) throws -> Bitmap {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError.unreadable(url)
        }
        return try bitmap(from: image)
    }

    public static func bitmap(from image: CGImage) throws -> Bitmap {
        let width = image.width
        let height = image.height
        var bitmap = Bitmap(width: width, height: height)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw LoadError.unreadable(URL(fileURLWithPath: "<colour space>"))
        }
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw LoadError.unreadable(URL(fileURLWithPath: "<context>")) }
        // Un-premultiply, so pixel comparisons in tests and the accent sampler
        // see the colours the artist wrote.
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = buffer[index + 3]
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0..<3 {
                buffer[index + channel] =
                    UInt8(min(255, Int(buffer[index + channel]) * 255 / Int(alpha)))
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bitmap.set(x, y, Bitmap.RGBA(
                    buffer[index], buffer[index + 1], buffer[index + 2], buffer[index + 3]))
            }
        }
        return bitmap
    }

    public static func cgImage(from bitmap: Bitmap) -> CGImage? {
        guard bitmap.width > 0, bitmap.height > 0 else { return nil }
        var premultiplied = bitmap.pixels
        for index in stride(from: 0, to: premultiplied.count, by: 4) {
            let alpha = Int(premultiplied[index + 3])
            guard alpha < 255 else { continue }
            for channel in 0..<3 {
                premultiplied[index + channel] =
                    UInt8(Int(premultiplied[index + channel]) * alpha / 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(premultiplied) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: bitmap.width, height: bitmap.height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bitmap.width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }

    /// The single place a texture is born. [standing rule]
    public static func texture(from image: CGImage) -> SKTexture {
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        return texture
    }

    public static func texture(from bitmap: Bitmap) -> SKTexture? {
        cgImage(from: bitmap).map(texture(from:))
    }

    /// Writes a bitmap out as a PNG. Used by the offscreen render harness.
    @discardableResult
    public static func writePNG(_ bitmap: Bitmap, to url: URL) -> Bool {
        guard let image = cgImage(from: bitmap),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
