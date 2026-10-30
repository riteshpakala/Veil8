//
//  Veil8Format.swift
//  Veil8
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  What this package is: the process that turns a picture into Veil's tile strings, and the one
//  encoding among them that cannot be turned back into pixels.
//
//      picture ──ImageLoader──▶ RGBAImage ──ImageNormalizer──▶ NormalizedImage (long side ≤ 512,
//      padded to a multiple of 32) ──VeilFrame.make──▶ tiles ──Veil8Encoder(key)──▶ one string per tile
//
//  A string is 1024 two-letter words, one per pixel; each word is eight one-bit keyed
//  measurements of the pixel's 5×5 neighbourhood. Many tiles write the same string, and the
//  string does not say which — but tiles that look alike share most of their words, which is all
//  matching needs. SPEC.md, which says every step byte for byte, will be added later;
//  Tests/Veil8Tests/Fixtures/rgb-veil8.json is the vector every implementation must reproduce.
//
//  Everything here is deterministic and offline. Embedding the strings, storing them and matching
//  them is the application's business (Veil's), not this package's.
//

import Foundation

public enum Veil8Format {
    /// The contract every implementation honours: the canonical image, the tiles, the encoding, the key.
    public static let contract = "veil.tiles.v1"
    /// The encoding's id, as a corpus names it.
    public static let encoding = "rgb-veil8"
    /// The side of a tile in pixels; a tile's string has `tileSize²` words.
    public static let tileSize = 32
    /// The working scale: the long side of every canonical image. A one-bit 5×5 measurement
    /// cannot be made scale-invariant, so both sides of a comparison are brought to one scale,
    /// and the coarser side sets it: the smallest size a model draws. Never upscaled.
    public static let canonicalLongSide = 512
}
