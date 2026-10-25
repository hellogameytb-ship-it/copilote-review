import AppKit
import CopiloteKit

/// The personal base in the app: `~/Copilote/` (created with its templates on first launch),
/// its index in Application Support, reindexing when files change, and the fiche shown for a
/// personal question, found in milliseconds without the LLM.
@MainActor
final class BaseController: ObservableObject {
    struct Status: Equatable {
        var items = 0
        var photos = 0
        var lastIndexed: Date?
        var isIndexing = false
        var message: String?
    }

    /// The fiche in the overlay, shown in full or suggested in one line.
    struct DisplayedFiche: Identifiable, Equatable {
        let fiche: Fiche
        var action: PersonalRouter.Action
        let question: String
        /// From the end of the turn to the fiche being ready.
        let latency: Duration

        var id: String { fiche.id + question }
    }

    /// An opinion question whose subject is not in avis.md: « Pas dans ta base ».
    struct MissingOpinion: Equatable {
        let topicID: String
        var subject: String
        var isAdded = false
        var failure: String?
    }

    @Published private(set) var status = Status()
    @Published private(set) var displayed: DisplayedFiche?
    @Published private(set) var missingOpinion: MissingOpinion?
    /// The fiche above an answer folds once the answer has words.
    @Published private(set) var fold = FicheFold()

    private let settings: SettingsStore
    private let providers: ProviderController
    private var index: BaseIndex?
    private var embedder: TextEmbedder?
    private var personal: PersonalBase?
    private var watcher: FolderWatcher?
    private var indexing: Task<Void, Never>?
    private var reindexAgain = false
    /// The latest question's lookup: an older one finishing late must not replace its fiche.
    private var routing: Task<Void, Never>?

