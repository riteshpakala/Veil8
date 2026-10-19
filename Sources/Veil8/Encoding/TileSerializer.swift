//
//  TileSerializer.swift
//  Veil8
//
//  A tile's pixels as a string, so a text embedding model can embed it. Veil8Encoder is the
//  one-way serializer this package defines; Veil adds reversible ones (the pixels as hex) behind
//  the same shape, so a frame can be written with any of them.
//

import Foundation

public protocol TileSerializer: Sendable {
    /// Characters per pixel word.
    var charsPerPixel: Int { get }
    /// Serializes one tile's RGBA8 bytes (row-major, `pixels * 4` bytes): one word per pixel,
    /// words separated by exactly one space, no leading or trailing whitespace, no newlines.
    func serialize(rgba: UnsafeBufferPointer<UInt8>) -> String
}

extension TileSerializer {
    public func serialize(rgba bytes: [UInt8]) -> String {
        bytes.withUnsafeBufferPointer { serialize(rgba: $0) }
    }

    public func serialize(rgba slice: ArraySlice<UInt8>) -> String {
        slice.withUnsafeBufferPointer { serialize(rgba: $0) }
    }

    /// Characters in a serialized tile of `pixels` pixels (digits plus separators).
    public func characterCount(pixels: Int) -> Int {
        guard pixels > 0 else { return 0 }
        return pixels * charsPerPixel + (pixels - 1)
    }
}
