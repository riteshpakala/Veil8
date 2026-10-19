//
//  Veil8Format.swift
//  Veil8
//
//  What this package is: the process that turns a picture into Veil's tile strings, and the one
//  encoding among them that cannot be turned back into pixels.
//
//      picture ──ImageLoader──▶ RGBAImage ──ImageNormalizer──▶ NormalizedImage (long side ≤ 1080,
//      padded to a multiple of 32) ──VeilFrame.make──▶ tiles ──Veil8Encoder(key)──▶ one string per tile
//
//  A string is 1024 two-letter words, one per pixel; each word is eight one-bit keyed
//  measurements of the pixel's 5×5 neighbourhood. Many tiles write the same string, and the
//  string does not say which — but tiles that look alike share most of their words, which is all
//  matching needs. SPEC.md says every step byte for byte; Tests/Veil8Tests/Fixtures/rgb-veil8.json
//  is the vector every implementation must reproduce.
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
}
