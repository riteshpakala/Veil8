//
//  Veil8Encoder.swift
//  Veil8
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  A tile's pixels as a string that cannot be turned back into the pixels. Each pixel
//  becomes a few one-bit measurements of its neighbourhood:
//
//      u      the (2r+1)² RGB window around the pixel, edge-replicated at the tile border
//      m_j    Σ G[j][i] · u[i]                    G: Gaussian weights drawn from the key
//      bit_j  ⌊(m_j + w_j) / Δ_j⌋ mod 2           w: dither drawn from the key, Δ: the step
//
//  and the bits of a pixel, first measurement in the high bit, are its word: two letters,
//  one per four bits, from the alphabet `cdefhiklmnoprstw` (c = 0 … w = 15). Words are
//  row-major and separated by one space, like every other serializer.
//
//  Why letters and not hex: a text embedder reads tokens, not characters. In the Qwen3
//  vocabulary voyage-4-nano uses, every one of the 256 words these letters make is a single
//  token, with or without a leading space, so a tile is exactly 1024 tokens — one per pixel.
//  Hex words split in two ("Ġb" + "6") and blur the measurement across tokens; calibrated
//  2026-10-04 at step 32, the letters separated matching tiles from unrelated ones by +0.023
//  to +0.056 in cosine where hex overlapped (−0.001 to −0.031), at a quarter of the time per tile
//  (Veil's Docs/CALIBRATION.md).
//
//  Three things are lost on the way, and none can be undone: 75 values collapse to 8
//  (the weights have a 67-dimensional null space), the floor drops whatever is finer
//  than the step, and `mod 2` drops the magnitude. What survives is locality — tiles
//  that look alike share most of their words — which is all matching needs.
//
//  Everything is integer arithmetic so another implementation can match it byte for
//  byte (SPEC.md, to be added later):
//
//    weights   for j, dy, dx, channel in that order, two bytes a, b from the key stream
//              "veil.tiles.v1/rgb-veil8/weights": G = B[dy] · B[dx] · (popcount(a) − popcount(b)),
//              B the binomial row of the window (1 4 6 4 1 for r = 2)
//    step      Δ_j = isqrt(step² · Σ G[j]²), at least 1 — `step` grey levels per unit of weight norm
//    dither    w_j = (eight bytes, big-endian, from ".../dither") mod 2Δ_j
//    division  floor, not truncation
//

import Foundation

public struct Veil8Encoder: TileSerializer {
    /// The key stream the weights are drawn from.
    public static let weightsLabel = "veil.tiles.v1/rgb-veil8/weights"
    /// The key stream the dither is drawn from.
    public static let ditherLabel = "veil.tiles.v1/rgb-veil8/dither"

    public let charsPerPixel: Int
    public let parameters: Veil8Parameters
    /// The fingerprint of the key this encoder writes with: what a corpus records as its `keyID`.
    public let keyFingerprint: String

    private let window: Int
    /// `measurements × window × window × 3`, in draw order.
    let weights: [Int]
    let steps: [Int]
    let dither: [Int]

    public init(key: Veil8Key, parameters: Veil8Parameters = .standard) {
        self.parameters = parameters
        self.charsPerPixel = parameters.measurements / 4
        self.keyFingerprint = key.fingerprint
        let window = 2 * parameters.radius + 1
        self.window = window
        let envelope = Self.binomialRow(window)
        let perMeasurement = window * window * 3

        var weightStream = key.stream(Self.weightsLabel)
        var weights = [Int]()
        weights.reserveCapacity(parameters.measurements * perMeasurement)
        for _ in 0..<parameters.measurements {
            for dy in 0..<window {
                for dx in 0..<window {
                    for _ in 0..<3 {
                        let a = weightStream.nextByte(), b = weightStream.nextByte()
                        weights.append(envelope[dy] * envelope[dx] * (a.nonzeroBitCount - b.nonzeroBitCount))
                    }
                }
            }
        }

        var ditherStream = key.stream(Self.ditherLabel)
        var steps = [Int](), dither = [Int]()
        for j in 0..<parameters.measurements {
            let squares = weights[(j * perMeasurement)..<((j + 1) * perMeasurement)].reduce(0) { $0 + $1 * $1 }
            let step = max(1, Self.isqrt(parameters.step * parameters.step * squares))
            steps.append(step)
            dither.append(Int(ditherStream.nextUInt64() % UInt64(2 * step)))
        }
        self.weights = weights
        self.steps = steps
        self.dither = dither
    }

    public func serialize(rgba: UnsafeBufferPointer<UInt8>) -> String {
        let pixels = rgba.count / 4
        guard pixels > 0 else { return "" }
        // A tile is square; anything else is read as a single row.
        let side = Int(Double(pixels).squareRoot().rounded())
        let (width, height) = side * side == pixels ? (side, side) : (pixels, 1)
        let radius = parameters.radius, measurements = parameters.measurements
        let paddedWidth = width + 2 * radius, paddedHeight = height + 2 * radius

        // RGB with the border replicated, so every pixel has a whole window.
        var padded = [Int](repeating: 0, count: paddedWidth * paddedHeight * 3)
        for py in 0..<paddedHeight {
            let y = min(height - 1, max(0, py - radius))
            for px in 0..<paddedWidth {
                let x = min(width - 1, max(0, px - radius))
                let source = (y * width + x) * 4, target = (py * paddedWidth + px) * 3
                padded[target] = Int(rgba[source])
                padded[target + 1] = Int(rgba[source + 1])
                padded[target + 2] = Int(rgba[source + 2])
            }
        }

        let run = window * 3
        var buf = [UInt8](repeating: 32, count: characterCount(pixels: pixels))
        Array(parameters.digits.utf8).withUnsafeBufferPointer { nib in
            padded.withUnsafeBufferPointer { p in
                weights.withUnsafeBufferPointer { w in
                    buf.withUnsafeMutableBufferPointer { out in
                        var o = 0
                        for y in 0..<height {
                            for x in 0..<width {
                                var word = 0
                                for j in 0..<measurements {
                                    var m = 0
                                    for dy in 0..<window {
                                        let source = ((y + dy) * paddedWidth + x) * 3
                                        let weight = (j * window + dy) * run
                                        for t in 0..<run { m &+= w[weight + t] &* p[source + t] }
                                    }
                                    word = (word << 1) | (Self.floorDivide(m + dither[j], steps[j]) & 1)
                                }
                                for digit in stride(from: charsPerPixel - 1, through: 0, by: -1) {
                                    out[o] = nib[(word >> (4 * digit)) & 15]
                                    o += 1
                                }
                                o += 1 // separator (already a space)
                            }
                        }
                    }
                }
            }
        }
        return String(decoding: buf, as: UTF8.self)
    }

    // MARK: - Arithmetic

    /// Row `n − 1` of Pascal's triangle: the integer Gaussian.
    static func binomialRow(_ n: Int) -> [Int] {
        var row = [1]
        for _ in 1..<max(1, n) { row = zip([0] + row, row + [0]).map(+) }
        return row
    }

    static func isqrt(_ x: Int) -> Int {
        guard x > 0 else { return 0 }
        var r = Int(Double(x).squareRoot())
        while r * r > x { r -= 1 }
        while (r + 1) * (r + 1) <= x { r += 1 }
        return r
    }

    /// `⌊a / b⌋` for `b > 0`.
    @inline(__always)
    static func floorDivide(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && a < 0) ? q - 1 : q
    }
}
