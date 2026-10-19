//
//  TilerCPU.swift
//  Veil8
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  The reference tiler: plain loops over an RGBAImage. Veil's Metal tiler is tested against it,
//  byte for byte.
//

import Foundation

public enum TilerCPU {
    /// Tile-major RGBA8 bytes: tile `i` (row-major over the grid) occupies
    /// `[i * tileSize² * 4, (i + 1) * tileSize² * 4)`, pixels row-major within the tile.
    public static func tileBytes(_ image: RGBAImage, grid: TileGrid) -> [UInt8] {
        precondition(image.width == grid.width && image.height == grid.height, "image does not match grid")
        let ts = grid.tileSize
        let rowBytes = image.width * 4
        let tileRowBytes = ts * 4
        var out = [UInt8](repeating: 0, count: grid.count * ts * ts * 4)
        image.pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for r in 0..<grid.rows {
                    for c in 0..<grid.cols {
                        let tile = grid.index(row: r, col: c)
                        let base = tile * ts * ts * 4
                        for y in 0..<ts {
                            let s = (r * ts + y) * rowBytes + c * tileRowBytes
                            let d = base + y * tileRowBytes
                            for k in 0..<tileRowBytes { dst[d + k] = src[s + k] }
                        }
                    }
                }
            }
        }
        return out
    }

    /// The inverse: tile-major bytes back to a row-major image (for tests and previews).
    public static func image(fromTileBytes bytes: [UInt8], grid: TileGrid) -> RGBAImage {
        let ts = grid.tileSize
        let rowBytes = grid.width * 4
        let tileRowBytes = ts * 4
        var out = [UInt8](repeating: 0, count: grid.width * grid.height * 4)
        bytes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for r in 0..<grid.rows {
                    for c in 0..<grid.cols {
                        let base = grid.index(row: r, col: c) * ts * ts * 4
                        for y in 0..<ts {
                            let d = (r * ts + y) * rowBytes + c * tileRowBytes
                            let s = base + y * tileRowBytes
                            for k in 0..<tileRowBytes { dst[d + k] = src[s + k] }
                        }
                    }
                }
            }
        }
        return RGBAImage(width: grid.width, height: grid.height, pixels: out)
    }
}

/// Flat tiles (uniform colour) match every other flat tile in the index; they carry no
/// evidence and are excluded on both sides of a search.
public enum FlatTileDetector {
    /// True when every RGB channel's standard deviation is below `threshold` (0–255 scale).
    public static func isFlat(rgba: UnsafeBufferPointer<UInt8>, threshold: Float) -> Bool {
        let n = rgba.count / 4
        guard n > 0 else { return true }
        var sum = (0.0, 0.0, 0.0)
        var sq = (0.0, 0.0, 0.0)
        var i = 0
        while i < n * 4 {
            let r = Double(rgba[i]), g = Double(rgba[i + 1]), b = Double(rgba[i + 2])
            sum.0 += r; sum.1 += g; sum.2 += b
            sq.0 += r * r; sq.1 += g * g; sq.2 += b * b
            i += 4
        }
        let d = Double(n)
        func sd(_ s: Double, _ q: Double) -> Double { max(0, q / d - (s / d) * (s / d)).squareRoot() }
        let maxSD = max(sd(sum.0, sq.0), sd(sum.1, sq.1), sd(sum.2, sq.2))
        return Float(maxSD) < threshold
    }

    public static func flags(tileBytes: [UInt8], grid: TileGrid, threshold: Float) -> [Bool] {
        let stride = grid.pixelsPerTile * 4
        return tileBytes.withUnsafeBufferPointer { all in
            (0..<grid.count).map { i in
                isFlat(rgba: UnsafeBufferPointer(rebasing: all[(i * stride)..<((i + 1) * stride)]), threshold: threshold)
            }
        }
    }
}
