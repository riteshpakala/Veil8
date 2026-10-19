//
//  VeilFrame.swift
//  Veil8
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  One image ready to encode: the padded canonical picture, its grid, the tile-major pixel bytes
//  the serializers consume, and which tiles are flat.
//

import Foundation

public struct VeilFrame: Sendable {
    public let grid: TileGrid
    /// The padded image (`grid.width × grid.height`).
    public let preview: RGBAImage
    /// Tile-major RGBA8 bytes (see `TilerCPU.tileBytes`).
    public let tileBytes: [UInt8]
    /// Flat (uniform) tiles, excluded from queries.
    public let flat: [Bool]
    /// Tiles that hold only padding (no original pixels); empty when the frame was not padded.
    public let paddingTiles: Set<Int>

    public init(grid: TileGrid, preview: RGBAImage, tileBytes: [UInt8], flat: [Bool], paddingTiles: Set<Int> = []) {
        precondition(tileBytes.count == grid.count * grid.pixelsPerTile * 4)
        precondition(flat.count == grid.count)
        self.grid = grid
        self.preview = preview
        self.tileBytes = tileBytes
        self.flat = flat
        self.paddingTiles = paddingTiles
    }

    public var tileByteCount: Int { grid.pixelsPerTile * 4 }
    public var tileCount: Int { grid.count }

    /// Tiles worth encoding: neither flat nor pure padding.
    public var activeTiles: [Int] {
        (0..<grid.count).filter { !flat[$0] && !paddingTiles.contains($0) }
    }

    public func tileSlice(_ i: Int) -> ArraySlice<UInt8> {
        tileBytes[(i * tileByteCount)..<((i + 1) * tileByteCount)]
    }

    /// Packed RGBA words of a tile, row-major.
    public func tileWords(_ i: Int) -> [UInt32] {
        let s = tileSlice(i)
        var out = [UInt32](repeating: 0, count: grid.pixelsPerTile)
        var j = s.startIndex
        for p in 0..<grid.pixelsPerTile {
            out[p] = (UInt32(s[j]) << 24) | (UInt32(s[j + 1]) << 16) | (UInt32(s[j + 2]) << 8) | UInt32(s[j + 3])
            j += 4
        }
        return out
    }

    public func tileImage(_ i: Int) -> RGBAImage {
        RGBAImage(width: grid.tileSize, height: grid.tileSize, pixels: Array(tileSlice(i)))
    }

    /// Serialized strings for the given tiles (default: every active tile), in the given order.
    /// Tiles are independent, so more than a handful are serialized across the cores — the
    /// one-way encoder does a few hundred thousand multiplies per tile.
    public func serialize(_ serializer: any TileSerializer, tiles: [Int]? = nil) -> [String] {
        let indices = tiles ?? activeTiles
        let size = tileByteCount
        return tileBytes.withUnsafeBufferPointer { all in
            guard indices.count >= 16 else {
                return indices.map { serializer.serialize(rgba: UnsafeBufferPointer(rebasing: all[($0 * size)..<(($0 + 1) * size)])) }
            }
            var out = [String](repeating: "", count: indices.count)
            out.withUnsafeMutableBufferPointer { buffer in
                // Each iteration reads its own tile and writes its own element, nothing else.
                nonisolated(unsafe) let strings = buffer
                nonisolated(unsafe) let bytes = all
                DispatchQueue.concurrentPerform(iterations: indices.count) { k in
                    let i = indices[k]
                    strings[k] = serializer.serialize(rgba: UnsafeBufferPointer(rebasing: bytes[(i * size)..<((i + 1) * size)]))
                }
            }
            return out
        }
    }

    // MARK: - Construction

    /// Tiles an image on the CPU, padding to the tile size by edge replication when needed.
    public static func make(image: RGBAImage, tileSize: Int = Veil8Format.tileSize, minTileVariance: Float = 4.0) -> VeilFrame {
        let padded = ImageNormalizer.pad(image, multipleOf: tileSize)
        let grid = TileGrid(width: padded.width, height: padded.height, tileSize: tileSize)!
        let bytes = TilerCPU.tileBytes(padded, grid: grid)
        let flat = FlatTileDetector.flags(tileBytes: bytes, grid: grid, threshold: minTileVariance)
        var padding = Set<Int>()
        if padded.size != image.size {
            for i in 0..<grid.count {
                let rect = grid.pixelRect(i)
                if rect.x >= image.width || rect.y >= image.height { padding.insert(i) }
            }
        }
        return VeilFrame(grid: grid, preview: padded, tileBytes: bytes, flat: flat, paddingTiles: padding)
    }

    /// A frame over an already-normalized image, marking its padding tiles.
    public static func make(normalized: NormalizedImage, minTileVariance: Float = 4.0) -> VeilFrame {
        let bytes = TilerCPU.tileBytes(normalized.image, grid: normalized.grid)
        let flat = FlatTileDetector.flags(tileBytes: bytes, grid: normalized.grid, threshold: minTileVariance)
        let padding = Set((0..<normalized.grid.count).filter { normalized.isPaddingTile($0) })
        return VeilFrame(grid: normalized.grid, preview: normalized.image, tileBytes: bytes, flat: flat, paddingTiles: padding)
    }
}
