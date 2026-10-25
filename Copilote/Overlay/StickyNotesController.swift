import AppKit
import Combine
import CopiloteKit
import SwiftUI

@MainActor
final class StickyNotesController: ObservableObject {
    @Published private(set) var notes: [StickyNote]
    @Published private(set) var isVisible: Bool
    private let defaults: UserDefaults
    private let settings: SettingsStore
    private var panels: [UUID: OverlayPanel] = [:]
    private var observers: [NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var hiddenWithOverlay = false
    private var moving = false
    var windowNumbers: [Int] { panels.values.map(\.windowNumber) }
    var hasDeleted: Bool { notes.contains { $0.deletedAt != nil } }
    var includedContext: [String] { notes.filter { $0.deletedAt == nil && $0.includeInAI && !$0.text.isEmpty }.map(\.text) }

    init(settings: SettingsStore) {
        self.settings = settings; defaults = settings.defaults
        notes = defaults.data(forKey: "stickyNotesV1").flatMap { try? JSONDecoder().decode([StickyNote].self, from: $0) } ?? []
        isVisible = defaults.object(forKey: "stickyNotesVisible") as? Bool ?? true
        settings.$overlayOpacity.sink { [weak self] density in
            self?.panels.values.forEach { ($0.contentView as? FrostedSurface)?.density = density }
        }.store(in: &subscriptions)
        settings.$overlayBackground.sink { [weak self] mode in
            self?.panels.values.forEach { ($0.contentView as? FrostedSurface)?.backgroundMode = mode }
        }.store(in: &subscriptions)
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, !self.moving, let panel = notification.object as? OverlayPanel,
                          let id = self.panels.first(where: { $0.value === panel })?.key,
                          let i = self.notes.firstIndex(where: { $0.id == id }) else { return }
                    self.notes[i].frame = panel.frame; self.save()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreWindows() }
        })
    }

    func add() {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        let offset = CGFloat(notes.filter { $0.deletedAt == nil }.count % 6) * 26
        notes.append(StickyNote(frame: CGRect(x: screen.minX + 40 + offset, y: screen.maxY - 280 - offset, width: 280, height: 220)))
        isVisible = true; save(); restoreWindows()
    }
    func setText(_ text: String, for id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].text = text; save()
    }
    func setIncluded(_ included: Bool, for id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].includeInAI = included; save()
    }
    func togglePin(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].isPinned.toggle(); save()
    }
    func delete(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].deletedAt = Date(); panels[id]?.orderOut(nil); save()
    }
    func restoreLastDeleted() {
        guard let i = notes.indices.filter({ notes[$0].deletedAt != nil }).max(by: { notes[$0].deletedAt! < notes[$1].deletedAt! }) else { return }
        notes[i].deletedAt = nil; isVisible = true; save(); restoreWindows()
    }
    func toggleVisible() { isVisible.toggle(); save(); restoreWindows() }
    func setHiddenWithOverlay(_ hidden: Bool) { hiddenWithOverlay = hidden; restoreWindows() }
    func restoreWindows() {
        moving = true
        defer { moving = false }
        for i in notes.indices where notes[i].deletedAt == nil {
            let note = notes[i]
            let panel = panels[note.id] ?? makePanel(note)
            notes[i].frame = StickyNote.fitted(note.frame, screens: NSScreen.screens.map(\.visibleFrame))
            panel.setFrame(notes[i].frame, display: false)
            if isVisible && !hiddenWithOverlay { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        }
        save()
    }
    func closeAll() { panels.values.forEach { $0.orderOut(nil) } }
    func isWindowVisible(_ id: UUID) -> Bool { panels[id]?.isVisible == true }
    func windowForDiagnostic(_ id: UUID) -> NSWindow? { DiagnosticRecette.isRequested ? panels[id] : nil }

    private func makePanel(_ note: StickyNote) -> OverlayPanel {
        let panel = OverlayPanel(size: note.frame.size)
        panel.title = "Personal note"
        panel.minSize = NSSize(width: 240, height: 180)
        panel.allowsKey = true
        let surface = FrostedSurface(); surface.density = settings.overlayOpacity; surface.backgroundMode = settings.overlayBackground
        panel.contentView = surface
        let host = FirstMouseHostingView(rootView: StickyNoteView(controller: self, id: note.id))
        host.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(host)
        NSLayoutConstraint.activate([host.topAnchor.constraint(equalTo: surface.topAnchor), host.bottomAnchor.constraint(equalTo: surface.bottomAnchor), host.leadingAnchor.constraint(equalTo: surface.leadingAnchor), host.trailingAnchor.constraint(equalTo: surface.trailingAnchor)])
        panels[note.id] = panel
        return panel
    }
    private func save() {
        if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: "stickyNotesV1") }
        defaults.set(isVisible, forKey: "stickyNotesVisible")
    }
}