    static var store: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Copilote/Base", isDirectory: true)
    }

    init(settings: SettingsStore, providers: ProviderController) {
        self.settings = settings
        self.providers = providers
    }

    var isReadOnly: Bool { VaultPolicy.isVault(root) }

    var root: URL { URL(fileURLWithPath: settings.baseFolder, isDirectory: true) }

    /// Why a folder can't be the base, or nil. Not the home folder or above it, nor a folder
    /// holding the index itself (each reindex would wake the watcher again).
    static func problem(withBaseFolder folder: URL) -> String? {
        let folder = folder.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if home.hasPrefix(folder) { return "Choose a dedicated folder, not your home directory." }
        if store.standardizedFileURL.path.hasPrefix(folder + "/") { return "This folder contains Copilote’s index." }
        return nil
    }

    /// Creates the folder and its templates if missing, opens the index, loads the on-device
    /// model and the index in memory, indexes what changed and watches the folders.
    func start() {
        do {
            if let problem = Self.problem(withBaseFolder: root) {
                status.message = problem
                return
            }
            guard FileManager.default.fileExists(atPath: root.path) else {
                status.message = "Brain is unavailable. Make it available locally in iCloud. No folder was created."
                return
            }
            index = try BaseIndex(url: Self.store.appendingPathComponent("index.sqlite"))
            if index?.meta("sourceRoot") != root.resolvingSymlinksInPath().path || index?.meta("inputPolicy") != VaultPolicy.indexPolicy {
                try index?.removeAll()
            }
        } catch {
            status.message = "Brain unavailable: \(error.localizedDescription)"
            return
        }
        refreshCounts()
        Task {
            let embedder: TextEmbedder = await ContextualEmbedder.prepare() ?? NoEmbedder()
            self.embedder = embedder
            if let index {
                let personal = PersonalBase(search: BaseSearch(index: index, embedder: embedder), index: index, root: root)
                self.personal = personal
                await personal.warmUp()
            }
            reindex()
        }
        watch()
    }

    /// Another base folder or photo folders: watch them and index again.
    func foldersChanged() {
        dismiss()
        if index?.meta("sourceRoot") != root.resolvingSymlinksInPath().path { try? index?.removeAll() }
        if let index, let embedder {
            personal = PersonalBase(search: BaseSearch(index: index, embedder: embedder), index: index, root: root)
        }
        watch()
        reindex()
    }

    func reindex() {
        guard let index, let embedder, Self.problem(withBaseFolder: root) == nil else { return }
        guard indexing == nil else {
            reindexAgain = true
            return
        }
        status.isIndexing = true
        let source = BaseSource(root: root, photoFolders: settings.basePhotoFolders.map { URL(fileURLWithPath: $0, isDirectory: true) })
        // Diagrams and captions go through the active provider; without one they wait for the next run.
        let provider = providers.current()
        let captions = settings.basePhotoCaptions
        let webFolder = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true)
        let store = Self.store
        indexing = Task.detached(priority: .utility) {
            let indexer = BaseIndexer(
                index: index, embedder: embedder, store: store, places: GeocoderPlaceNamer(), labeler: VisionLabeler(),
                captioner: captions && !source.isVault ? provider.map(LLMPhotoCaptioner.init) : nil,
                diagrams: source.isVault ? nil : webFolder.flatMap { folder in provider.map { LLMDiagramMaker(provider: $0, webFolder: folder) } }
            )
            let outcome: Result<IndexReport, Error>
            do { outcome = .success(try await indexer.run(source)) } catch { outcome = .failure(error) }
            await MainActor.run { self.finished(outcome) }
        }
    }

    private func finished(_ outcome: Result<IndexReport, Error>) {
        indexing = nil
        status.isIndexing = false
        switch outcome {
        case let .success(report):
            status.message = report.problems.isEmpty ? nil : "\(report.problems.count) unreadable file(s) : \(report.problems.first ?? "")"
        case let .failure(error):
            status.message = "Indexing failed: \(error.localizedDescription)"
        }
        refreshCounts()
        // The new index in memory now, not at the next question.
        if let personal { Task { await personal.warmUp() } }
        if reindexAgain {
            reindexAgain = false
            reindex()
        }
    }

    private func refreshCounts() {
        guard let index, let items = try? index.items() else { return }
        status.items = items.count
        status.photos = items.filter { $0.item.kind == .photo }.count
        status.lastIndexed = index.meta("lastIndexed").flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private func watch() {
        let folders = [root] + settings.basePhotoFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }
        watcher = FolderWatcher(folders: folders) { [weak self] in self?.reindex() }
    }

    // MARK: Personal questions

    private var router: PersonalRouter {
        PersonalRouter(mode: PersonalRouter.Mode(rawValue: settings.baseMode) ?? .show)
    }

    /// A turn of the others: if it is about the user and a fiche is sure enough, it shows now.
    func route(_ question: String) {
        guard let personal, router.mode != .off else { return }
        let clock = ContinuousClock()
        let started = clock.now
        let router = router
        routing?.cancel()
        routing = Task {
            guard let found = await personal.fiche(for: question, router: router), !Task.isCancelled else { return }
            // The same fiche found again keeps its fold: it must not reopen over words being read.
            if displayed?.fiche.id != found.fiche.id { fold.ficheShown() }
            displayed = DisplayedFiche(fiche: found.fiche, action: found.decision.action, question: question, latency: clock.now - started)
        }
    }

    /// The base's best extracts for a topic about the user (none for anything else).
    func snippets(for text: String) async -> [BaseSnippet] {
        await personal?.snippets(for: text, router: router) ?? []
    }

    /// How a case is answered: its kind's format and the extracts it may use (avis.md alone for an opinion).
    func plan(for topic: Topic, conversation: [TranscriptLine] = []) async -> AnswerPlan {
        await AnswerPlan.make(heard: topic.excerpt.isEmpty ? [topic.title] : topic.excerpt, base: router.mode == .off ? nil : personal, conversation: conversation)
    }

    /// « Afficher » on a suggestion: the fiche opens, even over an answer being read.
    func expand() {
        displayed?.action = .show
        fold.open()
    }

    /// The answer on screen (none, asked, words to read) folds or opens the fiche above it.
    func followAnswer(_ phase: AnswerPhase) {
        fold.answer(phase)
    }

    /// The folded line clicked, or the open fiche's fold button.
    func toggleFold() {
        fold.toggle()
    }

    func dismiss() {
        routing?.cancel()
        displayed = nil
        missingOpinion = nil
    }

    // MARK: Opinions not in the base

    /// An answer for this case (nil: the last phrases) is on its way: an opinion not in avis.md
    /// shows « Pas dans ta base », which offers to add its subject.
    func answering(_ topic: Topic?, neutralOpinion: Bool) {
        guard let topic, neutralOpinion else {
            missingOpinion = nil
            return
        }
        guard missingOpinion?.topicID != topic.id else { return }
        missingOpinion = MissingOpinion(topicID: topic.id, subject: OpinionLookup.subject(ofTitle: topic.title))
    }

    /// The model's better title, or the case it merged into, until the user adds it.
    func follow(_ topic: Topic, from id: String? = nil) {
        guard var missing = missingOpinion, missing.topicID == (id ?? topic.id), !missing.isAdded else { return }
        missing = MissingOpinion(topicID: topic.id, subject: OpinionLookup.subject(ofTitle: topic.title))
        missingOpinion = missing
    }

    /// Case 1's answer drafts itself under the fiche: not under the fiche of an earlier question.
    /// (The lookup for this question goes on: its fiche may still arrive.)
    func keepFiche(onlyFor topic: Topic) {
        if let displayed, !topic.excerpt.contains(displayed.question) { self.displayed = nil }
    }

    /// Its case left the board.
    func dropMissingOpinion(of topicID: String) {
        if missingOpinion?.topicID == topicID { missingOpinion = nil }
    }

    /// An empty section to fill in after the meeting; reindexing follows from the folder watcher.
    func addMissingOpinion() {
        guard var missing = missingOpinion, !missing.isAdded else { return }
        guard !VaultPolicy.isVault(root) else {
            missing.failure = "Brain is read-only. Edit your opinion in Obsidian."
            missingOpinion = missing
            return
        }
        do {
            try BaseScaffold.addOpinion(missing.subject, at: root)
            missing.isAdded = true
            missing.failure = nil
        } catch {
            missing.failure = Copy.Direct.addFailed(error.localizedDescription)
        }
        missingOpinion = missing
    }
}
