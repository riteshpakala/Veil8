import Foundation
import Testing
@testable import Veil8

/// What Veil8 does with a key it is handed. Making and keeping one is the application's (README,
/// "The key"); Veil tests its own in VeilKitTests.
@Suite struct Veil8KeyTests {
    @Test func aKeyIsThirtyTwoBytes() {
        #expect(Veil8Key(bytes: []) == nil && Veil8Key(bytes: Array(0..<31)) == nil && Veil8Key(bytes: Array(0..<33)) == nil)
        #expect(Veil8Key(hex: "zz") == nil && Veil8Key(hex: String(repeating: "g", count: 64)) == nil)
        #expect(Veil8Key(hex: String(testKeyHex.dropLast(2))) == nil, "62 digits are not a key")
        #expect(Veil8Key(hex: testKeyHex.uppercased()) == testKey, "either case")
        #expect(Veil8Key(bytes: Array(1...32)) != testKey)
    }

    /// A key file as Veil (through AII) writes it, 64 hex digits and a newline, is the same key.
    @Test func aWrittenKeyReadsBack() {
        #expect(Veil8Key(hex: testKeyHex + "\n") == testKey)
        #expect(Veil8Key(hex: "  " + testKeyHex + "\r\n") == testKey, "surrounding whitespace is ignored")
    }

    @Test func theFingerprintNamesTheKeyWithoutRevealingIt() {
        #expect(testKey.fingerprint == "857472e4")
        #expect(testKey.fingerprint != Veil8Key(bytes: Array(1...32))!.fingerprint)
        #expect("\(testKey)" == "Veil8Key(857472e4)")
        #expect(!"\(testKey)".contains(testKeyHex) && !String(reflecting: testKey).contains(testKeyHex))
        var dumped = ""
        dump(testKey, to: &dumped)
        #expect(dumped.contains("857472e4") && !dumped.contains("bytes"), "a dump shows the fingerprint, not the bytes")
    }

    /// The key stream as SPEC.md defines it: block n = HMAC-SHA256(key, label ‖ n), bytes in order.
    @Test func theStreamIsCounterModeHMAC() {
        var stream = testKey.stream("veil8.test")
        let first = (0..<40).map { _ in stream.nextByte() }
        var again = testKey.stream("veil8.test")
        #expect((0..<40).map { _ in again.nextByte() } == first, "deterministic")
        var other = testKey.stream("veil8.other")
        #expect((0..<40).map { _ in other.nextByte() } != first, "a label is a different stream")
        #expect(Set(first).count > 1)
        var wide = testKey.stream("veil8.test")
        let word = wide.nextUInt64()
        #expect(word == first[0..<8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }, "big-endian")
    }
}
