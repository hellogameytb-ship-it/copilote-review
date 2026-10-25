import AppKit
import SwiftUI
import KeyboardShortcuts

/// Captures keys in the existing settings panel. Conflicts are inline; no NSAlert or popup.
struct ProtectedShortcutRecorder: View {
    let label: String
    let name: KeyboardShortcuts.Name
    let onChange: () -> Void
    @State private var revision = 0
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                CaptureButton(name: name, revision: revision) { result in
                    message = result
                    revision += 1
                    onChange()
                }.frame(width: 140, height: 26)
                Button("Clear") {
                    KeyboardShortcuts.setShortcut(nil, for: name)
                    revision += 1; onChange()
                }.buttonStyle(.plain)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private struct CaptureButton: NSViewRepresentable {
        let name: KeyboardShortcuts.Name
        let revision: Int
        let onChange: (String) -> Void
        func makeNSView(context: Context) -> ShortcutCaptureButton { ShortcutCaptureButton() }
        func updateNSView(_ button: ShortcutCaptureButton, context: Context) {
            button.name = name; button.onChange = onChange
            if !button.recording { button.title = KeyboardShortcuts.getShortcut(for: name)?.description ?? "Record…" }
        }
        static func dismantleNSView(_ view: ShortcutCaptureButton, coordinator: ()) { view.finish() }
    }
}

@MainActor
final class ShortcutCaptureButton: NSButton {
    var name = KeyboardShortcuts.Name("unused")
    var onChange: (String) -> Void = { _ in }
    private(set) var recording = false
    private var enabledBefore: [KeyboardShortcuts.Name] = []
    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        identifier = NSUserInterfaceItemIdentifier("CopiloteShortcutRecorder")
        title = "Record…"
        target = self; action = #selector(begin)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc func begin() {
        guard !recording else { finish(); return }
        enabledBefore = ShortcutCatalog.all.map(\.name).filter { KeyboardShortcuts.isEnabled(for: $0) }
        recording = true
        window?.makeFirstResponder(self)
        KeyboardShortcuts.disable(ShortcutCatalog.all.map(\.name))
        title = "Press keys · Esc cancels"
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        if event.keyCode == 53 { finish(); return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard !modifiers.isEmpty, let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            onChange("Use Command, Control or Option with a key."); return
        }
        if shortcut.isTakenBySystem {
            onChange("This shortcut is reserved by macOS. Choose another combination."); return
        }
        if let duplicate = ShortcutCatalog.all.first(where: { $0.name != name && KeyboardShortcuts.getShortcut(for: $0.name) == shortcut }) {
            onChange("Already used for \(duplicate.label)."); return
        }
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        finish(); onChange("")
    }

    func finish() {
        guard recording else { return }
        recording = false
        KeyboardShortcuts.enable(enabledBefore)
        enabledBefore = []
        title = KeyboardShortcuts.getShortcut(for: name)?.description ?? "Record…"
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { finish() }; super.viewWillMove(toWindow: newWindow) }
}
