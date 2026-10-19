//
//  VeilKeyTests.swift
//  VeilKeyTests
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//

import Foundation
import Testing
import Veil8
@testable import VeilKey

/// A key as a value: what it is made of, what it shows, what it hands the encoder.
@Suite struct KeyTests {
    @Test func aKeyIsThirtyTwoBytes() {
        #expect(VeilKey(bytes: []) == nil && VeilKey(bytes: Array(0..<31)) == nil && VeilKey(bytes: Array(0..<33)) == nil)
        #expect(VeilKey(hex: "zz") == nil && VeilKey(hex: String(repeating: "g", count: 64)) == nil)
        #expect(VeilKey(hex: testKeyHex + "\n") == testKey)
        #expect(VeilKey(hex: testKeyHex.uppercased()) == testKey, "either case")
        #expect(testKey.hex == testKeyHex, "written down in lowercase")
    }

    @Test func randomKeysAreFreshAndWhole() {
        let a = VeilKey.random(), b = VeilKey.random()
        #expect(a != b && a.fingerprint != b.fingerprint)
        #expect(a.hex.count == 64 && VeilKey(hex: a.hex) == a)
    }

    @Test func theFingerprintNamesTheKeyWithoutRevealingIt() {
        #expect(testKey.fingerprint == "857472e4" && testKey.fingerprint == testKey.veil8.fingerprint)
        #expect("\(testKey)" == "VeilKey(857472e4)" && !"\(testKey)".contains(testKeyHex))
        var dumped = ""
        dump(testKey, to: &dumped)
        #expect(dumped.contains("857472e4") && !dumped.contains(testKeyHex) && !dumped.contains("hex"))
    }

    /// What the encoder takes is the same 32 bytes: Veil8's own key for bytes 0…31.
    @Test func theEncoderTakesTheSameKey() {
        #expect(testKey.veil8 == Veil8Key(bytes: Array(0..<32)))
        let tile = fixtureTile()
        #expect(Veil8Encoder(key: testKey.veil8).serialize(rgba: tile) == Veil8Encoder(key: Veil8Key(hex: testKeyHex)!).serialize(rgba: tile))
    }
}

/// A key as a file: made once, private, never replaced, never thrown away.
@Suite struct KeyFileTests {
    @Test func createdOncePrivateAndNeverReplaced() throws {
        let file = try scratchDirectory("file").appendingPathComponent("nested/my.key")
        #expect(try VeilKey.load(from: file) == nil)
        let first = try VeilKey.loadOrCreate(at: file)
        #expect(first.created)
        #expect(try mode(file) == 0o600 && mode(file.deletingLastPathComponent()) == 0o700)
        let second = try VeilKey.loadOrCreate(at: file)
        #expect(!second.created && second.key == first.key)
        #expect(try VeilKey.load(from: file) == first.key)
        // The file is the key's 64 hex digits and a newline, and Veil8 reads it as the same key.
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text == first.key.hex + "\n" && Veil8Key(hex: text) == first.key.veil8)
    }

    /// A file another writer made (AII's device key, another implementation) loads and fingerprints the same.
    @Test func aFileAnotherWriterMadeLoads() throws {
        let file = try scratchDirectory("file").appendingPathComponent("device.key")
        try Data((testKeyHex + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let key = try #require(try VeilKey.load(from: file))
        #expect(key == testKey && key.fingerprint == "857472e4")
    }

    /// Regenerating never throws a key away: the old one is kept beside the new one, still private,
    /// and either can be made current again.
    @Test func regeneratingKeepsTheOldKeyAndCanSwitchBack() throws {
        let file = try scratchDirectory("file").appendingPathComponent("my.key")
        func current() throws -> VeilKey? { try VeilKey.load(from: file) }
        func kept() -> Set<String> { Set(VeilKey.kept(beside: file).map(\.fingerprint)) }
        let first = try VeilKey.loadOrCreate(at: file).key
        #expect(kept().isEmpty)

        let (second, keptFile) = try VeilKey.regenerate(at: file)
        let afterRegenerate = try current()
        #expect(second != first && afterRegenerate == second)
        let firstFile = try #require(keptFile)
        #expect(firstFile.lastPathComponent == "my-\(first.fingerprint).key", "kept under the file's stem and its fingerprint")
        #expect(try mode(firstFile) == 0o600, "a kept key stays private")
        #expect(kept() == [first.fingerprint])

        let third = try VeilKey.regenerate(at: file).key
        #expect(kept() == [first.fingerprint, second.fingerprint])

        // Back to the first: it becomes current, and the one it replaced is kept in its place.
        let restored = try VeilKey.use(firstFile, at: file)
        let afterUse = try current()
        #expect(restored == first && afterUse == first)
        #expect(kept() == [second.fingerprint, third.fingerprint])
        // Choosing the key that is already current changes nothing.
        let secondFile = try #require(VeilKey.kept(beside: file).first { $0.key == second }).file
        try VeilKey.use(secondFile, at: file)
        try VeilKey.use(file, at: file)
        let afterNoOp = try current()
        #expect(afterNoOp == second)
        #expect(kept() == [first.fingerprint, third.fingerprint])
    }

    /// The device key keeps the name every Rao app knows: `device-<fingerprint>.key` beside `device.key`.
    @Test func theDeviceKeyIsKeptUnderItsOldName() throws {
        let file = try scratchDirectory("file").appendingPathComponent("device.key")
        let first = try VeilKey.loadOrCreate(at: file).key
        let (_, keptFile) = try VeilKey.regenerate(at: file)
        #expect(try #require(keptFile).lastPathComponent == "device-\(first.fingerprint).key")
        #expect(VeilKey.kept(beside: file).map(\.fingerprint) == [first.fingerprint])
    }

    @Test func regeneratingWithoutAKeyMakesOne() throws {
        let file = try scratchDirectory("file").appendingPathComponent("my.key")
        let (key, kept) = try VeilKey.regenerate(at: file)
        let stored = try VeilKey.load(from: file)
        #expect(kept == nil && stored == key)
    }

    @Test func aFileThatIsNotAKeyIsAnErrorNotAReplacement() throws {
        let file = try scratchDirectory("file").appendingPathComponent("my.key")
        try Data("not a key\n".utf8).write(to: file)
        #expect(throws: VeilKeyError.notAKey(file.path)) { try VeilKey.load(from: file) }
        #expect(throws: VeilKeyError.self) { try VeilKey.loadOrCreate(at: file) }
        #expect(throws: VeilKeyError.self) { try VeilKey.regenerate(at: file) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "not a key\n")
        let error = VeilKeyError.notAKey(file.path)
        #expect(error.localizedDescription == error.description && error.description.contains("64 hex digits"))
    }

    /// The README's guide, end to end: a key file made once, then the encoder made from it.
    @Test func theGuideWorks() throws {
        let keyFile = try scratchDirectory("guide").appendingPathComponent("my.key")
        let (key, created) = try VeilKey.loadOrCreate(at: keyFile)
        let encoder = Veil8Encoder(key: key.veil8)
        let again = try VeilKey.loadOrCreate(at: keyFile)
        #expect(created && !again.created && key.fingerprint.count == 8)
        #expect(encoder.serialize(rgba: fixtureTile()) == Veil8Encoder(key: again.key.veil8).serialize(rgba: fixtureTile()))
    }
}
