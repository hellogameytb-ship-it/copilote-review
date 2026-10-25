import AppKit
import Combine

/// Explicit OS UI exceptions. Callers display the visibility notice before the user's click.
/// These dialogs are not advertised as protected Copilote surfaces.
@MainActor
enum SystemDialogs {
    private static var sessionSubscription: AnyCancellable?
    private static var suspendObserver: NSObjectProtocol?
    private static var sessionActive = false
    private static var activePanel: NSSavePanel?
    static var diagnosticInvocation: (() -> Void)?

    enum Refusal: LocalizedError {
        case session, hidden
        var errorDescription: String? {
            switch self {
            case .session: return "End the listening session before opening a file dialog or exporting. Pausing is not enough. Then click again; nothing will open automatically."
            case .hidden: return "Show Copilote explicitly before opening a file dialog. Nothing will open automatically."
            }
        }
    }
    static func observe(_ listening: ListeningController) {
        sessionSubscription = listening.$state.sink { state in
            switch state { case .starting, .listening: sessionActive = true; case .idle, .failed: sessionActive = false }
            if sessionActive { activePanel?.cancel(nil) }
        }
        if let suspendObserver { NotificationCenter.default.removeObserver(suspendObserver) }
        suspendObserver = NotificationCenter.default.addObserver(forName: .copilotePresentationSuspended, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { activePanel?.cancel(nil) }
        }
    }
    static func checkPermission() throws {
        if sessionActive { throw Refusal.session }
        if !WindowPrivacy.presentationAuthorized { throw Refusal.hidden }
    }
    static func chooseFolder() throws -> URL? {
        try checkPermission()
        if DiagnosticRecette.isRequested, let diagnosticInvocation { diagnosticInvocation(); return nil }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        activePanel = panel; defer { activePanel = nil }
        let response = panel.runModal()
        try checkPermission()
        return response == .OK ? panel.url : nil
    }

    static func saveMarkdown(_ text: String, name: String) throws {
        try checkPermission()
        if DiagnosticRecette.isRequested, let diagnosticInvocation { diagnosticInvocation(); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        activePanel = panel; defer { activePanel = nil }
        let response = panel.runModal()
        try checkPermission()
        guard response == .OK, let url = panel.url else { return }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
