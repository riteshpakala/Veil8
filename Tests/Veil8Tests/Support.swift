import CryptoKit
import Foundation
import Testing
@testable import Veil8

/// The key every keyed test uses: bytes 0…31, as in `Fixtures/rgb-veil8.json`.
let testKey = Veil8Key(bytes: Array(0..<32))!
/// The same key as the file spells it.
let testKeyHex = (0..<32).map { String(format: "%02x", $0) }.joined()

/// SplitMix64 — tiny, fast, well-distributed: the tests' deterministic noise.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A deterministic noisy image (every tile distinct, none flat).
func syntheticImage(width: Int, height: Int, seed: UInt64 = 1) -> RGBAImage {
    var rng = SplitMix64(seed: seed)
    var px = [UInt8](repeating: 0, count: width * height * 4)
    var i = 0
    while i < px.count {
        let r = rng.next()
        px[i] = UInt8(truncatingIfNeeded: r)
        px[i + 1] = UInt8(truncatingIfNeeded: r >> 8)
        px[i + 2] = UInt8(truncatingIfNeeded: r >> 16)
        px[i + 3] = 255
        i += 4
    }
    return RGBAImage(width: width, height: height, pixels: px)
}

func sha256Hex(_ string: String) -> String {
    SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// A fresh directory under the system's temporary folder.
func scratchDirectory(_ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("veil8-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
