import AppKit
import Combine
import CopiloteKit

/// Single asynchronous entry for app-owned file browsing; no native open/save panel is created.
@MainActor
enum SystemDialogs {
    private static var sessionSubscription: AnyCancellable?
    private static var suspendObserver: NSObjectProtocol?
    private static var sessionActive = false
    private static var activeBrowser: ProtectedFileBrowser?
    private static var defaults = UserDefaults.standard
    private static let bookmarkKey = "protectedFileBrowserFolderBookmark"
    static var diagnosticInvocation: (() -> Void)?
    static var diagnosticBrowser: ProtectedFileBrowser? { DiagnosticRecette.isRequested ? activeBrowser : nil }

    enum Refusal: LocalizedError {
        case session, hidden, busy
        var errorDescription: String? {
            switch self {
            case .session: return "End the listening session before browsing files or exporting. Pausing is not enough. Then click again; nothing will open automatically."
            case .hidden: return "Show Copilote explicitly before browsing files. Nothing will open automatically."
            case .busy: return "Finish or cancel the open file browser first."
            }
        }
    }
    static func observe(_ listening: ListeningController, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sessionSubscription = listening.$state.sink { state in
            switch state { case .starting, .listening: sessionActive = true; case .idle, .failed: sessionActive = false }
            if sessionActive { activeBrowser?.refuse(Refusal.session) }
        }
        if let suspendObserver { NotificationCenter.default.removeObserver(suspendObserver) }
        suspendObserver = NotificationCenter.default.addObserver(forName: .copilotePresentationSuspended, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { activeBrowser?.refuse(Refusal.hidden) }
        }
    }
    static func checkPermission() throws {
        if sessionActive { throw Refusal.session }
        if !WindowPrivacy.presentationAuthorized || !WindowPrivacy.environmentAvailable { throw Refusal.hidden }
    }
    static func chooseFolder() async throws -> URL? { try await browse(mode: .folder, name: "") }
    static func saveMarkdown(_ text: String, name: String) async throws { _ = try await browse(mode: .markdown(text), name: name) }

    private static func browse(mode: ProtectedFileBrowser.Mode, name: String) async throws -> URL? {
        try checkPermission()
        guard activeBrowser == nil else { throw Refusal.busy }
        try Task.checkCancellation()
        if DiagnosticRecette.isRequested, let diagnosticInvocation { diagnosticInvocation(); return nil }
        let directory = defaults.data(forKey: bookmarkKey).flatMap { try? FileBrowserBookmark.resolve($0) } ?? FileManager.default.homeDirectoryForCurrentUser
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let browser = ProtectedFileBrowser(mode: mode, directory: directory, name: name) { result in
                    activeBrowser = nil
                    switch result {
                    case .success(let url):
                        if let url {
                            let folder: URL
                            if case .folder = mode { folder = url } else { folder = url.deletingLastPathComponent() }
                            if let bookmark = try? FileBrowserBookmark.create(folder) { defaults.set(bookmark, forKey: bookmarkKey) }
                        }
                    case .failure: break
                    }
                    continuation.resume(with: result)
                }
                browser.panel.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
                activeBrowser = browser
                do { try Task.checkCancellation(); try browser.present() }
                catch { browser.refuse(error) }
            }
        } onCancel: {
            Task { @MainActor in
                guard activeBrowser?.panel.identifier?.rawValue == id.uuidString else { return }
                activeBrowser?.refuse(CancellationError())
            }
        }
    }
}
