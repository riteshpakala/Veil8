//
//  RGBAImage.swift
//  Veil8
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  The one pixel type that crosses module boundaries: straight-alpha RGBA8, row-major,
//  top row first. Generated frames and stored images alike are opaque (alpha 255), which
//  the serializers rely on for the UInt32 pixel words.
//

import CoreGraphics
import CryptoKit
import Foundation

public struct PixelSize: Codable, Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var longSide: Int { max(width, height) }
}

public struct RGBAImage: Sendable, Hashable {
    public let width: Int
    public let height: Int
    /// RGBA8, row-major, top row first, straight alpha. Count is `width * height * 4`.
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "RGBAImage: \(pixels.count) bytes for \(width)×\(height)")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (0, 0, 0, 255)) {
        self.width = width
        self.height = height
        var px = [UInt8](repeating: 0, count: width * height * 4)
        var i = 0
        while i < px.count {
            px[i] = fill.r; px[i + 1] = fill.g; px[i + 2] = fill.b; px[i + 3] = fill.a
            i += 4
        }
        self.pixels = px
    }

    public var size: PixelSize { PixelSize(width: width, height: height) }
    public var byteCount: Int { pixels.count }

    @inlinable
    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }

    /// The packed word the serializers use: `(r << 24) | (g << 16) | (b << 8) | a`.
    @inlinable
    public func word(x: Int, y: Int) -> UInt32 {
        let p = pixel(x: x, y: y)
        return (UInt32(p.r) << 24) | (UInt32(p.g) << 16) | (UInt32(p.b) << 8) | UInt32(p.a)
    }

    /// SHA-256 over the dimensions and the pixel bytes — the document identity of a canonical image.
    public var sha256: String {
        var hasher = SHA256()
        let header = [UInt32(width).littleEndian, UInt32(height).littleEndian]
        header.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        pixels.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A sub-image (clamped to bounds).
    public func cropped(x: Int, y: Int, width w: Int, height h: Int) -> RGBAImage {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + w), y1 = min(height, y + h)
        let cw = max(0, x1 - x0), ch = max(0, y1 - y0)
        var out = [UInt8](repeating: 0, count: cw * ch * 4)
        guard cw > 0, ch > 0 else { return RGBAImage(width: cw, height: ch, pixels: out) }
        for row in 0..<ch {
            let src = ((y0 + row) * width + x0) * 4
            let dst = row * cw * 4
            out.replaceSubrange(dst..<(dst + cw * 4), with: pixels[src..<(src + cw * 4)])
        }
        return RGBAImage(width: cw, height: ch, pixels: out)
    }

    // MARK: - CoreGraphics bridging

    /// A CGImage over a copy of the pixels (straight alpha, sRGB).
    public func cgImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Renders a CGImage into RGBA8 over an opaque black background (alpha always 255).
    public init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, pixels: buf)
    }
}
