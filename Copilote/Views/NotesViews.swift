import AppKit
import CopiloteKit
import SwiftUI

/// The end-of-meeting notes: five sections, actions to tick, the follow-up email, and the
/// optional self-review. Each point shows its quote of the transcript on hover. Data only
/// (shared with copilote-render and the history).
struct MeetingNotesCard: View {
    let report: MeetingReport
    var onCopyNotes: () -> Void = {}
    var onCopyEmail: () -> Void = {}
    /// The e-mail's text can be selected in the main window only: on the overlay, a right click on
    /// selected text opens a system menu, visible in a screen share (« Copy l'e-mail » is there).
    var allowsSelection = false
    @State private var done: Set<String> = []
    @State private var quoted: Set<String> = []

    private func toggleQuote(_ text: String) {
        if quoted.contains(text) { quoted.remove(text) } else { quoted.insert(text) }
    }

    private var notes: MeetingNotes { report.notes }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.Notes.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(FicheStyle.accent)
                    Text(notes.title.isEmpty ? Copy.Notes.title : notes.title).font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                }
                Spacer()
                Button(Copy.Notes.copyNotes, action: onCopyNotes).buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(FicheStyle.accent)
            }
            NotesSection(title: "Key points", items: notes.keyPoints.map { ($0.text, $0.evidence) })
            NotesSection(title: "Decisions", items: notes.decisions.map { ($0.text, $0.evidence) })
            VStack(alignment: .leading, spacing: 4) {
                NotesHeading(title: "Actions")
                if notes.actions.isEmpty { NotesNothing() }
                ForEach(notes.actions, id: \.text) { action in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Toggle(isOn: Binding(get: { done.contains(action.text) }, set: { if $0 { done.insert(action.text) } else { done.remove(action.text) } })) {
                                Text(action.owner.map { "\(action.text) · \($0)" } ?? action.text)
                                    .font(.system(size: 12))
                                    .strikethrough(done.contains(action.text), color: .secondary)
                            }
                            .toggleStyle(.checkbox)
                            QuoteButton(isOpen: quoted.contains(action.text)) { toggleQuote(action.text) }
                        }
                        if quoted.contains(action.text) { QuoteLine(evidence: action.evidence) }
                    }
                }
            }
            NotesSection(title: "Questions ouvertes", items: notes.openQuestions.map { ($0.text, $0.evidence) })
            NotesSection(title: "Next steps", items: notes.nextSteps.map { ($0.text, $0.evidence) })
            Text(Copy.Notes.quoted).font(.system(size: 10.5)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    NotesHeading(title: Copy.Notes.email)
                    Spacer()
                    Button(Copy.Notes.copyEmail, action: onCopyEmail).buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(FicheStyle.accent)
                }
                (Text("\(Copy.Notes.subject) ").fontWeight(.semibold) + Text(report.email.subject)).font(.system(size: 12))
                emailBody
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let stats = report.stats {
                VStack(alignment: .leading, spacing: 3) {
                    NotesHeading(title: Copy.Notes.diction)
                    Text(stats.summary).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Text(Copy.Notes.dictionHelp).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let review = report.review { SelfReviewSection(review: review) }
        }
        .ficheCard()
    }
}

extension MeetingNotesCard {
    @ViewBuilder
    private var emailBody: some View {
        let text = Text(report.email.body).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if allowsSelection { text.textSelection(.enabled) } else { text }
    }
}

/// The self-review alone (notes switched off) or under the notes.
struct SelfReviewSection: View {
    let review: SelfReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotesHeading(title: Copy.Notes.review)
            NotesSection(title: "Strengths", items: review.strengths.map { ($0, nil) })
            NotesSection(title: "To improve", items: review.improvements.map { ($0, nil) })
            NotesSection(title: "Formulations plus claires", items: review.rephrasings.map { ("« \($0.original) » → \($0.better)", nil) })
        }
    }
}

private struct NotesHeading: View {
    let title: String

    var body: some View {
        Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
    }
}

private struct NotesNothing: View {
    var body: some View {
        Text("Rien.").font(.system(size: 12)).foregroundStyle(.secondary)
    }
}

/// A titled list; a point with its quote shows it on a click, inside the card (a tooltip would be
/// a system window, visible in a screen share).
private struct NotesSection: View {
    let title: String
    let items: [(text: String, evidence: String?)]
    @State private var open: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            NotesHeading(title: title)
            if items.isEmpty { NotesNothing() }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(item.text).fixedSize(horizontal: false, vertical: true)
                        if item.evidence != nil {
                            QuoteButton(isOpen: open.contains(index)) {
                                if open.contains(index) { open.remove(index) } else { open.insert(index) }
                            }
                        }
                    }
                    if open.contains(index), let evidence = item.evidence { QuoteLine(evidence: evidence) }
                }
                .font(.system(size: 12))
            }
        }
    }
}

/// Shows or hides the point's quote of the transcript.
private struct QuoteButton: View {
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOpen ? "quote.bubble.fill" : "quote.bubble").font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(isOpen ? Copy.Notes.hideQuote : Copy.Notes.showQuote)
    }
}

private struct QuoteLine: View {
    let evidence: String

    var body: some View {
        Text("« \(evidence) »")
            .font(.system(size: 11.5))
            .italic()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 12)
    }
}

/// Notes on their way, or why there are none.
struct NotesStatusView: View {
    let text: String
    var isWorking = false

    var body: some View {
        HStack(spacing: 8) {
            if isWorking { ProgressView().controlSize(.small) }
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FicheStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
