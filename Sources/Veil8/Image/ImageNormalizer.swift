//
//  ImageNormalizer.swift
//  Veil8
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  The canonical form of a picture, stored or generated: long side ≤ maxLongSide (the working
//  scale, downsampled, never upscaled), then padded right/bottom to a multiple of the tile size
//  by edge replication. A generated frame is canonicalised the same way, so both sides of a
//  comparison meet at one scale.
//

import Foundation

public struct CanonicalImagePolicy: Codable, Sendable, Equatable {
    public var maxLongSide: Int
    public var tileSize: Int

    public init(maxLongSide: Int = Veil8Format.canonicalLongSide, tileSize: Int = Veil8Format.tileSize) {
        self.maxLongSide = maxLongSide
        self.tileSize = tileSize
    }

    public static let standard = CanonicalImagePolicy()
}

/// A canonical image plus the geometry that produced it.
public struct NormalizedImage: Sendable {
    /// Padded canonical pixels (`grid.width × grid.height`).
    public let image: RGBAImage
    public let original: PixelSize
    /// Size after resampling, before padding.
    public let scaled: PixelSize
    public let grid: TileGrid
    public let policy: CanonicalImagePolicy

    public var padded: PixelSize { PixelSize(width: grid.width, height: grid.height) }
    public var padRight: Int { grid.width - scaled.width }
    public var padBottom: Int { grid.height - scaled.height }

    /// Whether a tile lies entirely inside the padding strips (no original pixels at all).
    public func isPaddingTile(_ index: Int) -> Bool {
        let rect = grid.pixelRect(index)
        return rect.x >= scaled.width || rect.y >= scaled.height
    }

    /// Tiles that contain at least one original pixel.
    public var contentTiles: [Int] { (0..<grid.count).filter { !isPaddingTile($0) } }
}

public enum ImageNormalizer {
    /// Downsample target: the long side becomes `maxLongSide` (rounded other side), never upscaled.
    public static func targetSize(for size: PixelSize, maxLongSide: Int) -> PixelSize {
        guard size.longSide > maxLongSide, size.longSide > 0 else { return size }
        let scale = Double(maxLongSide) / Double(size.longSide)
        if size.width >= size.height {
            return PixelSize(width: maxLongSide, height: max(1, Int((Double(size.height) * scale).rounded())))
        } else {
            return PixelSize(width: max(1, Int((Double(size.width) * scale).rounded())), height: maxLongSide)
        }
    }

    /// Size after padding up to multiples of `multiple`.
    public static func paddedSize(for size: PixelSize, multipleOf multiple: Int) -> PixelSize {
        func up(_ v: Int) -> Int { (v + multiple - 1) / multiple * multiple }
        return PixelSize(width: up(size.width), height: up(size.height))
    }

    public static func normalize(_ image: RGBAImage, policy: CanonicalImagePolicy = .standard) -> NormalizedImage {
        let target = targetSize(for: image.size, maxLongSide: policy.maxLongSide)
        let scaled = ImageLoader.resized(image, to: target)
        let padded = pad(scaled, multipleOf: policy.tileSize)
        let grid = TileGrid(width: padded.width, height: padded.height, tileSize: policy.tileSize)!
        return NormalizedImage(image: padded, original: image.size, scaled: scaled.size, grid: grid, policy: policy)
    }

    /// Pads right/bottom to multiples of `multiple` by replicating the last column and row.
    public static func pad(_ image: RGBAImage, multipleOf multiple: Int) -> RGBAImage {
        let target = paddedSize(for: image.size, multipleOf: multiple)
        guard target != image.size else { return image }
        let w = image.width, h = image.height
        let tw = target.width, th = target.height
        var out = [UInt8](repeating: 0, count: tw * th * 4)
        image.pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<th {
                    let sy = min(y, h - 1)
                    let srcRow = sy * w * 4
                    let dstRow = y * tw * 4
                    // Copy the source row, then replicate its last pixel across the pad strip.
                    for i in 0..<(w * 4) { dst[dstRow + i] = src[srcRow + i] }
                    if tw > w {
                        let last = srcRow + (w - 1) * 4
                        for x in w..<tw {
                            let d = dstRow + x * 4
                            dst[d] = src[last]; dst[d + 1] = src[last + 1]; dst[d + 2] = src[last + 2]; dst[d + 3] = src[last + 3]
                        }
                    }
                }
            }
        }
        return RGBAImage(width: tw, height: th, pixels: out)
    }
}
