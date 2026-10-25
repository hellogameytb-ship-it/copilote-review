import AppKit
import WebKit

/// Renders a Mermaid diagram to PNG with the bundled mermaid.js in an off-screen WKWebView
/// (`web/diagram.html`). Rendering is the final validation: what Mermaid rejects is not stored.
@MainActor
public final class MermaidRenderer: NSObject, WKNavigationDelegate {
    private let webFolder: URL
    private var view: WKWebView?
    private var loading: CheckedContinuation<Void, Error>?

    /// `webFolder` holds `diagram.html` and `vendor/mermaid.min.js`.
    public init(webFolder: URL) {
        self.webFolder = webFolder
    }

    /// nil when Mermaid rejects the source.
    public func png(for source: String) async throws -> Data? {
        let view = try await loadedView()
        let result: Any?
        do {
            // A page that never answers must not hold the indexing back.
            result = try await Self.within(.seconds(15)) {
                try await view.callAsyncJavaScript("return await window.copiloteDiagram(source)", arguments: ["source": source], contentWorld: .page)
            }
        } catch {
            return nil
        }
        guard let size = result as? [String: Any], let width = size["width"] as? Double, let height = size["height"] as? Double,
              width > 0, height > 0 else { return nil }
        let rect = NSRect(x: 0, y: 0, width: min(width, 2400), height: min(height, 2400))
        view.frame = rect
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        let image = try await view.takeSnapshot(configuration: configuration)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func loadedView() async throws -> WKWebView {
        if let view { return view }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: configuration)
        view.navigationDelegate = self
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loading = continuation
            view.loadFileURL(webFolder.appendingPathComponent("diagram.html"), allowingReadAccessTo: webFolder)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.loading?.resume(throwing: CocoaError(.fileReadUnknown))
                self?.loading = nil
            }
        }
        self.view = view
        return view
    }

    private static func within<T: Sendable>(_ limit: Duration, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw CancellationError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading?.resume(throwing: CocoaError(.fileReadUnknown))
        loading = nil
        view = nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading?.resume()
        loading = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading?.resume(throwing: error)
        loading = nil
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading?.resume(throwing: error)
        loading = nil
    }

    /// Only the diagram page itself.
    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.isFileURL == true && action.request.url?.lastPathComponent == "diagram.html" ? .allow : .cancel)
    }
}

/// The diagram of a repo through the active provider: one request, checked, rendered, stored.
public struct LLMDiagramMaker: DiagramMaker {
    private let provider: any LLMProvider
    private let webFolder: URL

    public init(provider: any LLMProvider, webFolder: URL) {
        self.provider = provider
        self.webFolder = webFolder
    }

    public func diagram(project: String, snapshot: RepoSnapshot, into folder: URL) async throws -> (mermaid: String, image: URL)? {
        let answer = try await provider.complete(
            system: "Draw concise and accurate Mermaid architecture diagrams with English labels. Return only the diagram.",
            prompt: DiagramCache.prompt(project: project, snapshot: snapshot), images: []
        )
        guard let mermaid = MermaidCheck.diagram(in: answer) else { return nil }
        let webFolder = webFolder
        guard let png = try await MainActor.run(body: { MermaidRenderer(webFolder: webFolder) }).png(for: mermaid) else { return nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(snapshot.hash.prefix(16)).png")
        try png.write(to: url)
        return (mermaid, url)
    }
}
