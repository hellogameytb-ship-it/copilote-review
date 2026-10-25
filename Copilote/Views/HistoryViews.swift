import AppKit
import CopiloteKit
import SwiftUI

/// The sessions kept on this Mac: search, list, and the one opened. Sessions kept before the
/// history was switched off stay readable, exportable and deletable.
struct HistoryBrowser: View {
    /// "Garder l'historique" is on.
    let isRecording: Bool
    let sessions: [SessionSummary]
    @Binding var query: String
    @Binding var selection: UUID?
    let opened: SessionRecord?
    var onExport: (SessionRecord) -> Void = { _ in }
    var onDelete: (SessionRecord) -> Void = { _ in }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField(Copy.History.search, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                    .disabled(!isRecording && sessions.isEmpty && query.isEmpty)
                if !isRecording, !sessions.isEmpty || !query.isEmpty {
                    Text(Copy.History.offKept).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                }
                if !isRecording, sessions.isEmpty, query.isEmpty {
                    empty(Copy.History.off)
                } else if sessions.isEmpty {
                    empty(query.isEmpty ? Copy.History.empty : Copy.History.noResult(query))
                } else {
                    List(sessions, selection: $selection) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text("\(SessionSummary.dateText(session.started)) · \(session.mode.name) · \(SessionSummary.durationText(session.duration))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(session.id)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 230, idealWidth: 260)

            Group {
                if let opened {
                    SessionDetail(record: opened, onExport: { onExport(opened) }, onDelete: { onDelete(opened) })
                } else {
                    empty(isRecording || !sessions.isEmpty ? Copy.History.pick() : Copy.History.off)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One session, opened: notes first, then cases, answers and transcript.
struct SessionDetail: View {
    let record: SessionRecord
    var onExport: () -> Void = {}
    var onDelete: () -> Void = {}
    @State private var confirmsDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.title).font(.title3.weight(.semibold))
                    Text("\(SessionSummary.dateText(record.started)) · \(record.mode.name) · \(SessionSummary.durationText(record.duration))")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(Copy.History.export, action: onExport)
                        Button(Copy.History.delete, role: .destructive) { confirmsDelete = true }
                    }
                    .padding(.top, 2)
                    Text("Export opens a file browser inside Copilote. End any listening session first, including a paused session, then click Export again.").font(.caption).foregroundStyle(.secondary)
                    if confirmsDelete {
                        Text(Copy.History.deleteMessage).font(.caption)
                        HStack {
                            Button(Copy.History.keep) { confirmsDelete = false }
                            Button(Copy.History.delete, role: .destructive) { confirmsDelete = false; onDelete() }
                        }
                    }
                }
                if let notes = record.notes, let email = record.email {
                    MeetingNotesCard(report: MeetingReport(notes: notes, email: email, review: record.review, stats: SpeechStats(transcript: record.transcript)), allowsSelection: true)
                }
                if !record.topics.isEmpty {
                    block(Copy.History.cases) {
                        ForEach(record.topics, id: \.title) { Text("• \($0.title)").font(.system(size: 12.5)) }
                    }
                }
                if !record.answers.isEmpty {
                    block(Copy.History.answers) {
                        ForEach(Array(record.answers.enumerated()), id: \.offset) { _, answer in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(answer.label).font(.system(size: 12, weight: .semibold))
                                Text(answer.markdown).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(8).textSelection(.enabled)
                            }
                        }
                    }
                }
                if !record.transcript.isEmpty {
                    block(Copy.History.transcript) {
                        ForEach(Array(record.transcript.enumerated()), id: \.offset) { _, line in
                            (Text("\(line.speaker.name)  ").fontWeight(.semibold).foregroundColor(line.speaker == .me ? FicheStyle.accent : .secondary)
                                + Text(line.text))
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

