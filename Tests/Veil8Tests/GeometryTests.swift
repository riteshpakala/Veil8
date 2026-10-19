//
//  GeometryTests.swift
//  Veil8Tests
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//

import Foundation
import Testing
@testable import Veil8

/// The canonical image and its tiles (SPEC.md, to be added later: "The canonical image" and "Tiles").
@Suite struct GeometryTests {
    @Test func tileGridIndexing() {
        let g = TileGrid(width: 96, height: 64, tileSize: 32)!
        #expect(g.rows == 2 && g.cols == 3 && g.count == 6)
        #expect(g.index(row: 1, col: 2) == 5)
        #expect(g.rowCol(5) == (1, 2))
        let r = g.pixelRect(4)
        #expect(r.x == 32 && r.y == 32 && r.width == 32)
        #expect(TileGrid(width: 100, height: 64, tileSize: 32) == nil)
    }

    /// The grid is stored beside every corpus document as JSON; its coding is part of the contract.
    @Test func aGridCodesAsItsThreeNumbers() throws {
        let g = TileGrid(width: 832, height: 1088, tileSize: 32)!
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(g), as: UTF8.self) == #"{"cols":26,"rows":34,"tileSize":32}"#)
        #expect(try JSONDecoder().decode(TileGrid.self, from: Data(#"{"tileSize":32,"rows":34,"cols":26}"#.utf8)) == g)
    }

    @Test func targetSizesForTheAssets() {
        #expect(ImageNormalizer.targetSize(for: PixelSize(width: 3024, height: 4032), maxLongSide: 1080) == PixelSize(width: 810, height: 1080))
        #expect(ImageNormalizer.targetSize(for: PixelSize(width: 3840, height: 2160), maxLongSide: 1080) == PixelSize(width: 1080, height: 608))
        #expect(ImageNormalizer.targetSize(for: PixelSize(width: 1024, height: 1024), maxLongSide: 1080) == PixelSize(width: 1024, height: 1024))
        #expect(ImageNormalizer.targetSize(for: PixelSize(width: 300, height: 200), maxLongSide: 1080) == PixelSize(width: 300, height: 200))
        #expect(ImageNormalizer.paddedSize(for: PixelSize(width: 810, height: 1080), multipleOf: 32) == PixelSize(width: 832, height: 1088))
        #expect(ImageNormalizer.paddedSize(for: PixelSize(width: 1080, height: 608), multipleOf: 32) == PixelSize(width: 1088, height: 608))
        #expect(ImageLoader.orientedSize(PixelSize(width: 4032, height: 3024), orientation: 6) == PixelSize(width: 3024, height: 4032))
        #expect(ImageLoader.orientedSize(PixelSize(width: 4032, height: 3024), orientation: 3) == PixelSize(width: 4032, height: 3024))
    }

    @Test func edgeReplicationPadding() {
        let img = syntheticImage(width: 40, height: 33, seed: 5)
        let padded = ImageNormalizer.pad(img, multipleOf: 32)
        #expect(padded.width == 64 && padded.height == 64)
        // Inside: unchanged. Right strip: last column. Bottom strip: last row (of the padded row above).
        #expect(padded.pixel(x: 10, y: 10) == img.pixel(x: 10, y: 10))
        #expect(padded.pixel(x: 63, y: 5) == img.pixel(x: 39, y: 5))
        #expect(padded.pixel(x: 5, y: 60) == img.pixel(x: 5, y: 32))
        #expect(padded.pixel(x: 63, y: 63) == img.pixel(x: 39, y: 32))
    }

    @Test func normalizeReportsGeometry() {
        let img = syntheticImage(width: 2000, height: 1000, seed: 9)
        let n = ImageNormalizer.normalize(img, policy: CanonicalImagePolicy(maxLongSide: 1080, tileSize: 32))
        #expect(n.scaled == PixelSize(width: 1080, height: 540))
        #expect(n.grid.cols == 34 && n.grid.rows == 17)
        #expect(n.padRight == 8 && n.padBottom == 4)
        #expect(n.contentTiles.count == n.grid.count)   // every tile has some content when the pad is < 32
        #expect(CanonicalImagePolicy.standard == CanonicalImagePolicy(maxLongSide: 1080, tileSize: 32))
    }

    /// A small image is never upscaled, and its canonical pixels are its own, padded.
    @Test func normalizeNeverUpscales() {
        let img = syntheticImage(width: 100, height: 70, seed: 4)
        let n = ImageNormalizer.normalize(img)
        #expect(n.scaled == img.size && n.padded == PixelSize(width: 128, height: 96))
        #expect(n.image == ImageNormalizer.pad(img, multipleOf: 32))
    }

    @Test func cpuTilerRoundTrip() {
        let img = syntheticImage(width: 96, height: 64, seed: 11)
        let grid = TileGrid(width: 96, height: 64, tileSize: 32)!
        let bytes = TilerCPU.tileBytes(img, grid: grid)
        #expect(bytes.count == 6 * 4096)
        // Tile (1, 2) starts at pixel (64, 32).
        let frame = VeilFrame(grid: grid, preview: img, tileBytes: bytes, flat: [Bool](repeating: false, count: 6))
        #expect(frame.tileWords(5)[0] == img.word(x: 64, y: 32))
        #expect(frame.tileWords(5)[33] == img.word(x: 65, y: 33))
        #expect(TilerCPU.image(fromTileBytes: bytes, grid: grid) == img)
        #expect(frame.tileImage(5) == img.cropped(x: 64, y: 32, width: 32, height: 32))
    }

    @Test func flatDetection() {
        let flat = RGBAImage(width: 32, height: 32, fill: (10, 20, 30, 255))
        let noisy = syntheticImage(width: 32, height: 32)
        #expect(flat.pixels.withUnsafeBufferPointer { FlatTileDetector.isFlat(rgba: $0, threshold: 4) })
        #expect(!noisy.pixels.withUnsafeBufferPointer { FlatTileDetector.isFlat(rgba: $0, threshold: 4) })
        let frame = VeilFrame.make(image: syntheticImage(width: 40, height: 40, seed: 2))
        #expect(frame.grid.count == 4)
        #expect(frame.paddingTiles.isEmpty)   // every tile has content pixels
        let frame2 = VeilFrame.make(image: syntheticImage(width: 32, height: 40, seed: 2))
        #expect(frame2.paddingTiles.isEmpty && frame2.grid.rows == 2)
    }

    /// The image's identity: SHA-256 over width and height (u32 little-endian) and the RGBA bytes.
    @Test func theIdentityHashesSizeAndPixels() {
        let a = RGBAImage(width: 2, height: 1, pixels: [1, 2, 3, 255, 4, 5, 6, 255])
        let b = RGBAImage(width: 1, height: 2, pixels: a.pixels)
        #expect(a.sha256.count == 64 && a.sha256 != b.sha256, "the same bytes in another shape are another image")
        #expect(a.sha256 == RGBAImage(width: 2, height: 1, pixels: a.pixels).sha256)
    }
}