struct StickyNotesBar: View {
    @ObservedObject var notes: StickyNotesController
    var body: some View {
        HStack(spacing: 12) {
            Button("+ Personal note", action: notes.add)
            Button(notes.isVisible ? "Hide notes" : "Show notes", action: notes.toggleVisible)
            if notes.hasDeleted { Button("Restore deleted", action: notes.restoreLastDeleted) }
            Spacer()
        }.buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
    }
}

private struct StickyNoteView: View {
    @ObservedObject var controller: StickyNotesController
    let id: UUID
    var body: some View {
        if let note = controller.notes.first(where: { $0.id == id }) {
            VStack(spacing: 7) {
                HStack {
                    NoteDragHandle(locked: note.isPinned).frame(width: 28, height: 20)
                    Text("Personal note").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button(note.isPinned ? "Unpin" : "Pin") { controller.togglePin(id) }
                    Button("Delete") { controller.delete(id) }
                }.buttonStyle(.plain).font(.system(size: 10.5))
                StickyEditor(text: note.text, onChange: { controller.setText($0, for: id) })
                Toggle("Use as AI context", isOn: Binding(get: { note.includeInAI }, set: { controller.setIncluded($0, for: id) }))
                    .toggleStyle(.checkbox).font(.system(size: 10.5))
                Text(note.includeInAI ? "Included in future requests until unchecked" : "Private · saved only on this Mac")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
            }.padding(10).foregroundStyle(.white)
        }
    }
}
private struct NoteDragHandle: NSViewRepresentable {
    var locked: Bool
    func makeNSView(context: Context) -> Grip { Grip() }
    func updateNSView(_ view: Grip, context: Context) { view.locked = locked }
    final class Grip: NSView {
        var locked = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { if !locked { window?.performDrag(with: event) } }
        override func draw(_ dirtyRect: NSRect) { (locked ? "●" : "⠿").draw(at: NSPoint(x: 6, y: 2), withAttributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 14)]) }
    }
}
private struct StickyEditor: NSViewRepresentable {
    var text: String
    var onChange: (String) -> Void
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let editor = StickyTextView()
        editor.string = text; editor.onChange = onChange
        editor.drawsBackground = false; editor.textColor = .white; editor.insertionPointColor = .white
        editor.font = .systemFont(ofSize: 14); editor.isRichText = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false; editor.isAutomaticDataDetectionEnabled = false
        editor.displaysLinkToolTips = false; editor.inlinePredictionType = .no
        if #available(macOS 15.0, *) { editor.writingToolsBehavior = .none }
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? StickyTextView else { return }
        editor.onChange = onChange
        if editor.string != text { editor.string = text }
    }
}
final class StickyTextView: NSTextView {
    var onChange: (String) -> Void = { _ in }
    override func didChangeText() { super.didChangeText(); onChange(string) }
    override var isContinuousSpellCheckingEnabled: Bool { get { false } set {} }
    override var isGrammarCheckingEnabled: Bool { get { false } set {} }
    override var isAutomaticSpellingCorrectionEnabled: Bool { get { false } set {} }
    override var isAutomaticTextCompletionEnabled: Bool { get { false } set {} }
    override var isAutomaticTextReplacementEnabled: Bool { get { false } set {} }
    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func quickLook(with event: NSEvent) {}
    override func complete(_ sender: Any?) {}
    @objc func orderFrontCharacterPalette(_ sender: Any?) {}
    override func cancelOperation(_ sender: Any?) { window?.resignKey() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
