//
//  Support.swift
//  VeilKeyTests
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//

import Foundation
import Veil8
import VeilKey

/// The key every keyed test uses: bytes 0…31, as in Veil8's `Fixtures/rgb-veil8.json`.
let testKey = VeilKey(bytes: Array(0..<32))!
/// The same key as its file spells it: 64 hex digits.
let testKeyHex = (0..<32).map { String(format: "%02x", $0) }.joined()

/// A fresh directory under the system's temporary folder.
func scratchDirectory(_ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("veilkey-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func mode(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o777
}

/// A deterministic 32×32 tile, the fixture's pattern.
func fixtureTile() -> [UInt8] {
    var pixels = [UInt8]()
    for y in 0..<32 {
        for x in 0..<32 {
            pixels += [UInt8((7 * x + 13 * y) & 255), UInt8((x * x + 3 * y) & 255), UInt8((x ^ (5 * y)) & 255), 255]
        }
    }
    return pixels
}
