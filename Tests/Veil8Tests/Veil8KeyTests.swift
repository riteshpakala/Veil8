import Foundation
import Testing
@testable import Veil8

@Suite struct Veil8KeyTests {
    @Test func aKeyIsThirtyTwoBytes() {
        #expect(Veil8Key(bytes: []) == nil && Veil8Key(bytes: Array(0..<31)) == nil)
        #expect(Veil8Key(hex: "zz") == nil && Veil8Key(hex: String(repeating: "g", count: 64)) == nil)
        #expect(Veil8Key(hex: testKeyHex + "\n") == testKey)
        #expect(Veil8Key(hex: testKeyHex.uppercased()) == testKey, "either case")
        #expect(Veil8Key.random() != Veil8Key.random())
    }

    @Test func theFingerprintNamesTheKeyWithoutRevealingIt() {
        #expect(testKey.fingerprint == "857472e4")
        #expect(testKey.fingerprint != Veil8Key(bytes: Array(1...32))!.fingerprint)
        #expect("\(testKey)" == "Veil8Key(857472e4)")
        #expect(!"\(testKey)".contains(testKeyHex))
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

    @Test func createdOncePrivateAndNeverReplaced() throws {
        let file = try scratchDirectory("key").appendingPathComponent("nested/veil8.key")
        #expect(try Veil8Key.load(from: file) == nil)
        let first = try Veil8Key.loadOrCreate(at: file)
        #expect(first.created)
        let mode = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        #expect(mode.intValue & 0o777 == 0o600)
        let dirMode = try #require(FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)
        #expect(dirMode.intValue & 0o777 == 0o700)
        let second = try Veil8Key.loadOrCreate(at: file)
        #expect(!second.created && second.key == first.key)
        #expect(try Veil8Key.load(from: file) == first.key)
        // The file is the key's 64 hex digits and a newline, as every other writer spells it.
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.count == 65 && text.hasSuffix("\n") && Veil8Key(hex: text) == first.key)
    }

    /// A file another implementation wrote — AII's device key, say — loads and fingerprints the same.
    @Test func aFileAnotherWriterMadeLoads() throws {
        let file = try scratchDirectory("key").appendingPathComponent("device.key")
        try Data((testKeyHex + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let key = try #require(try Veil8Key.load(from: file))
        #expect(key == testKey && key.fingerprint == "857472e4")
    }

    /// Regenerating never throws a key away: the old one is kept beside the new one, still
    /// private, and either can be made current again.
    @Test func regeneratingKeepsTheOldKeyAndCanSwitchBack() throws {
        let file = try scratchDirectory("key").appendingPathComponent("veil8.key")
        func current() throws -> Veil8Key? { try Veil8Key.load(from: file) }
        func kept() -> Set<String> { Set(Veil8Key.kept(beside: file).map(\.fingerprint)) }
        let first = try Veil8Key.loadOrCreate(at: file).key
        #expect(kept().isEmpty)

        let (second, keptFile) = try Veil8Key.regenerate(at: file)
        let afterRegenerate = try current()
        #expect(second != first && afterRegenerate == second)
        let firstFile = try #require(keptFile)
        #expect(firstFile.lastPathComponent == "veil8-\(first.fingerprint).key", "kept under the file's stem and its fingerprint")
        let mode = try #require(FileManager.default.attributesOfItem(atPath: firstFile.path)[.posixPermissions] as? NSNumber)
        #expect(mode.intValue & 0o777 == 0o600, "a kept key stays private")
        #expect(kept() == [first.fingerprint])

        let third = try Veil8Key.regenerate(at: file).key
        #expect(kept() == [first.fingerprint, second.fingerprint])

        // Back to the first: it becomes current, and the one it replaced is kept in its place.
        let restored = try Veil8Key.use(firstFile, at: file)
        let afterUse = try current()
        #expect(restored == first && afterUse == first)
        #expect(kept() == [second.fingerprint, third.fingerprint])
        // Choosing the key that is already current changes nothing.
        let secondFile = try #require(Veil8Key.kept(beside: file).first { $0.key == second }).file
        try Veil8Key.use(secondFile, at: file)
        try Veil8Key.use(file, at: file)
        let afterNoOp = try current()
        #expect(afterNoOp == second)
        #expect(kept() == [first.fingerprint, third.fingerprint])
    }

    /// The device key keeps the name every Rao app knows: `device-<fingerprint>.key` beside `device.key`.
    @Test func theDeviceKeyIsKeptUnderItsOldName() throws {
        let file = try scratchDirectory("key").appendingPathComponent("device.key")
        let first = try Veil8Key.loadOrCreate(at: file).key
        let (_, keptFile) = try Veil8Key.regenerate(at: file)
        #expect(try #require(keptFile).lastPathComponent == "device-\(first.fingerprint).key")
        #expect(Veil8Key.kept(beside: file).map(\.fingerprint) == [first.fingerprint])
        #expect(Veil8Key.kept(beside: file).first?.file.lastPathComponent == keptFile?.lastPathComponent)
    }

    @Test func regeneratingWithoutAKeyMakesOne() throws {
        let file = try scratchDirectory("key").appendingPathComponent("veil8.key")
        let (key, kept) = try Veil8Key.regenerate(at: file)
        let stored = try Veil8Key.load(from: file)
        #expect(kept == nil && stored == key)
    }

    @Test func aFileThatIsNotAKeyIsAnErrorNotAReplacement() throws {
        let file = try scratchDirectory("key").appendingPathComponent("veil8.key")
        try Data("not a key\n".utf8).write(to: file)
        #expect(throws: Veil8KeyError.notAKey(file.path)) { try Veil8Key.load(from: file) }
        #expect(throws: Veil8KeyError.self) { try Veil8Key.loadOrCreate(at: file) }
        #expect(throws: Veil8KeyError.self) { try Veil8Key.regenerate(at: file) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "not a key\n")
        let error = Veil8KeyError.notAKey(file.path)
        #expect(error.localizedDescription == error.description && error.description.contains("64 hex digits"))
    }
}
