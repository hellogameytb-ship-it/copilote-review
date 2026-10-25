import Foundation
import Darwin

/// Atomic local Markdown export. The final path is never followed through a symbolic link.
public enum MarkdownFileExport {
    public struct Revision: Equatable, Sendable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modified: timespec
        let changed: timespec
        public static func == (a: Self, b: Self) -> Bool {
            a.device == b.device && a.inode == b.inode && a.size == b.size &&
            a.modified.tv_sec == b.modified.tv_sec && a.modified.tv_nsec == b.modified.tv_nsec &&
            a.changed.tv_sec == b.changed.tv_sec && a.changed.tv_nsec == b.changed.tv_nsec
        }
    }
    public enum Failure: LocalizedError {
        case invalidName, unsupportedTarget, changed
        public var errorDescription: String? {
            switch self {
            case .invalidName: return "Enter a simple Markdown filename, without slashes, control characters or a relative path."
            case .unsupportedTarget: return "Choose a regular file destination. Folders and symbolic links cannot be replaced."
            case .changed: return "The destination changed. Review it and confirm replacement again."
            }
        }
    }
    public static func filename(_ proposed: String) throws -> String {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Failure.invalidName }
        return name.lowercased().hasSuffix(".md") ? name : name + ".md"
    }
    public static func suggestedName(_ name: String) -> String {
        let clean = name.components(separatedBy: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))).joined(separator: "-")
        return (try? filename(clean)) ?? "Session.md"
    }
    public static func revision(at url: URL) throws -> Revision? {
        var value = stat()
        if lstat(url.path, &value) != 0 {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        return try revision(value)
    }
    private static func revision(_ value: stat) throws -> Revision {
        guard value.st_mode & S_IFMT == S_IFREG else { throw Failure.unsupportedTarget }
        return Revision(device: value.st_dev, inode: value.st_ino, size: value.st_size, modified: value.st_mtimespec, changed: value.st_ctimespec)
    }
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }

    /// New destinations use an exclusive link, so a concurrently created file is never replaced.
    /// Confirmed replacement checks identity/metadata again, then atomically renames within the same directory.
    public static func write(_ text: String, directory: URL, name: String, replacing expected: Revision?) throws {
        let name = try filename(name)
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dir >= 0 else { throw posixError() }
        defer { close(dir) }
        func current() throws -> Revision? {
            var value = stat()
            if fstatat(dir, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno == ENOENT { return nil }
                throw posixError()
            }
            return try revision(value)
        }
        guard try current() == expected else { throw Failure.changed }
        let temporary = ".copilote-export-" + UUID().uuidString
        let fd = openat(dir, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }
        defer { close(fd); unlinkat(dir, temporary, 0) }
        let data = Data(text.utf8)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw posixError() }
                guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw posixError() }
        guard try current() == expected else { throw Failure.changed }
        if expected == nil {
            guard linkat(dir, temporary, dir, name, 0) == 0 else { throw posixError() }
        } else {
            guard renameat(dir, temporary, dir, name) == 0 else { throw posixError() }
        }
    }
}

/// Location memory for this non-sandboxed app; it does not grant new file access.
public enum FileBrowserBookmark {
    public static func create(_ url: URL) throws -> Data { try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
    public static func resolve(_ data: Data) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}
