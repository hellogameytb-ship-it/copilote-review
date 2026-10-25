import AppKit
import WebKit

/// Local WKWebView rendering the answer (Markdown, highlight.js, Mermaid — all bundled).
/// It only ever loads `web/index.html` from the app bundle; every other navigation is refused.
final class ResponseWebView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    private var isReady = false
    private var pendingScripts: [String] = []
    private var lastRenderScript: String?
    private var lastHintsScript: String?
    /// « Réessayer » under a failed answer.
    var onRetry: (() -> Void)?
    var onCopy: (String) -> Void = { Clipboard.copy($0) }

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if #available(macOS 15.0, *) { configuration.writingToolsBehavior = .none }
        super.init(frame: .zero, configuration: configuration)
        configuration.userContentController.add(self, name: "copilote")
        navigationDelegate = self
        allowsBackForwardNavigationGestures = false
        allowsMagnification = false
        // Nothing that opens a system window (seen in a screen share): no link preview; the page
        // cancels the context menu; Look Up below.
        allowsLinkPreview = false
        underPageBackgroundColor = .clear
        // macOS WebKit draws a default document backing even when CSS is transparent.
        setValue(false, forKey: "drawsBackground")
        #if DEBUG
        isInspectable = true
        #endif
        loadPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Look Up (force click, three-finger tap) opens a system popover.
    override func quickLook(with event: NSEvent) {}

    /// Belt and braces with the page's `contextmenu` handler: never a menu.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
    }

    /// The panel is never key: without this the first click (e.g. "Copy") would be swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Commands

    func render(payloadJSON: String) {
        let script = "window.copilote.render(\(payloadJSON))"
        lastRenderScript = script
        run(script, replacingPendingRender: true)
    }

    func reset() {
        lastRenderScript = nil
        run("window.copilote.reset()", replacingPendingRender: true)
    }

    func setHints(json: String) {
        let script = "window.copilote.setHints(\(json))"
        lastHintsScript = script
        run(script, replacingPendingRender: false)
    }

    func scrollPage(_ direction: Int) {
        run("window.copilote.scrollPage(\(direction))", replacingPendingRender: false)
    }

    private func run(_ script: String, replacingPendingRender: Bool) {
        guard isReady else {
            if replacingPendingRender { pendingScripts.removeAll { $0.hasPrefix("window.copilote.render(") } }
            pendingScripts.append(script)
            return
        }
        evaluateJavaScript(script, completionHandler: nil)
    }

    private func loadPage() {
        guard let directory = Bundle.main.url(forResource: "web", withExtension: nil) else { return }
        loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let page = Bundle.main.url(forResource: "web", withExtension: nil)?.appendingPathComponent("index.html")
        let url = navigationAction.request.url
        let isBundledPage = url?.isFileURL == true && url?.standardizedFileURL.path == page?.standardizedFileURL.path
        decisionHandler(isBundledPage ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        pendingScripts = [lastHintsScript, lastRenderScript].compactMap { $0 }
        loadPage()
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            let scripts = pendingScripts
            pendingScripts.removeAll()
            scripts.forEach { evaluateJavaScript($0, completionHandler: nil) }
        case "copy":
            if let text = body["text"] as? String { onCopy(text) }
        case "retry":
            onRetry?()
        case "openSource":
            if let text = body["url"] as? String, let url = URL(string: text), url.scheme == "https", url.host != nil, url.user == nil {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }
}
