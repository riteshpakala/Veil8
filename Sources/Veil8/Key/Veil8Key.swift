//
//  Veil8Key.swift
//  Veil8
//
//  The secret the encoder draws its measurement weights from: 32 bytes the application hands in.
//  Veil8 never makes a key, keeps one or sends one. The application does all three, and the
//  README says how ("The key"). Without the key a tile string means nothing; with a different
//  one, a query lands in another space and scores near zero against every stored tile. So the
//  key is a property of a corpus, like the encoding: its fingerprint is stored beside what was
//  written with it and compared before a query is encoded.
//
//  Only the fingerprint is ever shown, eight hex digits of HMAC-SHA256(key, "veil.key.fingerprint");
//  the bytes are not public, and `description` prints the fingerprint. Everything derived from the
//  key goes through one construction, the key stream: block n of the stream for a label is
//  HMAC-SHA256(key, label ‖ n as 4 big-endian bytes), bytes taken in order.
//

import CryptoKit
import Foundation

public struct Veil8Key: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    public static let byteCount = 32
    /// What the fingerprint is keyed under: the label Veil's corpora have named their key by since 2026-10.
    static let fingerprintLabel = "veil.key.fingerprint"

    let bytes: [UInt8]

    /// Nil unless exactly `byteCount` bytes. The application makes them, from a cryptographically
    /// secure random source, and keeps them (README, "The key").
    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    /// 64 hex digits, either case, surrounding whitespace ignored: a key as it is written down
    /// (SPEC.md, "The key"), such as a key file's 64 digits and newline.
    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count == Self.byteCount * 2, let bytes = Hex.bytes(trimmed) else { return nil }
        self.bytes = bytes
    }

    /// Eight hex digits that name the key without revealing it: the first four bytes of
    /// `HMAC-SHA256(key, "veil.key.fingerprint")`. What a corpus records as its `keyID`.
    public var fingerprint: String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(Self.fingerprintLabel.utf8), using: SymmetricKey(data: bytes))
        return Hex.string(Array(mac.prefix(4)))
    }

    /// Never the key.
    public var description: String { "Veil8Key(\(fingerprint))" }

    /// What `dump` and a debugger's `po` see: the fingerprint, never the bytes.
    public var customMirror: Mirror { Mirror(self, children: ["fingerprint": fingerprint]) }

    // MARK: - The key stream

    /// A deterministic byte stream for one purpose. Block `n` is
    /// `HMAC-SHA256(key, label ‖ n as 4 big-endian bytes)`, `n` from 0; bytes are taken in order.
    public func stream(_ label: String) -> KeyStream { KeyStream(key: SymmetricKey(data: bytes), label: Array(label.utf8)) }

    public struct KeyStream: Sendable {
        private let key: SymmetricKey
        private let label: [UInt8]
        private var counter: UInt32 = 0
        private var block: [UInt8] = []
        private var offset = 0

        init(key: SymmetricKey, label: [UInt8]) {
            self.key = key
            self.label = label
        }

        public mutating func nextByte() -> UInt8 {
            if offset == block.count {
                let n = counter
                let message = label + [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
                block = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
                counter &+= 1
                offset = 0
            }
            defer { offset += 1 }
            return block[offset]
        }

        /// Eight bytes, big-endian.
        public mutating func nextUInt64() -> UInt64 {
            (0..<8).reduce(UInt64(0)) { value, _ in (value << 8) | UInt64(nextByte()) }
        }
    }
}

/// Lowercase hex, both ways.
enum Hex {
    private static let digits = Array("0123456789abcdef".utf8)

    static func string(_ bytes: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Nil unless an even, non-empty run of hex digits (either case).
    static func bytes(_ hex: String) -> [UInt8]? {
        let characters = Array(hex.utf8)
        guard !characters.isEmpty, characters.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = nibble(characters[index]), let low = nibble(characters[index + 1]) else { return nil }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48
        case 97...102: return c - 87
        case 65...70: return c - 55
        default: return nil
        }
    }
}
