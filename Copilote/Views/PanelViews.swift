import AppKit
import CopiloteKit
import SwiftUI

// The panel's step-4 pieces, as plain views of data (shared with copilote-render).

/// The topic cases, newest first.
struct CasesList: View {
    let topics: [Topic]
    /// "⌥1"… per case, as configured.
    let keys: [String]
    var answeringID: String?
    var selectedID: String?
    var answers: [String: String] = [:]
    var onAnswer: (Int) -> Void = { _ in }
    var onPin: (Int) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                CaseRow(
                    topic: topic, keys: keys.indices.contains(index) ? keys[index] : "", isAnswering: answeringID == topic.id,
                    isSelected: selectedID == topic.id, answerPreview: answers[topic.id], onAnswer: { onAnswer(index) }, onPin: { onPin(index) }
                )
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(FicheStyle.motion(reduceMotion), value: topics.map(\.id))
    }
}

struct CaseRow: View {
    let topic: Topic
    let keys: String
    let isAnswering: Bool
    var isSelected = false
    var answerPreview: String?
    let onAnswer: () -> Void
    let onPin: () -> Void
    /// Brief highlight when the topic continues (a new version arrives).
    @State private var highlight = 0.0
    private static let pinWidth: CGFloat = 16
    /// Fits "10:42 PM" too.
    private static let timeWidth: CGFloat = 48

