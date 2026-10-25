import CryptoKit
import Foundation

/// Where the base is: `~/Copilote/` and the photo folders added in Réglages → Base.
public struct BaseSource: Sendable {
    public let root: URL
    public let photoFolders: [URL]
    public var isVault: Bool { VaultPolicy.isVault(root) }

    public init(root: URL, photoFolders: [URL] = []) {
        self.root = root.standardizedFileURL
        self.photoFolders = photoFolders.map(\.standardizedFileURL)
    }
}

/// Place name for a GPS position (reverse geocoding: a network call, at indexing only; cached).
public protocol PlaceNamer: Sendable {
    /// nil: no place there (the sea). Throws when the lookup itself failed (offline, throttled).
    func name(for coordinate: Coordinate) async throws -> String?
}

/// On-device labels for a photo ("plage", "montagne"…).
public protocol PhotoLabeler: Sendable {
    func labels(for url: URL) -> [String]
}

/// Optional caption of a photo by the LLM (off by default, offline batch).
public protocol PhotoCaptioner: Sendable {
    func caption(for url: URL) async throws -> String
}

/// The architecture diagram of a repo, made once per repo state (LLM + validation + render).
public protocol DiagramMaker: Sendable {
    /// nil: the LLM's answer was not a valid diagram. Throws when the call itself failed.
    func diagram(project: String, snapshot: RepoSnapshot, into folder: URL) async throws -> (mermaid: String, image: URL)?
}

public struct IndexReport: Sendable {
    public var scannedFiles = 0
    public var changedFiles = 0
    public var removedFiles = 0
    public var items = 0
    public var photos = 0
    public var diagrams: [String: DiagramRecord.Status] = [:]
    public var problems: [String] = []
    public var elapsed: Duration = .zero
}

