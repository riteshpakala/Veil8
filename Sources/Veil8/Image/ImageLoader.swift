//
//  ImageLoader.swift
//  Veil8
//
//  File/data → RGBAImage with the EXIF orientation applied (an iPhone photo stored
//  4032×3024 with orientation 6 loads as 3024×4032). ImageIO applies the transform;
//  a manual transform backs it up when ImageIO returns unexpected dimensions.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageLoader {
    public enum LoadError: Error, LocalizedError, Sendable {
        case unreadable(String)
        case decodeFailed(String)
        case encodeFailed

        public var errorDescription: String? {
            switch self {
            case .unreadable(let s): return "cannot read image: \(s)"
            case .decodeFailed(let s): return "cannot decode image: \(s)"
            case .encodeFailed: return "cannot encode image"
            }
        }
    }

    public static func load(_ url: URL) throws -> RGBAImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw LoadError.unreadable(url.path)
        }
        return try load(source: source, name: url.lastPathComponent)
    }

    public static func load(data: Data) throws -> RGBAImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw LoadError.unreadable("\(data.count) bytes")
        }
        return try load(source: source, name: "data")
    }

    /// Orientation (EXIF 1–8) and stored pixel size of the first image in a source.
    public static func properties(of url: URL) -> (orientation: Int, size: PixelSize)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return properties(of: source)
    }

    static func properties(of source: CGImageSource) -> (orientation: Int, size: PixelSize)? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return (orientation, PixelSize(width: w, height: h))
    }

    static func load(source: CGImageSource, name: String) throws -> RGBAImage {
        guard CGImageSourceGetCount(source) > 0 else { throw LoadError.decodeFailed(name) }
        let props = properties(of: source)
        let orientation = props?.orientation ?? 1
        let stored = props?.size ?? PixelSize(width: 0, height: 0)
        let expected = orientedSize(stored, orientation: orientation)

        // ImageIO applies the EXIF transform when asked; at the image's own size this is a
        // full decode, not a thumbnail.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(stored.longSide, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
           expected.width == 0 || (cg.width == expected.width && cg.height == expected.height),
           let image = RGBAImage(cgImage: cg) {
            return image
        }

        // Fallback: decode and orient by hand.
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw LoadError.decodeFailed(name) }
        guard let image = RGBAImage(cgImage: oriented(raw, orientation: orientation) ?? raw) else {
            throw LoadError.decodeFailed(name)
        }
        return image
    }

    /// Size after applying an EXIF orientation (5–8 swap the axes).
    public static func orientedSize(_ size: PixelSize, orientation: Int) -> PixelSize {
        (5...8).contains(orientation) ? PixelSize(width: size.height, height: size.width) : size
    }

    /// Applies an EXIF orientation (1–8) to a CGImage.
    static func oriented(_ image: CGImage, orientation: Int) -> CGImage? {
        guard orientation != 1, (1...8).contains(orientation) else { return image }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let out = orientedSize(PixelSize(width: image.width, height: image.height), orientation: orientation)
        let ow = CGFloat(out.width), oh = CGFloat(out.height)
        var t = CGAffineTransform.identity
        switch orientation {
        case 3, 4: t = t.translatedBy(x: ow, y: oh).rotated(by: .pi)          // down
        case 8, 5: t = t.translatedBy(x: ow, y: 0).rotated(by: .pi / 2)       // left
        case 6, 7: t = t.translatedBy(x: 0, y: oh).rotated(by: -.pi / 2)      // right
        default: break
        }
        switch orientation {
        case 2, 4: t = t.translatedBy(x: ow, y: 0).scaledBy(x: -1, y: 1)      // mirrored up/down
        case 5, 7: t = t.translatedBy(x: oh, y: 0).scaledBy(x: -1, y: 1)      // mirrored left/right
        default: break
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: out.width, height: out.height, bitsPerComponent: 8,
                                  bytesPerRow: out.width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.concatenate(t)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Resampling

    /// High-quality resample to an exact size (aspect not preserved; callers compute the size).
    public static func resized(_ image: RGBAImage, to size: PixelSize) -> RGBAImage {
        guard size.width != image.width || size.height != image.height else { return image }
        guard let cg = image.cgImage(), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        var buf = [UInt8](repeating: 0, count: size.width * size.height * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: size.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return true
        }
        return ok ? RGBAImage(width: size.width, height: size.height, pixels: buf) : image
    }

    /// Resample so the long side equals `longSide` (never upscales).
    public static func resized(_ image: RGBAImage, longSide: Int) -> RGBAImage {
        resized(image, to: ImageNormalizer.targetSize(for: image.size, maxLongSide: longSide))
    }

    // MARK: - Encoding

    public static func pngData(_ image: RGBAImage) -> Data? {
        encode(image, type: UTType.png, properties: nil)
    }

    public static func jpegData(_ image: RGBAImage, quality: Double = 0.85) -> Data? {
        encode(image, type: UTType.jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    static func encode(_ image: RGBAImage, type: UTType, properties: [CFString: Any]?) -> Data? {
        guard let cg = image.cgImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, properties as CFDictionary?)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// The MIME type of a file, by extension (JPEG for anything that is not PNG).
    public static func mediaType(for url: URL) -> String {
        url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
    }
}
