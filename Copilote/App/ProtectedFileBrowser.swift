import AppKit
import SwiftUI
import CopiloteKit

/// One app-owned browser; all errors and replacement confirmation remain in its protected panel.
@MainActor
final class ProtectedFileBrowser: NSObject, ObservableObject, NSWindowDelegate {
    enum Mode { case folder, markdown(String) }
    struct Entry: Identifiable {
        let url: URL
        let isDirectory: Bool
        let isLink: Bool
        var id: String { url.path }
    }
    struct Replacement {
        let url: URL
        let revision: MarkdownFileExport.Revision
    }
    let mode: Mode
    final class BrowserPanel: OverlayPanel {
        var onCancel: (() -> Void)?
        init() { super.init(size: NSSize(width: 640, height: 500), resizable: false) }
        override func sendEvent(_ event: NSEvent) {
            if event.type == .keyDown, event.keyCode == 53,
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                onCancel?(); return
            }
            super.sendEvent(event)
        }
        override func cancelOperation(_ sender: Any?) { onCancel?() }
    }
    let panel = BrowserPanel()
    @Published private(set) var directory: URL
    @Published private(set) var entries: [Entry] = []
    @Published var path: String
    @Published var name: String { didSet { replacement = nil } }
    @Published var notice: String?
    @Published private(set) var replacement: Replacement?
    private var canSelectDirectory = false
    private var completion: ((Result<URL?, Error>) -> Void)?
    private weak var previousKeyWindow: NSWindow?
    var isSaving: Bool { if case .markdown = mode { return true }; return false }

    init(mode: Mode, directory: URL, name: String, completion: @escaping (Result<URL?, Error>) -> Void) {
        self.mode = mode; self.directory = directory; self.path = directory.path
        self.name = MarkdownFileExport.suggestedName(name); self.completion = completion
        super.init()
        panel.title = isSaving ? "Export Markdown" : "Choose folder"
        panel.allowsKey = true; panel.delegate = self
        panel.onCancel = { [weak self] in self?.cancel() }
        let host = FirstMouseHostingView(rootView: ProtectedFileBrowserView(browser: self))
        panel.contentView = OverlayController.surface(hosting: host, cornerRadius: 14)
        navigate(directory)
    }
    func present() throws {
        try SystemDialogs.checkPermission()
        guard WindowPrivacy.canPresent(panel) else { throw SystemDialogs.Refusal.hidden }
        previousKeyWindow = NSApp.keyWindow
        if let screen = previousKeyWindow?.screen ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.midY - panel.frame.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        guard panel.isVisible else { throw SystemDialogs.Refusal.hidden }
    }
    private func permitted() -> Bool {
        guard completion != nil else { return false }
        do { try SystemDialogs.checkPermission(); return true }
        catch { finish(.failure(error)); return false }
    }
    func navigate(_ destination: URL) {
        guard permitted() else { return }
        replacement = nil; notice = nil; canSelectDirectory = false; entries = []
        let url = destination.standardizedFileURL.resolvingSymlinksInPath()
        do {
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                notice = "Choose an existing folder."; return
            }
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            let items = try urls.map { url -> Entry in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return Entry(url: url, isDirectory: values.isDirectory == true, isLink: values.isSymbolicLink == true)
            }
            directory = url; path = url.path; canSelectDirectory = true
            entries = items.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
            }
        } catch { notice = "Could not read this folder: \(error.localizedDescription)" }
    }
    func go() {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { notice = "Enter an absolute folder path, or a path beginning with ~/."; return }
        navigate(URL(fileURLWithPath: expanded, isDirectory: true))
    }
    func open(_ entry: Entry) {
        guard permitted() else { return }
        if entry.isLink { notice = "Symbolic links are not opened here. Enter the destination folder path explicitly."; return }
        if entry.isDirectory { navigate(entry.url) }
        else if isSaving { name = entry.url.lastPathComponent; notice = nil }
    }
    func accept() {
        guard permitted(), canSelectDirectory else { return }
        if case .folder = mode {
            // Recheck readability after navigation: the directory might have moved or disappeared.
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                finish(.success(directory))
            } catch { notice = error.localizedDescription }
        } else {
            do {
                name = try MarkdownFileExport.filename(name)
                let destination = directory.appendingPathComponent(name)
                if let revision = try MarkdownFileExport.revision(at: destination) {
                    replacement = Replacement(url: destination, revision: revision)
                } else { write(replacing: nil) }
            } catch { notice = error.localizedDescription }
        }
    }
    func confirmReplacement() {
        guard permitted(), let replacement, replacement.url == directory.appendingPathComponent(name) else { return }
        write(replacing: replacement.revision)
    }
    func keepExisting() { replacement = nil; notice = nil }
    private func write(replacing revision: MarkdownFileExport.Revision?) {
        guard permitted(), case .markdown(let text) = mode else { return }
        do {
            try MarkdownFileExport.write(text, directory: directory, name: name, replacing: revision)
            finish(.success(directory.appendingPathComponent(name)))
        } catch { replacement = nil; notice = error.localizedDescription }
    }
    func cancel() { finish(.success(nil)) }
    func refuse(_ error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<URL?, Error>) {
        guard let completion else { return }
        self.completion = nil
        panel.orderOut(nil); panel.delegate = nil
        // The hosting view observes this controller; break panel → view → controller on completion.
        panel.contentView = nil; panel.onCancel = nil
        if let previousKeyWindow, previousKeyWindow.isVisible, WindowPrivacy.presentationAuthorized { previousKeyWindow.makeKey() }
        completion(result)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
}

private struct ProtectedFileBrowserView: View {
    @ObservedObject var browser: ProtectedFileBrowser
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(browser.isSaving ? "Export Markdown" : "Choose folder").font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel", action: browser.cancel).keyboardShortcut(.cancelAction)
            }
            HStack {
                Button("Up") { browser.navigate(browser.directory.deletingLastPathComponent()) }
                Button("Home") { browser.navigate(FileManager.default.homeDirectoryForCurrentUser) }
                TextField("Folder path", text: $browser.path).textFieldStyle(.roundedBorder).onSubmit(browser.go)
                Button("Go", action: browser.go)
            }
            Text(browser.directory.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(browser.entries) { entry in
                        Button { browser.open(entry) } label: {
                            HStack {
                                Image(systemName: entry.isLink ? "link" : entry.isDirectory ? "folder" : "doc.text")
                                Text(entry.url.lastPathComponent).lineLimit(1)
                                Spacer()
                                if entry.isDirectory { Image(systemName: "chevron.right") }
                            }.padding(7).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .disabled(!entry.isDirectory && !browser.isSaving)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            if browser.isSaving { TextField("Filename", text: $browser.name).textFieldStyle(.roundedBorder) }
            if let replacement = browser.replacement {
                Text("Replace “\(replacement.url.lastPathComponent)”? Its current contents will be replaced.").font(.callout)
                HStack {
                    Button("Keep existing", action: browser.keepExisting)
                    Spacer()
                    Button("Replace file", action: browser.confirmReplacement)
                }
            } else {
                HStack {
                    Text("Available outside listening sessions.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(browser.isSaving ? "Save Markdown" : "Choose this folder", action: browser.accept)
                }
            }
            if let notice = browser.notice { Text(notice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(18).frame(width: 640, height: 500)
        .onExitCommand(perform: browser.cancel)
    }
}
