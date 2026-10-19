//
//  Veil8Key+File.swift
//  Veil8
//
//  The key on disk: one file, 64 hex digits and a newline, mode 0600 in a 0700 directory. It is
//  made once and never overwritten — two processes racing to create it end up with the same one —
//  and never thrown away: regenerating moves the current key aside as `<stem>-<fingerprint>.key`
//  (`device-<fingerprint>.key` beside `device.key`) before the new one is written, and any kept
//  key can be made current again, the only way back to a corpus written with it.
//
//  Where the file lives is the application's business (Veil keeps it with the Rao device key,
//  ~/.rao/keys/device.key); every function here takes the URL.
//

import Foundation

public enum Veil8KeyError: Error, Equatable, LocalizedError, CustomStringConvertible {
    /// The file exists and is not 64 hex digits. It is never replaced: that would orphan
    /// whatever was written with the real key.
    case notAKey(String)
    case unreadable(String)
    case notOwned(String)
    case notADirectory(String)
    case io(String, String)

    public var description: String {
        switch self {
        case .notAKey(let path): return "\(path) is not a key (expected \(Veil8Key.byteCount * 2) hex digits)"
        case .unreadable(let path): return "could not read the key at \(path)"
        case .notOwned(let path): return "\(path) belongs to another user"
        case .notADirectory(let path): return "\(path) is not a directory"
        case .io(let path, let reason): return "\(path): \(reason)"
        }
    }

    /// The same words for `localizedDescription`.
    public var errorDescription: String? { description }
}

extension Veil8Key {
    /// The key at `url`, or nil when there is no file. A file that is not a key throws:
    /// replacing it silently would orphan whatever was written with the real one.
    public static func load(from url: URL) throws -> Veil8Key? {
        guard PrivateFile.exists(url) else { return nil }
        guard let data = FileManager.default.contents(atPath: PrivateFile.path(url)) else {
            throw Veil8KeyError.unreadable(PrivateFile.path(url))
        }
        guard let key = Veil8Key(hex: String(decoding: data, as: UTF8.self)) else {
            throw Veil8KeyError.notAKey(PrivateFile.path(url))
        }
        return key
    }

    /// The key at `url`, made when absent. Never overwrites: two processes racing to create it
    /// end up with the same one.
    public static func loadOrCreate(at url: URL) throws -> (key: Veil8Key, created: Bool) {
        if let existing = try load(from: url) { return (existing, false) }
        try PrivateFile.ensureDirectory(url.deletingLastPathComponent())
        let fresh = Veil8Key.random()
        let published = try PrivateFile.publishIfAbsent(Data((fresh.hex + "\n").utf8), to: url, mode: 0o600)
        if published { return (fresh, true) }
        guard let winner = try load(from: url) else { throw Veil8KeyError.unreadable(PrivateFile.path(url)) }
        return (winner, false)
    }

    // MARK: - Regenerating, and switching back

    /// A key kept beside the current one: an earlier key a corpus may still be written with.
    public struct KeptKey: Sendable, Equatable, Identifiable {
        public let key: Veil8Key
        public let file: URL
        public var fingerprint: String { key.fingerprint }
        public var id: String { PrivateFile.path(file) }

        public init(key: Veil8Key, file: URL) {
            self.key = key
            self.file = file
        }
    }

    /// The name a key is kept under beside `url`: `<stem>-<fingerprint>.key`, so the key kept
    /// beside `device.key` is `device-<fingerprint>.key`.
    static func keptName(_ key: Veil8Key, beside url: URL) -> String {
        "\(stem(url))-\(key.fingerprint).key"
    }

    /// `device` for `device.key`; the whole name when there is no extension.
    static func stem(_ url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? url.lastPathComponent : stem
    }

    /// The keys kept beside `url` (`<stem>-*.key`), most recently written first. Files that are
    /// not keys are left out.
    public static func kept(beside url: URL) -> [KeptKey] {
        let directory = url.deletingLastPathComponent()
        let prefix = stem(url) + "-"
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let kept = files.compactMap { file -> (KeptKey, Date)? in
            let name = file.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".key"), let key = try? load(from: file) else { return nil }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (KeptKey(key: key, file: file), date)
        }
        return kept.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// A new key at `url`. The current one, when there is one, is kept beside it first.
    /// - Returns: the new key, and where the previous one now is.
    @discardableResult
    public static func regenerate(at url: URL) throws -> (key: Veil8Key, kept: URL?) {
        let keptFile = try keepCurrent(at: url)
        let (key, _) = try loadOrCreate(at: url)
        return (key, keptFile)
    }

    /// Makes a kept key the current one again; the current one is kept in its place.
    @discardableResult
    public static func use(_ keptFile: URL, at url: URL) throws -> Veil8Key {
        guard let chosen = try load(from: keptFile) else {
            throw Veil8KeyError.unreadable(PrivateFile.path(keptFile))
        }
        if let current = try load(from: url), current == chosen { return chosen }
        _ = try keepCurrent(at: url)
        try FileManager.default.moveItem(at: keptFile, to: url)
        return chosen
    }

    /// Moves the key at `url` aside as `<stem>-<fingerprint>.key`; nil when there is none. A file
    /// that is not a key is an error rather than something to move.
    static func keepCurrent(at url: URL) throws -> URL? {
        guard let current = try load(from: url) else { return nil }
        let keptFile = url.deletingLastPathComponent().appendingPathComponent(keptName(current, beside: url))
        if let already = try? load(from: keptFile), already == current {
            // Kept before, under the same name: the copy here is the same key.
            try FileManager.default.removeItem(at: url)
        } else {
            try FileManager.default.moveItem(at: url, to: keptFile)
        }
        return keptFile
    }
}