    var body: some View {
        Button(action: onAnswer) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(keys)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .leading)
                // Shown from keywords at once; the model's title fades in over it, in place.
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(topic.isProvisional ? .secondary : .primary)
                        .lineLimit(2)
                    if let answerPreview, !answerPreview.isEmpty {
                        Text(answerPreview.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room for the pin toggle laid over the row (outside the button).
                Color.clear.frame(width: Self.pinWidth, height: 1)
                Text(topic.updatedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: Self.timeWidth, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            // The case being answered (or chosen) is tinted as a whole: read at a glance, no side stripe.
            // An update shows over the tint too.
            .background(
                FicheStyle.accent.opacity((isAnswering || isSelected ? 0.14 : 0) + highlight),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(CaseButtonStyle(isPinned: topic.isPinned))
        // A visible toggle, not a context menu: a context menu is a system window, seen in shares.
        .overlay(alignment: .topTrailing) {
            Button(action: onPin) {
                Image(systemName: topic.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9.5))
                    .foregroundStyle(topic.isPinned ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .frame(width: Self.pinWidth, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // On the first line, next to the time (a title can take two lines).
            .padding(.top, 4)
            .padding(.trailing, 10 + Self.timeWidth + 8)
            // VoiceOver: the row's « Épingler » action below.
            .accessibilityHidden(true)
        }
        .onChange(of: topic.version) {
            // Once, softly: the case changed, nothing to chase.
            highlight = 0.1
            withAnimation(.easeOut(duration: 0.9)) { highlight = 0 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isAnswering ? Copy.Direct.answerShown : topic.isProvisional ? Copy.Direct.provisional : "")
        .accessibilityAddTraits(isAnswering || isSelected ? .isSelected : [])
        .accessibilityHint("Open this subject’s answer")
        .accessibilityAction(named: topic.isPinned ? Copy.Panel.unpin : Copy.Panel.pin, onPin)
    }
}

/// Lighter than the panel's material: the cases are what you act on. Feedback on press.
struct CaseButtonStyle: ButtonStyle {
    let isPinned: Bool

    func makeBody(configuration: Configuration) -> some View {
        CaseButtonBody(label: configuration.label, isPressed: configuration.isPressed, isPinned: isPinned)
    }
}

private struct CaseButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isPinned: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        label
            .background(Color.white.opacity(isPressed ? 0.15 : 0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(edge, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var edge: Color {
        FicheStyle.edge(Color.white.opacity(isPinned ? 0.22 : 0.06), contrast: contrast, emphasized: isPinned)
    }
}

/// Répondre · Que dire · Questions · Notes, on the chosen case or on the last phrases.
struct ActionBar: View {
    let target: String?
    let included: Int
    let total: Int
    var isContextOpen = false
    var onAction: (AssistAction) -> Void = { _ in }
    var onClearTarget: () -> Void = {}
    var onContext: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The icons go first when the panel is made narrow.
            ViewThatFits(in: .horizontal) {
                actions([.answer, .whatToSay, .questions, .notes])
                VStack(alignment: .leading, spacing: 4) {
                    actions([.answer, .whatToSay])
                    actions([.questions, .notes])
                }
            }
            HStack(spacing: 4) {
                Text(Copy.Panel.target(target)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if target != nil {
                    Button(action: onClearTarget) { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .overlayHint(Copy.Panel.clearTarget)
                        .accessibilityLabel(Copy.Panel.clearTarget)
                }
                Spacer(minLength: 8)
                Button(action: onContext) {
                    HStack(spacing: 4) {
                        Text(Copy.Panel.context(included, of: total)).font(.system(size: 11, weight: .medium).monospacedDigit())
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(isContextOpen ? 180 : 0))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actions(_ choices: [AssistAction]) -> some View {
        HStack(spacing: 6) {
            ForEach(choices, id: \.self) { action in
                Button { onAction(action) } label: {
                    Text(shortName(action)).font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .overlayHint(Copy.Panel.actionHint(action))
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }
    private func shortName(_ action: AssistAction) -> String {
        switch action {
        case .answer: return "Answer"
        case .whatToSay: return "Short version"
        case .questions: return "Follow-ups"
        case .notes: return "Notes"
        }
    }

}

/// Each piece of context with its switch: what is off is not sent.
struct ContextDrawer: View {
    let items: [ContextItem]
    var onToggle: (String) -> Void = { _ in }
    var onIncludeAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                Text(Copy.Panel.contextEmpty).font(.system(size: 11.5)).foregroundStyle(.secondary)
            } else {
                HStack {
                    Spacer()
                    Button(Copy.Panel.includeAll, action: onIncludeAll).buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(FicheStyle.accent)
                        .disabled(items.allSatisfy(\.isIncluded))
                }
                group(Copy.Panel.transcript, .line)
                group(Copy.Panel.captures, .capture)
                group(Copy.Panel.base, .extract)
            }
        }
        .ficheCard(padding: 10)
    }

    @ViewBuilder
    private func group(_ title: String, _ kind: ContextItem.Kind) -> some View {
        let pieces = items.filter { $0.kind == kind }
        if !pieces.isEmpty {
            Text(title.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            ForEach(pieces) { item in
                Toggle(isOn: Binding(get: { item.isIncluded }, set: { _ in onToggle(item.id) })) {
                    Text(item.label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(item.isIncluded ? .primary : .secondary)
                        .strikethrough(!item.isIncluded, color: .secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(FicheStyle.accent)
            }
        }
    }
}

/// An opinion question whose subject is not in avis.md: Copilote gives angles, never an opinion,
/// and offers to add the subject (an empty section, to fill in after the meeting).
struct MissingOpinionCard: View {
    let subject: String
    var readOnly = false
    var isAdded = false
    var failure: String?
    var onAdd: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble").font(.system(size: 11, weight: .semibold)).foregroundStyle(FicheStyle.accent)
                Text(Copy.Direct.notInBase.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(FicheStyle.accent)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Close")
            }
            Text(Copy.Direct.notInBaseBody(subject))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if readOnly {
                Text("Brain is read-only. Add an explicit opinion to an avis.md note in Obsidian.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            } else if isAdded {
                Label(Copy.Direct.added, systemImage: "checkmark").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
            } else {
                Button(action: onAdd) {
                    Label(Copy.Direct.addToOpinions, systemImage: "plus").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(PillButtonStyle())
            }
            if let failure {
                Text(failure).font(.system(size: 11)).foregroundStyle(FicheStyle.danger)
            }
        }
        .ficheCard(padding: 10)
    }
}

/// "Que dire": the sentence to read out, big, with its likely follow-ups.
struct WhatToSayCard: View {
    let say: WhatToSay
    var onCopy: () -> Void = {}
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Copy.Panel.say.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(FicheStyle.accent)
                Spacer()
                Button(copied ? Copy.Panel.copied : Copy.Panel.copySentence) {
                    onCopy()
                    copied = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FicheStyle.accent)
            }
            Text(say.sentence)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !say.followUps.isEmpty {
                Text(Copy.Panel.followUps).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
                ForEach(Array(say.followUps.enumerated()), id: \.element.question) { index, followUp in
                    if index > 0 { Divider().opacity(0.5) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("« \(followUp.question) »").font(.system(size: 12, weight: .medium))
                        if let reply = followUp.reply {
                            Text("→ \(reply)").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .ficheCard()
    }
}

/// "Demander" at rest: one line that turns into the field when clicked.
struct AskPrompt: View {
    var onStart: () -> Void = {}

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor").font(.system(size: 11)).foregroundStyle(FicheStyle.accent)
                Text(Copy.Panel.askPlaceholder).font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AskBoundsMarker())
        .overlayHint(Copy.Pill.askHelp)
    }
}

/// "Demander": a one-line field; the panel takes the keyboard only while it is focused.
struct AskField: View {
    @Binding var text: String
    var wantsFocus = true
    var onCancel: () -> Void = {}
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor").font(.system(size: 11)).foregroundStyle(FicheStyle.accent)
                field
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(FicheStyle.accent.opacity(0.45), lineWidth: 1))
            Text(Copy.Panel.askHint).font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 2)
        }
    }

    private var field: some View {
        NativeAskField(text: $text, wantsFocus: wantsFocus, onCancel: onCancel, onSubmit: onSubmit)
    }
}

/// Only this native cell accepts our quiet field editor. SwiftUI's private text cells require
/// their own editor subclass, so substituting an NSTextView there crashes during focus.
final class OverlayAskTextField: NSTextField {
    var wantsFocus = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFocus()
    }
    private var focusRequest = 0
    func requestFocus() {
        focusRequest += 1
        focusWhenReady(generation: focusRequest, attempts: 6)
    }
    private func focusWhenReady(generation: Int, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempts == 6 ? 0 : 0.04)) { [weak self] in
            guard let self, self.wantsFocus, self.focusRequest == generation, self.currentEditor() == nil else { return }
            if self.window?.isKeyWindow == true { self.window?.makeFirstResponder(self) }
            if self.currentEditor() == nil, attempts > 1 {
                self.focusWhenReady(generation: generation, attempts: attempts - 1)
            }
        }
    }

}

private struct NativeAskField: NSViewRepresentable {
    @Binding var text: String
    var wantsFocus: Bool
    var onCancel: () -> Void
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> OverlayAskTextField {
        let field = OverlayAskTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 12.5)
        field.textColor = .labelColor
        field.placeholderString = Copy.Panel.askPlaceholder
        field.focusRingType = .none
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: OverlayAskTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.wantsFocus = wantsFocus
        if wantsFocus { field.requestFocus() }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeAskField
        init(_ parent: NativeAskField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            if command == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if command == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

/// A non-interactive native anchor for own-window click verification.
private struct AskBoundsMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {}
    final class Marker: NSView {
        override init(frame: NSRect) { super.init(frame: frame); identifier = NSUserInterfaceItemIdentifier("CopiloteAskBounds") }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
