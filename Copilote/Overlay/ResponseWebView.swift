import AppKit
import SwiftUI
import WebKit

/// Bundled answer renderer. macOS 26+ uses the public SwiftUI WebKit background API;
/// older systems retain a WKWebView fallback without undocumented transparency setters.
@MainActor
final class ResponseWebView: NSView, WKNavigationDelegate {
    private var legacy: QuietLegacyWebView?
    private var modernStorage: AnyObject?
    private let bridge = ResponseMessageBridge()
    private var isReady = false
    private var pendingScripts: [String] = []
    private var lastRenderScript: String?
    private var lastHintsScript: String?
    var onRetry: (() -> Void)?
    var onCopy: (String) -> Void = { Clipboard.copy($0) }
    var pageZoom: Double = 1 {
        didSet { run("document.documentElement.style.zoom = \(pageZoom)", replacingPendingRender: false) }
    }
    var supportsTransparentBackground: Bool { modernStorage != nil }
    static var bundledPage: URL? { Bundle.main.url(forResource: "web", withExtension: nil)?.appendingPathComponent("index.html") }

    init() {
        super.init(frame: .zero)
        bridge.owner = self
        let view: NSView
        if #available(macOS 26, *) {
            let modern = ModernAnswerPage(bridge: bridge)
            modernStorage = modern
            view = FirstMouseHostingView(rootView: WebView(modern.page)
                .webViewContentBackground(.hidden)
                .webViewLinkPreviews(.disabled)
                .webViewBackForwardNavigationGestures(.disabled)
                .webViewMagnificationGestures(.disabled)
                .webViewTextSelection(.disabled)
                .webViewContextMenu { _ in EmptyView() })
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.add(bridge, name: "copilote")
            if #available(macOS 15, *) { configuration.writingToolsBehavior = .none }
            let web = QuietLegacyWebView(frame: .zero, configuration: configuration)
            web.navigationDelegate = self
            web.allowsLinkPreview = false
            web.allowsBackForwardNavigationGestures = false
            web.allowsMagnification = false
            web.underPageBackgroundColor = .clear
            legacy = web; view = web
        }
        view.frame = bounds; view.autoresizingMask = [.width, .height]
        addSubview(view)
        loadPage()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func quickLook(with event: NSEvent) {}

    func render(payloadJSON: String) {
        let script = "window.copilote.render(\(payloadJSON))"
        lastRenderScript = script
        run(script, replacingPendingRender: true)
    }
    func reset() { lastRenderScript = nil; run("window.copilote.reset()", replacingPendingRender: true) }
    func setHints(json: String) {
        let script = "window.copilote.setHints(\(json))"
        lastHintsScript = script; run(script, replacingPendingRender: false)
    }
    func scrollPage(_ direction: Int) { run("window.copilote.scrollPage(\(direction))", replacingPendingRender: false) }

    private func run(_ script: String, replacingPendingRender: Bool) {
        guard isReady else {
            if replacingPendingRender { pendingScripts.removeAll { $0.hasPrefix("window.copilote.render(") } }
            pendingScripts.append(script); return
        }
        evaluateJavaScript(script, completionHandler: nil)
    }
    func evaluateJavaScript(_ script: String) async throws -> Any {
        if #available(macOS 26, *), let modern = modernStorage as? ModernAnswerPage {
            return try await modern.page.callJavaScript("return (\(script));") ?? NSNull()
        }
        return try await legacy?.evaluateJavaScript(script) ?? NSNull()
    }
    func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)?) {
        Task { @MainActor in
            do { let result = try await evaluateJavaScript(script); completionHandler?(result, nil) }
            catch { completionHandler?(nil, error) }
        }
    }
    private func loadPage() {
        guard let page = Self.bundledPage else { return }
        if #available(macOS 26, *), let modern = modernStorage as? ModernAnswerPage { modern.load(page) }
        else { legacy?.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent()) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(Self.allows(action.request.url) ? .allow : .cancel)
    }
    static func allows(_ url: URL?) -> Bool {
        url?.isFileURL == true && url?.standardizedFileURL.path == bundledPage?.standardizedFileURL.path
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { recover() }
    func recover() {
        isReady = false
        pendingScripts = [lastHintsScript, lastRenderScript, "document.documentElement.style.zoom = \(pageZoom)"].compactMap { $0 }
        loadPage()
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            let scripts = pendingScripts; pendingScripts.removeAll()
            scripts.forEach { evaluateJavaScript($0, completionHandler: nil) }
        case "copy": if let text = body["text"] as? String { onCopy(text) }
        case "retry": onRetry?()
        case "openSource":
            if let text = body["url"] as? String, let url = URL(string: text), url.scheme == "https", url.host != nil, url.user == nil { NSWorkspace.shared.open(url) }
        default: break
        }
    }
}

private final class ResponseMessageBridge: NSObject, WKScriptMessageHandler {
    weak var owner: ResponseWebView?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

private final class QuietLegacyWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func quickLook(with event: NSEvent) {}
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) { menu.removeAllItems() }
}

@available(macOS 26, *)
@MainActor
private final class ModernAnswerPage {
    let page: WebPage
    private weak var bridge: ResponseMessageBridge?
    private var loading: Task<Void, Never>?
    init(bridge: ResponseMessageBridge) {
        self.bridge = bridge
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlinePredictions = false
        configuration.userContentController.add(bridge, name: "copilote")
        page = WebPage(configuration: configuration, navigationDecider: BundledNavigation(), dialogPresenter: NoWebDialogs())
    }
    func load(_ url: URL) {
        loading?.cancel()
        loading = Task { [weak self] in
            guard let self else { return }
            do { for try await _ in page.load(url) {} }
            catch WebPage.NavigationError.webContentProcessTerminated { bridge?.owner?.recover() }
            catch { /* A cancelled or denied navigation never opens external content. */ }
        }
    }
}

@available(macOS 26, *)
private struct BundledNavigation: WebPage.NavigationDeciding {
    func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        ResponseWebView.allows(action.request.url) ? .allow : .cancel
    }
}

@available(macOS 26, *)
private struct NoWebDialogs: WebPage.DialogPresenting {
    func handleJavaScriptAlert(message: String, initiatedBy frame: WebPage.FrameInfo) async {}
    func handleJavaScriptConfirm(message: String, initiatedBy frame: WebPage.FrameInfo) async -> WebPage.JavaScriptConfirmResult { .cancel }
    func handleJavaScriptPrompt(message: String, defaultText: String?, initiatedBy frame: WebPage.FrameInfo) async -> WebPage.JavaScriptPromptResult { .cancel }
    func handleFileInputPrompt(parameters: WKOpenPanelParameters, initiatedBy frame: WebPage.FrameInfo) async -> WebPage.FileInputPromptResult { .cancel }
}