/// Reads the base folder into the index, incrementally: a file is read again only when its
/// size or modification date changed; files gone from the folder leave the index. Repos are
/// read only at the path a fiche gives, never searched for.
public actor BaseIndexer {
    private let index: BaseIndex
    private let embedder: TextEmbedder
    /// Thumbnails and diagram images.
    private let store: URL
    private let places: PlaceNamer?
    private let labeler: PhotoLabeler?
    private let captioner: PhotoCaptioner?
    private let diagrams: DiagramMaker?

    public init(
        index: BaseIndex, embedder: TextEmbedder, store: URL, places: PlaceNamer? = nil, labeler: PhotoLabeler? = nil,
        captioner: PhotoCaptioner? = nil, diagrams: DiagramMaker? = nil
    ) {
        self.index = index
        self.embedder = embedder
        self.store = store
        self.places = places
        self.labeler = labeler
        self.captioner = captioner
        self.diagrams = diagrams
    }

    public func run(_ source: BaseSource, today: CalendarDay = .today()) async throws -> IndexReport {
        let clock = ContinuousClock()
        let started = clock.now
        var report = IndexReport()
        if index.meta("embedder") != embedder.identifier || index.meta("inputPolicy") != VaultPolicy.indexPolicy || index.meta("sourceRoot") != source.root.resolvingSymlinksInPath().path {
            try index.removeAll()
            try index.setMeta("embedder", embedder.identifier)
            try index.setMeta("inputPolicy", VaultPolicy.indexPolicy)
            try index.setMeta("sourceRoot", source.root.resolvingSymlinksInPath().path)
        }
        // Captions switched on or off: every photo is read again.
        let captions = captioner == nil ? "off" : "on"
        let redoPhotos = index.meta("captions") != captions
        let stamps = try index.stamps()
        var gone = Set(stamps.keys)
        for file in files(in: source) {
            report.scannedFiles += 1
            gone.remove(file.key)
            if stamps[file.key] == file.stamp, !(file.isPhoto && redoPhotos) { continue }
            do {
                let (items, complete) = try await read(file, source: source, today: today)
                if file.isPhoto { try forgetThumbnails(ofFile: file.key, keeping: items) }
                // An incomplete read (place lookup failed) keeps a stamp that won't match next time.
                try index.replace(file: file.key, stamp: complete ? file.stamp : file.stamp + "|retry", items: items, vectors: items.map(vector))
                report.changedFiles += 1
            } catch {
                report.problems.append("\(file.key) : \(error.localizedDescription)")
            }
        }
        for gone in gone {
            try forgetThumbnails(ofFile: gone, keeping: [])
            try index.remove(file: gone)
            report.removedFiles += 1
        }
        try index.setMeta("captions", captions)
        if diagrams != nil, !source.isVault {
            report.diagrams = await refreshDiagrams(source: source)
        }
        let all = try index.items()
        report.items = all.count
        report.photos = all.filter { $0.item.kind == .photo }.count
        report.elapsed = clock.now - started
        try index.setMeta("lastIndexed", ISO8601DateFormatter().string(from: Date()))
        return report
    }

    private func vector(_ item: BaseItem) -> [Float]? {
        embedder.vector(for: String((item.label + "\n" + item.text).prefix(1000)))
    }

    // MARK: Files

    struct File {
        let url: URL
        /// Path relative to the base, or absolute for an added photo folder.
        let key: String
        let stamp: String
        let isPhoto: Bool
    }

    static let photoTypes: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
    static let textTypes: Set<String> = ["md", "txt", "pdf", "docx", "rtf"]

    /// Only the base's own folders and its two root files: never the rest of a folder the base
    /// was put in by mistake (the home folder…).
    private func files(in source: BaseSource) -> [File] {
        var found: [File] = []
        let rootPath = source.root.path + "/"
        let known = source.isVault ? Self.walk(source.root) : BaseScaffold.folders.flatMap { Self.walk(source.root.appendingPathComponent($0, isDirectory: true)) }
            + ["cv.md", "bio.md", BaseScaffold.opinionsFile].map { source.root.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        for url in known {
            let key = String(url.path.dropFirst(rootPath.count))
            guard VaultPolicy.allows(path: key),
                  url.resolvingSymlinksInPath().path.hasPrefix(source.root.resolvingSymlinksInPath().path + "/"),
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
            let type = url.pathExtension.lowercased()
            if source.isVault {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
                guard type == "md", size <= 1_048_576 else { continue }
                found.append(File(url: url, key: key, stamp: Self.stamp(url), isPhoto: false))
                continue
            }
            let top = key.split(separator: "/").first.map(String.init) ?? ""
            if top == "photos", Self.photoTypes.contains(type) {
                found.append(File(url: url, key: key, stamp: Self.stamp(url), isPhoto: true))
            } else if Self.textTypes.contains(type), Self.kind(ofKey: key) != nil {
                found.append(File(url: url, key: key, stamp: Self.stamp(url), isPhoto: false))
            }
        }
        for folder in (source.isVault ? [] : source.photoFolders) where !folder.path.hasPrefix(rootPath) {
            for url in Self.walk(folder) where Self.photoTypes.contains(url.pathExtension.lowercased()) {
                found.append(File(url: url, key: url.path, stamp: Self.stamp(url), isPhoto: true))
            }
        }
        return found
    }

    static func kind(ofKey key: String) -> BaseKind? {
        let type = (key as NSString).pathExtension.lowercased()
        if type == "md" { return BaseChunker.kind(forPath: key) }
        if key.hasPrefix("reference/") { return .reference }
        if key.hasPrefix("notes/"), type == "txt" { return .note }
        return nil
    }

    private static func walk(_ folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
    }

    private static func stamp(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(values?.fileSize ?? 0):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    /// The file's items, and whether everything could be read (a failed place lookup: no).
    private func read(_ file: File, source: BaseSource, today: CalendarDay) async throws -> (items: [BaseItem], complete: Bool) {
        if file.isPhoto {
            guard let (item, complete) = try await photo(file) else { return ([], true) }
            return ([item], complete)
        }
        let type = file.url.pathExtension.lowercased()
        if source.isVault {
            let text = try String(contentsOf: file.url, encoding: .utf8)
            guard !VaultPolicy.containsSecrets(text) else { return ([], true) }
            if let kind = VaultPolicy.documentKind(for: file.key) {
                return (BaseChunker.items(markdown: text, path: file.key, today: today, kind: kind), true)
            }
            return (ReferenceText.items(text: Frontmatter(markdown: text).body, path: file.key, kind: .note), true)
        }
        if type == "md", BaseChunker.kind(forPath: file.key) != nil {
            return (BaseChunker.items(markdown: try String(contentsOf: file.url, encoding: .utf8), path: file.key, today: today), true)
        }
        guard let kind = Self.kind(ofKey: file.key) else { return ([], true) }
        return (ReferenceText.items(text: try ReferenceText.read(file.url), path: file.key, kind: kind), true)
    }

    // MARK: Photos

    private func photo(_ file: File) async throws -> (BaseItem, complete: Bool)? {
        guard let metadata = PhotoMetadata(url: file.url) else { return nil }
        var place: String?
        var complete = true
        if let coordinate = metadata.coordinate {
            let key = String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
            switch try index.cachedPlace(forKey: key) {
            case let .named(name):
                place = name
            case .nowhere:
                break
            case nil:
                if let places {
                    do {
                        place = try await places.name(for: coordinate)
                        try index.cachePlace(place.map(BaseIndex.CachedPlace.named) ?? .nowhere, forKey: key)
                    } catch {
                        complete = false
                    }
                }
            }
        }
        let labels = labeler?.labels(for: file.url) ?? []
        let caption = try? await captioner?.caption(for: file.url)
        let folder = file.url.deletingLastPathComponent().lastPathComponent.replacingOccurrences(of: "-", with: " ")
        var fields: [String: FrontmatterValue] = ["path": .text(file.url.path)]
        if let thumbnail = thumbnail(of: file) { fields["thumb"] = .text(thumbnail.path) }
        if !labels.isEmpty { fields["labels"] = .list(labels) }
        if let caption { fields["legende"] = .text(caption) }
        if let coordinate = metadata.coordinate { fields["gps"] = .text("\(coordinate.latitude),\(coordinate.longitude)") }
        let when = metadata.taken.map(Self.monthYear)
        let text = [place, folder, when, labels.joined(separator: ", "), caption].compactMap { $0 }.filter { !$0.isEmpty }
        let item = BaseItem(
            id: "photo:\(file.key)", kind: .photo, source: file.key, title: place ?? folder,
            text: text.joined(separator: "\n"), dates: metadata.taken.map { DateSpan($0, $0) }, place: place, fields: fields
        )
        return (item, complete)
    }

    static func monthYear(_ day: CalendarDay) -> String {
        let names = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
        return "\(names[day.month - 1]) \(day.year)"
    }

    /// 720 px JPEG, read by the photo grid and its enlarged view (originals can be 10 MB). Named
    /// after the photo's path and stamp: an edited photo gets a new one.
    private func thumbnail(of file: File) -> URL? {
        let name = SHA256.hash(data: Data((file.url.path + "|" + file.stamp).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let target = store.appendingPathComponent("thumbs/\(name).jpg")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        guard let jpeg = ImageThumbnail.jpeg(of: file.url, maxPixelSize: 720, quality: 0.8) else { return nil }
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? jpeg.data.write(to: target)) != nil ? target : nil
    }

    /// Copies of personal photos don't outlive them in Application Support.
    private func forgetThumbnails(ofFile key: String, keeping items: [BaseItem]) throws {
        let kept = Set(items.compactMap { $0.fields["thumb"]?.text })
        for old in try index.items(ofFile: key) {
            if let thumb = old.fields["thumb"]?.text, !kept.contains(thumb), thumb.hasPrefix(store.path) {
                try? FileManager.default.removeItem(atPath: thumb)
            }
        }
    }

    // MARK: Diagrams

    private func refreshDiagrams(source: BaseSource) async -> [String: DiagramRecord.Status] {
        guard let diagrams, let stored = try? index.items() else { return [:] }
        var statuses: [String: DiagramRecord.Status] = [:]
        for item in stored.map(\.item) where item.kind == .project && item.section == nil {
            guard let path = item.fields["repo"]?.text, let repo = Self.repoURL(path, root: source.root),
                  let snapshot = try? RepoSnapshot(at: repo) else { continue }
            let hash = snapshot.hash
            let existing = index.diagram(forProject: item.source)
            guard DiagramCache.plan(existing: existing?.record, repoHash: hash) == .generate else {
                statuses[item.title] = existing?.record.status
                continue
            }
            let record: DiagramRecord
            var image: URL?
            do {
                if let made = try await diagrams.diagram(project: item.title, snapshot: snapshot, into: store.appendingPathComponent("diagrams")) {
                    record = DiagramRecord(repoHash: hash, mermaid: made.mermaid, status: .ok)
                    image = made.image
                } else {
                    record = DiagramRecord(repoHash: hash, mermaid: nil, status: .invalid)
                }
            } catch {
                record = DiagramRecord(repoHash: hash, mermaid: nil, status: .failed)
            }
            try? index.setDiagram(record, image: image, forProject: item.source)
            statuses[item.title] = record.status
        }
        return statuses
    }

    /// `~/…`, absolute, or relative to the base. Never the home folder itself or one of its
    /// direct folders (`~/Projects` is a folder of repos, not a repo).
    static func repoURL(_ path: String, root: URL) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let expanded: URL
        if path.hasPrefix("~/") {
            expanded = home.appendingPathComponent(String(path.dropFirst(2)))
        } else if path.hasPrefix("/") {
            expanded = URL(fileURLWithPath: path)
        } else {
            expanded = root.appendingPathComponent(path)
        }
        let url = expanded.standardizedFileURL
        guard url != home, url.deletingLastPathComponent() != home, url.pathComponents.count > 2 else { return nil }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : nil
    }
}
