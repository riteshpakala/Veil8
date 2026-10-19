//
//  PrivateFile.swift
//  VeilKey
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  The few filesystem moves a key file needs to be safe with more than one process touching it:
//  a private directory, and publishing a file only if nothing is there yet. Every write lands in
//  a temporary file beside its target and is linked into place, so a reader never sees a torn or
//  empty key, and two processes racing to create one end up holding the same key. Ported from
//  AII's PrivateFile (the Ambient Intelligence Index), which writes the Rao device key the same way.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum PrivateFile {
    /// The path a syscall wants: no percent-encoding (a space stays a space), no trailing slash.
    static func path(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Owner uid, permission bits and kind, or nil when nothing is there. A symlink is reported
    /// as itself (lstat), never as what it points at, so nothing is created over a dangling one.
    static func ownerAndMode(_ url: URL) -> (uid: uid_t, mode: UInt16, isDirectory: Bool)? {
        var info = stat()
        guard lstat(path(url), &info) == 0 else { return nil }
        return (info.st_uid, UInt16(info.st_mode & 0o7777), info.st_mode & S_IFMT == S_IFDIR)
    }

    static func exists(_ url: URL) -> Bool { ownerAndMode(url) != nil }

    /// `mkdir -p` with `mode` for every directory it creates. An existing directory of this
    /// user's that is more open than `mode` is tightened; one owned by someone else is refused.
    static func ensureDirectory(_ url: URL, mode: mode_t = 0o700) throws {
        let target = url.standardizedFileURL
        if let found = ownerAndMode(target) {
            guard found.isDirectory else { throw VeilKeyError.notADirectory(path(target)) }
            guard found.uid == geteuid() else { throw VeilKeyError.notOwned(path(target)) }
            if found.mode & ~UInt16(mode) & 0o777 != 0 {
                guard chmod(path(target), mode) == 0 else {
                    throw VeilKeyError.io(path(target), "chmod: \(errnoText())")
                }
            }
            return
        }
        let parent = target.deletingLastPathComponent()
        if parent.path(percentEncoded: false) != target.path(percentEncoded: false), !exists(parent) {
            try ensureDirectory(parent, mode: mode)
        }
        if mkdir(path(target), mode) != 0 && errno != EEXIST {
            throw VeilKeyError.io(path(target), "mkdir: \(errnoText())")
        }
        // mkdir honours the umask; make the mode exact.
        _ = chmod(path(target), mode)
    }

    /// Publishes `data` at `url` only if nothing is there yet: the whole contents go to a
    /// temporary file first (O_EXCL, fsync, `mode`) and are hard-linked into place, so a reader
    /// never sees an empty or partial file and two racing writers cannot both win. Returns false
    /// when `url` already existed.
    @discardableResult
    static func publishIfAbsent(_ data: Data, to url: URL, mode: mode_t = 0o600) throws -> Bool {
        let temp = try writeTemporary(data, beside: url, mode: mode)
        defer { unlink(path(temp)) }
        if link(path(temp), path(url)) == 0 { return true }
        if errno == EEXIST { return false }
        throw VeilKeyError.io(path(url), "link: \(errnoText())")
    }

    private static func writeTemporary(_ data: Data, beside url: URL, mode: mode_t) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(getpid()).\(UInt32.random(in: .min ... .max)).tmp")
        let fd = open(path(temp), O_WRONLY | O_CREAT | O_EXCL, mode)
        guard fd >= 0 else { throw VeilKeyError.io(path(temp), "open: \(errnoText())") }
        var failure: String?
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, base.advanced(by: offset), buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = "write: \(errnoText())"
                    return
                }
                offset += written
            }
        }
        if failure == nil, fsync(fd) != 0 { failure = "fsync: \(errnoText())" }
        _ = fchmod(fd, mode)
        close(fd)
        if let failure {
            unlink(path(temp))
            throw VeilKeyError.io(path(temp), failure)
        }
        return temp
    }

    static func errnoText() -> String { String(cString: strerror(errno)) }
}
