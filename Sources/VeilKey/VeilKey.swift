//
//  VeilKey.swift
//  VeilKey
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  The key an application keeps for Veil8: 32 random bytes in a file it can make, read, replace and
//  switch back to. Veil8's encoder only takes a key (`Veil8Key`); this library makes one and keeps
//  it, the way Veil keeps its own: one file, 64 hex digits and a newline, mode 0600, made once,
//  never overwritten and never thrown away (VeilKey+File.swift). `veil8` is the key as the encoder
//  takes it: `Veil8Encoder(key: key.veil8)`.
//
//  Only the fingerprint is ever shown: `description` and `dump` print it, and the bytes leave this
//  type only as the file it writes.
//

import Foundation
import Veil8

public struct VeilKey: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    public static let byteCount = Veil8Key.byteCount

    /// The key as Veil8's encoder takes it.
    public let veil8: Veil8Key
    /// The same 32 bytes as the file spells them, 64 lowercase hex digits: VeilKey is the one place
    /// a key is written down, and `Veil8Key` shows nothing but its fingerprint.
    let hex: String

    private init(_ key: Veil8Key, hex: String) {
        self.veil8 = key
        self.hex = hex
    }

    /// Nil unless exactly `byteCount` bytes.
    public init?(bytes: [UInt8]) {
        guard let key = Veil8Key(bytes: bytes) else { return nil }
        self.init(key, hex: bytes.map { String(format: "%02x", $0) }.joined())
    }

    /// 64 hex digits, either case, surrounding whitespace ignored: a key file's contents.
    public init?(hex: String) {
        guard let key = Veil8Key(hex: hex) else { return nil }
        self.init(key, hex: hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// A fresh key from the system's secure random source (arc4random_buf on Apple platforms,
    /// getrandom on Linux). A key derived from a password, a device id or anything else that can be
    /// guessed protects nothing: the key is the only secret in the encoding.
    public static func random() -> VeilKey {
        var generator = SystemRandomNumberGenerator()
        return VeilKey(bytes: (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })!
    }

    /// Eight hex digits that name the key without revealing it (Veil8Key's): what a corpus records
    /// beside what was written with the key, and what a mismatch names.
    public var fingerprint: String { veil8.fingerprint }

    /// Never the key.
    public var description: String { "VeilKey(\(fingerprint))" }

    /// What `dump` and a debugger's `po` see: the fingerprint, never the bytes.
    public var customMirror: Mirror { Mirror(self, children: ["fingerprint": fingerprint]) }
}
