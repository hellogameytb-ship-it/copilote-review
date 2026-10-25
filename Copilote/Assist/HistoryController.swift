import AppKit
import CopiloteKit

/// The sessions kept on this Mac (only with "Garder l'historique"): list, search, open,
/// export, delete, retention.
@MainActor
final class HistoryController: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published var query = "" {
        didSet { reload() }
    }
    @Published var selection: UUID? {
        didSet { opened = selection.flatMap { try? store?.session(id: $0) } }
    }
    @Published private(set) var opened: SessionRecord?
    /// "Garder l'historique" is on (sessions kept before stay readable when it is off).
    @Published private(set) var isRecording = false

    private let settings: SettingsStore
    private var store: HistoryStore?

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Copilote/History/history.sqlite")
    }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Opens the store if history is on (or was: past sessions stay readable), applies retention.
    /// Called at launch and when the history settings change.
    func start() {
        isRecording = settings.keepHistory
        guard settings.keepHistory || FileManager.default.fileExists(atPath: Self.url.path) else { return }
        if store == nil { store = try? HistoryStore(url: Self.url) }
        purge()
        reload()
    }

    func save(_ record: SessionRecord) {
        guard settings.keepHistory else { return }
        if store == nil { store = try? HistoryStore(url: Self.url) }
        try? store?.save(record)
        purge()
        reload()
        if selection == record.id { opened = record }
    }

    private func purge() {
        if settings.historyRetentionDays > 0 { _ = try? store?.purge(olderThanDays: settings.historyRetentionDays) }
    }

    func delete(_ record: SessionRecord) {
        let alert = NSAlert()
        alert.messageText = Copy.History.deleteTitle(record.title)
        alert.informativeText = Copy.History.deleteMessage
        alert.addButton(withTitle: Copy.History.delete).hasDestructiveAction = true
        alert.addButton(withTitle: Copy.History.keep)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store?.delete(id: record.id)
        selection = nil
        reload()
    }

    func export(_ record: SessionRecord) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(record.title).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? record.markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    private func reload() {
        sessions = (try? query.isEmpty ? store?.sessions() : store?.search(query)) ?? []
    }
}
