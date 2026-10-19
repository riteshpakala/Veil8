import Foundation
import Testing
@testable import Veil8

/// A reversible serializer for the tests: each pixel's RGB as six hex digits.
struct HexTestSerializer: TileSerializer {
    let charsPerPixel = 6

    func serialize(rgba: UnsafeBufferPointer<UInt8>) -> String {
        stride(from: 0, to: rgba.count, by: 4).map { String(format: "%02x%02x%02x", rgba[$0], rgba[$0 + 1], rgba[$0 + 2]) }.joined(separator: " ")
    }
}

@Suite struct FrameTests {
    /// A frame serializes many tiles across the cores; the strings must be exactly what one tile
    /// at a time writes, in the order asked for.
    @Test func aFrameSerializesInParallelExactlyAsOneByOne() {
        let frame = VeilFrame.make(image: syntheticImage(width: 256, height: 192, seed: 17))
        let order = Array((0..<frame.tileCount).reversed()) + [3, 3, 0]
        #expect(order.count >= 16)
        for serializer in [HexTestSerializer() as any TileSerializer, Veil8Encoder(key: testKey)] {
            let together = frame.serialize(serializer, tiles: order)
            let oneByOne = order.map { frame.serialize(serializer, tiles: [$0])[0] }
            #expect(together == oneByOne)
            #expect(together.allSatisfy { $0.count == serializer.characterCount(pixels: 1024) })
        }
    }

    /// By default a frame writes its active tiles: flat ones are left out.
    @Test func onlyActiveTilesAreWritten() {
        var image = syntheticImage(width: 64, height: 32, seed: 6)
        for y in 0..<32 {
            for x in 32..<64 {
                let i = (y * 64 + x) * 4
                image.pixels[i] = 40; image.pixels[i + 1] = 80; image.pixels[i + 2] = 120
            }
        }
        let frame = VeilFrame.make(image: image)
        #expect(frame.flat == [false, true] && frame.activeTiles == [0])
        let encoder = Veil8Encoder(key: testKey)
        #expect(frame.serialize(encoder) == [encoder.serialize(rgba: frame.tileSlice(0))])
    }

    /// The whole process from a file: encode a picture, load it back, normalize, tile, write.
    @Test func aPictureBecomesStrings() throws {
        let picture = syntheticImage(width: 70, height: 45, seed: 21)
        let png = try #require(ImageLoader.pngData(picture))
        let loaded = try ImageLoader.load(data: png)
        #expect(loaded == picture, "PNG is lossless and the loader draws opaque pixels unchanged")
        let frame = VeilFrame.make(normalized: ImageNormalizer.normalize(loaded))
        #expect(frame.grid == TileGrid(width: 96, height: 64, tileSize: 32))
        let strings = frame.serialize(Veil8Encoder(key: testKey))
        #expect(strings.count == frame.activeTiles.count && strings.count == 6)
        #expect(strings.allSatisfy { $0.count == 3071 })
        #expect(throws: ImageLoader.LoadError.self) { try ImageLoader.load(data: Data("not a picture".utf8)) }
    }
}
