import AppKit
import Combine
import CopiloteKit
import SwiftUI

/// The overlay's state for SwiftUI: folded pill, unfolded panel, hidden; typing in "Demander".
@MainActor
final class OverlayModel: ObservableObject {
    @Published fileprivate(set) var machine: OverlayMachine = {
        var state = OverlayMachine(); state.handle(.toggleVisibility); return state
    }()
    @Published var showsPrivacyHelp = false

    var isUnfolded: Bool { machine.presentation == .panel }
    var isTyping: Bool { machine.isTyping }
}

/// Owns the two floating panels, à la Cluely: the pill at the top of the screen and the panel
/// that unfolds under it. Placement per screen (⌘ + arrows, or drag the pill), appearance,
/// click-through, rendering commands.
@MainActor
final class OverlayController {
    let model = OverlayModel()
    private let pill = PillPanel()
    private let panel = OverlayPanel()
    private let header = OverlayHeaderView()
    private let webView = ResponseWebView()
    private let settings: SettingsStore

    /// Called with the new state (the arrows are grabbed only while the panel is unfolded).
    var onPresentationChange: ((OverlayMachine.Presentation) -> Void)?
    /// ⌘↩ while there is a case: answer it.
    var onAnswerLatestTopic: (() -> Void)?

    /// The capture must leave both panels out.
    var windowNumbers: [Int] { [pill.windowNumber, panel.windowNumber] }

    private var screen: NSScreen?
    private var panelSize: NSSize
    private var placement: OverlayPlacement
    private var hasPlacedWorkspace = false
    private var isPlacingWorkspace = false
    private var presentationArea: ScreenArea?
    private var savedExpandedGeometry: (pill: NSRect, panel: NSRect)?
    private(set) var diagnosticGeometry: [[String:String]] = []
    private func traceGeometry(_ event:String) {
        guard DiagnosticAnchorFixture.isRequested else { return }
        diagnosticGeometry.append(["event":event,"pill":NSStringFromRect(pill.frame),"panel":NSStringFromRect(panel.frame),"savedPill":savedExpandedGeometry.map { NSStringFromRect($0.pill) } ?? "nil","savedPanel":savedExpandedGeometry.map { NSStringFromRect($0.panel) } ?? "nil"])
    }
    private var savePlacement: DispatchWorkItem?
    private(set) var placementWrites = 0
    /// The app in front when typing started: it gets the keyboard back.
    private var previousApp: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []

    private(set) var isClickThrough = false {
        didSet {
            panel.ignoresMouseEvents = isClickThrough
            header.setClickThrough(isClickThrough)
        }
    }

