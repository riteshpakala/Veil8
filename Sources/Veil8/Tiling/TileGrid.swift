//
//  TileGrid.swift
//  Veil8
//

import Foundation

/// A fixed tiling of an image: `rows × cols` tiles of `tileSize` pixels, row-major.
public struct TileGrid: Codable, Sendable, Hashable {
    public let tileSize: Int
    public let rows: Int
    public let cols: Int

    public init(tileSize: Int, rows: Int, cols: Int) {
        self.tileSize = tileSize
        self.rows = rows
        self.cols = cols
    }

    /// Nil unless both dimensions are multiples of the tile size.
    public init?(width: Int, height: Int, tileSize: Int) {
        guard tileSize > 0, width > 0, height > 0, width % tileSize == 0, height % tileSize == 0 else { return nil }
        self.init(tileSize: tileSize, rows: height / tileSize, cols: width / tileSize)
    }

    public var width: Int { cols * tileSize }
    public var height: Int { rows * tileSize }
    public var count: Int { rows * cols }
    public var pixelsPerTile: Int { tileSize * tileSize }

    @inlinable public func index(row: Int, col: Int) -> Int { row * cols + col }
    @inlinable public func rowCol(_ index: Int) -> (row: Int, col: Int) { (index / cols, index % cols) }

    public func pixelRect(_ index: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let (r, c) = rowCol(index)
        return (c * tileSize, r * tileSize, tileSize, tileSize)
    }

    public func contains(row: Int, col: Int) -> Bool { row >= 0 && row < rows && col >= 0 && col < cols }

    public var description: String { "\(cols)×\(rows) tiles of \(tileSize)px (\(width)×\(height))" }
}
