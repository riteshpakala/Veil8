import Foundation
import Testing
@testable import Veil8

@Suite struct Veil8EncoderTests {
    /// Every field of `Fixtures/rgb-veil8.json`.
    struct Golden: Decodable {
        let contract: String
        let serializer: String
        let key: String
        let fingerprint: String
        let letters: String
        let steps: [Int]
        let dither: [Int]
        let firstWeights: [Int]
        let characters: Int
        let head: String
        let sha256: String
    }

    /// The fixture's tile: pixel (x, y) = r (7x + 13y) & 255, g (x·x + 3y) & 255, b (x ^ 5y) & 255.
    func goldenTile() -> [UInt8] {
        var px = [UInt8]()
        px.reserveCapacity(32 * 32 * 4)
        for y in 0..<32 {
            for x in 0..<32 {
                px += [UInt8((7 * x + 13 * y) & 255), UInt8((x * x + 3 * y) & 255), UInt8((x ^ (5 * y)) & 255), 255]
            }
        }
        return px
    }

    /// How many words two tile strings share, position by position.
    func sharedWords(_ a: String, _ b: String) -> Double {
        let wa = a.split(separator: " "), wb = b.split(separator: " ")
        return Double(zip(wa, wb).filter { $0 == $1 }.count) / Double(wa.count)
    }

    /// The same string an independent implementation of SPEC.md produced, and the same weights,
    /// steps and dither on the way to it.
    @Test func matchesTheReferenceImplementation() throws {
        let url = try #require(Bundle.module.url(forResource: "rgb-veil8", withExtension: "json", subdirectory: "Fixtures"))
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        #expect(golden.contract == Veil8Format.contract && golden.serializer == Veil8Format.encoding)
        #expect(golden.letters == Veil8Parameters.letters)
        let key = try #require(Veil8Key(hex: golden.key))
        #expect(key == testKey && key.fingerprint == golden.fingerprint)
        let encoder = Veil8Encoder(key: key)
        #expect(encoder.keyFingerprint == golden.fingerprint)
        #expect(encoder.steps == golden.steps)
        #expect(encoder.dither == golden.dither)
        #expect(Array(encoder.weights.prefix(golden.firstWeights.count)) == golden.firstWeights)
        let string = encoder.serialize(rgba: goldenTile())
        #expect(string.count == golden.characters)
        #expect(String(string.prefix(golden.head.count)) == golden.head)
        #expect(sha256Hex(string) == golden.sha256)
    }

    @Test func shapeOfATileString() throws {
        let tile = syntheticImage(width: 32, height: 32, seed: 3).pixels
        let s = Veil8Encoder(key: testKey)
        let a = s.serialize(rgba: tile), b = s.serialize(rgba: tile)
        #expect(a == b)
        #expect(s.charsPerPixel == 2)
        #expect(a.count == 3071 && a.count == s.characterCount(pixels: 1024))
        #expect(!a.hasPrefix(" ") && !a.hasSuffix(" ") && !a.contains("\n"))
        let words = a.split(separator: " ", omittingEmptySubsequences: false)
        #expect(words.count == 1024)
        #expect(words.allSatisfy { $0.count == 2 && $0.allSatisfy { Veil8Parameters.letters.contains($0) } })
    }

    /// A single row of pixels is encoded as a row: every pixel still gets a word.
    @Test func aNonSquareBufferIsOneRow() {
        let s = Veil8Encoder(key: testKey)
        let row = Array(syntheticImage(width: 6, height: 1, seed: 2).pixels)
        let words = s.serialize(rgba: row).split(separator: " ")
        #expect(words.count == 6)
        #expect(s.serialize(rgba: []) == "")
    }

    @Test func anotherKeyWritesAnotherString() {
        let tile = syntheticImage(width: 32, height: 32, seed: 5).pixels
        let other = Veil8Key(bytes: Array(1...32))!
        let a = Veil8Encoder(key: testKey).serialize(rgba: tile)
        let b = Veil8Encoder(key: other).serialize(rgba: tile)
        // Unrelated keys agree on a word about once in 256.
        #expect(sharedWords(a, b) < 0.05)
    }