    init(settings: SettingsStore) {
        self.settings = settings
        StealthConfirmationController.register(pill, source:.pill)
        placement = settings.placement
        let saved = settings.defaults.string(forKey: "panelSize").map(NSSizeFromString) ?? .zero
        panelSize = saved.width >= 340 && saved.height >= 180 ? saved : OverlayPanel.defaultSize
        panel.minSize = NSSize(width: 420, height: 540)
        panelSize = NSSize(width: max(420, panelSize.width), height: max(540, panelSize.height))
        panel.setContentSize(panelSize)
        observers.append(NotificationCenter.default.addObserver(forName: .copilotePresentationSuspended, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })

        let material = Self.material()
        panel.contentView = material
        header.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 10
        webView.layer?.cornerCurve = .continuous
        webView.layer?.masksToBounds = true
        material.addSubview(header)
        material.addSubview(webView)
        layoutReadingAreaOnly(in: material)

        let pillMaterial = Self.material()
        pillMaterial.isCapsule = true
        pillMaterial.wantsLayer = true
        pillMaterial.layer?.cornerRadius = PillPanel.size.height / 2
        pillMaterial.layer?.masksToBounds = true
        pill.contentView = pillMaterial

        // Density affects only the native background. Text and controls remain fully opaque.
        settings.$overlayOpacity.removeDuplicates().sink { [pill, panel] opacity in
            (pill.contentView as? FrostedSurface)?.density = opacity
            (panel.contentView as? FrostedSurface)?.density = opacity
        }.store(in: &subscriptions)
        settings.$overlayBackground.removeDuplicates().sink { [pill, panel] mode in
            (pill.contentView as? FrostedSurface)?.backgroundMode = mode
            (panel.contentView as? FrostedSurface)?.backgroundMode = mode
        }.store(in: &subscriptions)
        settings.$answerTextScale.removeDuplicates().sink { [webView] scale in webView.pageZoom = scale }.store(in: &subscriptions)

        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelResized() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: Notification.Name("CopiloteWorkspaceDrag"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let event = note.object as? NSEvent, event.windowNumber == self.pill.windowNumber else { return }
                self.pill.performWorkspaceDrag(with: event)
            }
        })
        panel.isMovable = false // The header delegates to the root; no independent titlebar drag.
        panel.workspaceRoot = pill
        pill.onWorkspaceDragBegan = { [weak self] in self?.onPlaced?() }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: pill, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.landDraggedWorkspace() }
        })
        // Clicked back into the call while typing: typing is over, the keyboard is already theirs.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelLostKeyboard() }
        })
    }

    var isVisible: Bool { pill.isVisible }

    /// The overlay's surface: the HUD material, with a dark veil under the content so the text
    /// stays legible in front of a white page as in front of a dark one.
    static func material() -> FrostedSurface {
        FrostedSurface()
    }

    /// A small panel's surface (the tour, the ⚙ menu): the material, rounded, with `host` filling it.
    static func surface(hosting host: NSView, cornerRadius: CGFloat) -> FrostedSurface {
        let material = material()
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: material.topAnchor),
            host.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        return material
    }

    /// The pill's controls and the panel's body (step 2-4 content).
    func attach(panelBody: some View, pillBody: some View) {
        if let material = panel.contentView {
            webView.removeFromSuperview()
            let body = FirstMouseHostingView(rootView: AnyView(panelBody))
            body.sizingOptions = []
            body.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(body)
            NSLayoutConstraint.deactivate(layoutConstraints)
            layoutConstraints = [
                body.topAnchor.constraint(equalTo: header.bottomAnchor),
                body.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                body.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                body.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ] + headerConstraints(in: material)
            NSLayoutConstraint.activate(layoutConstraints)
        }
        if let material = pill.contentView {
            let body = FirstMouseHostingView(rootView: AnyView(pillBody))
            body.sizingOptions = []
            body.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(body)
            NSLayoutConstraint.activate([
                body.topAnchor.constraint(equalTo: material.topAnchor),
                body.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                body.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                body.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
        }
    }

    /// The reading area inside the panel's SwiftUI body.
    var readingArea: NSView { webView }

    private var layoutConstraints: [NSLayoutConstraint] = []

    private func layoutReadingAreaOnly(in material: NSView) {
        layoutConstraints = headerConstraints(in: material) + [
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 6),
            webView.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -6),
            webView.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -6),
        ]
        NSLayoutConstraint.activate(layoutConstraints)
    }

    private func headerConstraints(in material: NSView) -> [NSLayoutConstraint] {
        [
            header.topAnchor.constraint(equalTo: material.topAnchor),
            header.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 34),
        ]
    }

    func setListening(_ isListening: Bool) {
        header.setListening(isListening)
    }

    // MARK: States

    /// Initial explicit presentation uses the saved placement on the cursor's screen.
    func start() {
        present()
    }

    /// Reopening keeps the native workspace anchor; only the first presentation chooses a screen.
    func present() {
        guard WindowPrivacy.presentationAuthorized else { return }
        if let reason = WindowPrivacy.takeBlockReason() { header.setStatus(reason, tone: .failed) }
        if !hasPlacedWorkspace { screen = Self.screenUnderCursor() }
        if model.machine.presentation == .hidden { handle(.toggleVisibility) }
        handle(.answerStarted)
        pill.orderFrontRegardless()
        if model.isUnfolded { panel.orderFrontRegardless() }
    }

    /// Where the pill is, for what hangs under it (the tour).
    var pillFrame: NSRect { pill.frame }

    /// A rect in the pill's SwiftUI coordinates (top-left origin) on the screen (the ⚙ button).
    func screenRect(fromPill rect: CGRect) -> CGRect {
        CGRect(x: pill.frame.minX + rect.minX, y: pill.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
    /// The pill moved (dragged, placed, recentred): the tour follows it.
    var onPlaced: (() -> Void)?

    private func goHome() {
        guard let area else { return }
        placement.goHome(on: area)
    }

    /// Hide immediately and restore at the same native anchor.
    func toggle() {
        if model.machine.presentation == .hidden { present() } else { hide() }
    }

    func hide() {
        if model.isUnfolded { savedExpandedGeometry = (pill.frame, panel.frame) }
        WindowPrivacy.suspend()
        if model.machine.presentation != .hidden { handle(.toggleVisibility) }
    }

    func pillClicked() {
        handle(.pillClicked)
    }

    /// ⌘↩.
    func assist(hasTopic: Bool) {
        handle(.assist(hasTopic: hasTopic))
    }

    /// The user asked for something (a shortcut, a click): show it, even after ⌘\.
    func reveal() {
        if model.machine.presentation == .hidden { handle(.toggleVisibility) }
        handle(.answerStarted)
    }

    /// An answer drafted by itself: the pill unfolds; hidden by ⌘\, the overlay stays hidden.
    func showAutomatic() {
        handle(.answerStarted)
    }

    func startTyping() {
        handle(.startTyping)
    }

    func endTyping() {
        handle(.endTyping)
    }

    private func handle(_ event: OverlayMachine.Event) {
        guard WindowPrivacy.presentationAuthorized || event == .toggleVisibility || event == .endTyping else { return }
        let before = model.machine.presentation
        let effects = model.machine.handle(event)
        if !hasPlacedWorkspace, before == .hidden, model.machine.presentation != .hidden { screen = Self.screenUnderCursor() }
        for effect in effects {
            switch effect {
            case .answerLatestTopic: onAnswerLatestTopic?()
            case .takeKeyboard: break // The panel must be visible first.
            case .giveKeyboardBack: giveKeyboardBack()
            }
        }
        apply(from: before)
        if effects.contains(.takeKeyboard) { takeKeyboard() }
    }

    // MARK: Keyboard ("Demander")

    private func takeKeyboard() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        panel.allowsKey = true
        panel.makeKey()
    }

    private func giveKeyboardBack() {
        panel.allowsKey = false
        if panel.isKeyWindow {
            // A panel can't hand the keyboard over by itself: out and back in, it is no longer key.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        // AppKit restores the active app's keyboard when this non-activating panel resigns.
        // Never queue another app activation: it can arrive after the next Ask has started.
        previousApp = nil
    }

    private func panelLostKeyboard() {
        guard model.isTyping, !panel.isKeyWindow else { return }
        previousApp = nil
        panel.allowsKey = false
        _ = model.machine.handle(.endTyping)
    }

    // MARK: Placement

    /// ⌘ + arrows: a step on this screen, remembered for it; already against the edge, on to the
    /// screen on that side (where the block was left there).
    func move(_ direction: OverlayPlacement.Direction) {
        guard let area else { return }
        if hasPlacedWorkspace { placement.remember(pillFrame: pill.frame, on: area) }
        let screens = NSScreen.screens.map { (screen: $0, area: Self.area($0)) }
        let landed = placement.moveWorkspace(direction, pillSize: PillPanel.size, panelSize: panelSize, on: area, among: screens.map(\.area))
        if landed.id != area.id { screen = screens.first { $0.area.id == landed.id }?.screen }
        place()
        persistPlacementSoon()
    }

    /// ⌥⌘= / ⌥⌘-: the answer's text a step bigger or smaller, kept.
    func changeTextSize(by steps: Int) {
        settings.answerTextScale = TextScale.stepped(from: settings.answerTextScale, by: steps)
    }

    private var area: ScreenArea? {
        (screen ?? Self.screenUnderCursor()).map(Self.area)
    }

    private static func area(_ screen: NSScreen) -> ScreenArea {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
        return ScreenArea(id: number, visibleFrame: screen.visibleFrame)
    }

    private static func screenUnderCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private var frames: (pill: NSRect, panel: NSRect)? {
        guard let area else { return nil }
        return placement.workspaceFrames(pillSize: PillPanel.size, panelSize: panelSize, on: area)
    }

    private func place() {
        guard let frames else { return }
        isPlacingWorkspace = true
        defer { isPlacingWorkspace = false }
        // AppKit moves the child with its parent in one native window group. No easing queues
        // on key repeat, no SwiftUI publications or preference writes during a drag.
        pill.setFrame(frames.pill, display: false)
        if panel.isVisible { panel.setFrame(frames.panel, display: false) }
        hasPlacedWorkspace = true
        if let area { placement.remember(pillFrame: pill.frame, on: area); presentationArea = area }
        onPlaced?()
    }

    private func panelResized() {
        panelSize = panel.frame.size
        settings.defaults.set(NSStringFromSize(panelSize), forKey: "panelSize")
        if let area {
            let fitted = OverlayPlacement.anchoredWorkspaceFrames(pillFrame: pill.frame, panelSize: panelSize, on: area)
            panel.setFrame(fitted.panel, display: false)
        }
        persistPlacementSoon()
    }

    func landDraggedWorkspace() {
        guard hasPlacedWorkspace, !isPlacingWorkspace else { return }
        screen = screenContainingAnchor() ?? screen
        if let area { placement.remember(pillFrame: pill.frame, on: area) }
        // Observe the native root; never move it back to a previously saved offset.
        onPlaced?()
        persistPlacementSoon()
    }

    private func screenContainingAnchor() -> NSScreen? {
        NSScreen.screens.max {
            let a = $0.frame.intersection(pill.frame), b = $1.frame.intersection(pill.frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
    }

    private func persistPlacementSoon() {
        savePlacement?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushPlacement() }
        savePlacement = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func flushPlacement() {
        savePlacement?.cancel(); savePlacement = nil
        if hasPlacedWorkspace, let area { placement.remember(pillFrame: pill.frame, on: area) }
        guard settings.placement != placement else { return }
        settings.placement = placement
        placementWrites += 1
    }

    /// The pill's menu: back to the top centre of this screen.
    func recenter() {
        goHome()
        place()
        persistPlacementSoon()
    }

    // MARK: Showing

    /// Show or hide the native window group without queuing geometry animations.
    private func apply(from before: OverlayMachine.Presentation) {
        traceGeometry("apply from \(before) to \(model.machine.presentation)")
        if DiagnosticRecette.isRequested && ProcessInfo.processInfo.arguments.contains("-RecetteProfileOnly") { return }
        let now = model.machine.presentation
        if now != .hidden, !WindowPrivacy.canPresent(pill) || !WindowPrivacy.canPresent(panel) { return }
        switch now {
        case .hidden:
            if before == .panel { savedExpandedGeometry = (pill.frame, panel.frame) }
            pill.removeChildWindow(panel)
            panel.orderOut(nil)
            pill.orderOut(nil)
        case .pill, .panel:
            if !hasPlacedWorkspace { place() }
            if let current = screen, !NSScreen.screens.contains(where: { Self.area($0).id == Self.area(current).id }) {
                screen = screenContainingAnchor()
            }
            if let actual = NSScreen.screens.first(where: { $0.visibleFrame.contains(pill.frame) }) { screen = actual }
            guard let area else { return }
            let frames = OverlayPlacement.anchoredWorkspaceFrames(pillFrame: pill.frame, panelSize: panelSize, on: area)
            // Only invalid screen geometry permits an automatic correction of the root.
            if frames.pill != pill.frame { pill.setFrame(frames.pill, display: false) }
            let screenChanged = presentationArea != area
            let needsScreenRepair = screenChanged && !area.visibleFrame.contains(panel.frame)
            presentationArea = area
            placement.remember(pillFrame: pill.frame, on: area)
            pill.orderFrontRegardless()
            if now == .panel, before != .panel || panel.parent !== pill || needsScreenRepair {
                let preserved = savedExpandedGeometry.flatMap { saved in
                    !needsScreenRepair && saved.pill == pill.frame ? saved.panel : nil
                }
                unfold(to: preserved ?? frames.panel)
            } else if now == .panel {
                panel.orderFrontRegardless()
            } else if now == .pill, panel.parent === pill || panel.isVisible {
                fold()
            }
        }
        onPresentationChange?(now)
    }

    private func unfold(to target: NSRect) {
        traceGeometry("unfold to \(NSStringFromRect(target))")
        panel.alphaValue = 1
        if panel.parent !== pill { pill.addChildWindow(panel, ordered: .above) }
        // Reattaching can restore an old native child offset. Apply the chosen frame AFTER it.
        panel.setFrame(target, display: true)
        panel.orderFrontRegardless()
        traceGeometry("unfold done")
    }

    private func fold() {
        if panel.parent === pill { savedExpandedGeometry = (pill.frame, panel.frame) }
        pill.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func toggleClickThrough() {
        isClickThrough.toggle()
    }

    // MARK: Content

    func setStatus(_ text: String, tone: OverlayHeaderView.Tone) {
        header.setStatus(text, tone: tone)
    }

    func setCounter(_ text: String) {
        header.setCounter(text)
    }

    func render(payloadJSON: String) {
        webView.render(payloadJSON: payloadJSON)
    }

    /// « Réessayer » under a failed answer.
    var onRetry: (() -> Void)? {
        get { webView.onRetry }
        set { webView.onRetry = newValue }
    }

    func resetAnswer() {
        webView.reset()
    }

    func setHints(json: String) {
        webView.setHints(json: json)
    }

    func scroll(_ direction: Int) {
        webView.scrollPage(direction)
    }
}