    /// Different pixels, the same string: the string does not determine the tile.
    @Test func distinctTilesCollide() {
        let s = Veil8Encoder(key: testKey)
        let tile = syntheticImage(width: 32, height: 32, seed: 9).pixels
        let original = s.serialize(rgba: tile)
        var collisions = 0
        for pixel in stride(from: 0, to: 1024, by: 41) {
            var other = tile
            other[pixel * 4] = other[pixel * 4] == 255 ? 254 : other[pixel * 4] + 1
            if s.serialize(rgba: other) == original { collisions += 1 }
        }
        #expect(collisions > 0)
    }

    /// What matching needs: a tile that barely changed keeps most of its words, and an
    /// unrelated tile shares almost none.
    @Test func nearbyTilesShareWordsAndUnrelatedOnesDoNot() {
        let s = Veil8Encoder(key: testKey)
        let tile = syntheticImage(width: 32, height: 32, seed: 11).pixels
        var rng = SplitMix64(seed: 99)
        var noisy = tile
        for i in stride(from: 0, to: noisy.count, by: 4) {
            for c in 0..<3 {
                let delta = Int(rng.next() % 5) - 2
                noisy[i + c] = UInt8(min(255, max(0, Int(noisy[i + c]) + delta)))
            }
        }
        let unrelated = syntheticImage(width: 32, height: 32, seed: 12).pixels
        let base = s.serialize(rgba: tile)
        #expect(sharedWords(base, s.serialize(rgba: noisy)) > 0.5)
        #expect(sharedWords(base, s.serialize(rgba: unrelated)) < 0.05)
    }

    /// A word depends only on its pixel's window, so the same content four pixels over
    /// writes the same words wherever both windows are whole.
    @Test func wordsFollowTheContentUnderAShift() {
        let s = Veil8Encoder(key: testKey)
        let image = syntheticImage(width: 40, height: 40, seed: 13)
        let a = s.serialize(rgba: image.cropped(x: 0, y: 0, width: 32, height: 32).pixels).split(separator: " ")
        let b = s.serialize(rgba: image.cropped(x: 4, y: 4, width: 32, height: 32).pixels).split(separator: " ")
        for y in 2...25 {
            for x in 2...25 {
                #expect(b[y * 32 + x] == a[(y + 4) * 32 + (x + 4)])
            }
        }
    }

    /// Alpha is never read: an opaque and a transparent copy of a tile write the same string.
    @Test func alphaIsIgnored() {
        let s = Veil8Encoder(key: testKey)
        let tile = syntheticImage(width: 32, height: 32, seed: 17).pixels
        var faded = tile
        for i in stride(from: 3, to: faded.count, by: 4) { faded[i] = UInt8(i % 251) }
        #expect(s.serialize(rgba: tile) == s.serialize(rgba: faded))
    }

    @Test func parametersAreWhatTheIdNames() {
        #expect(Veil8Parameters.standard == Veil8Parameters(measurements: 8, radius: 2, step: 32, digits: "cdefhiklmnoprstw"))
        #expect(Veil8Parameters(digits: "aab").digits == Veil8Parameters.letters, "sixteen distinct characters or the default")
        #expect(Veil8Parameters(measurements: 5, radius: -1, step: 0) == Veil8Parameters(measurements: 8, radius: 0, step: 1))
        #expect(Veil8Encoder(key: testKey, parameters: Veil8Parameters(measurements: 12)).charsPerPixel == 3)
        #expect(Veil8Encoder.binomialRow(5) == [1, 4, 6, 4, 1])
        #expect(Veil8Encoder.isqrt(0) == 0 && Veil8Encoder.isqrt(15) == 3 && Veil8Encoder.isqrt(16) == 4)
        #expect(Veil8Encoder.floorDivide(-1, 4) == -1 && Veil8Encoder.floorDivide(-4, 4) == -1 && Veil8Encoder.floorDivide(7, 4) == 1)
        #expect(Veil8Format.contract == "veil.tiles.v1" && Veil8Format.encoding == "rgb-veil8" && Veil8Format.tileSize == 32)
    }
}
