import AppKit
import CopiloteKit
import SwiftUI

/// Settings → Base: where the base is, what is indexed, and what a personal question does.
struct BaseSection: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var base: BaseController
    @State private var refused: String?

    var body: some View {
        Section("Brain") {
            Text("Browse folders inside Copilote after ending the listening session, including a paused session. Open in Finder leaves Copilote and may be visible in a screen share.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Folder") {
                HStack(spacing: 6) {
                    Text(abbreviated(settings.baseFolder)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Open in Finder") { NSWorkspace.shared.open(base.root) }
                    Button("Choose folder…") { Task { @MainActor in
                        guard let folder = await chooseFolder() else { return }
                        if let problem = BaseController.problem(withBaseFolder: folder) {
                            refused = problem
                        } else {
                            refused = nil
                            settings.baseFolder = folder.path
                            base.foldersChanged()
                        }
                    } }
                }
            }
            LabeledContent("Index") {
                HStack(spacing: 8) {
                    if base.status.isIndexing {
                        ProgressView().controlSize(.small)
                    }
                    Text(indexSummary).foregroundStyle(.secondary).monospacedDigit()
                    Button("Reindex", action: base.reindex).disabled(base.status.isIndexing)
                }
            }
            if let refused {
                Text(refused).font(.caption).foregroundStyle(.orange)
            }
            if let message = base.status.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if !base.isReadOnly {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Additional photo folders")
                    Spacer()
                    Button("Add folder…") { Task { @MainActor in
                        if let folder = await chooseFolder(), !settings.basePhotoFolders.contains(folder.path) {
                            settings.basePhotoFolders.append(folder.path)
                            base.foldersChanged()
                        }
                    } }
                }
                if settings.basePhotoFolders.isEmpty {
                    Text("Only the base’s photos/ folder is read by default. The Photos library is never scanned.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(settings.basePhotoFolders, id: \.self) { folder in
                    HStack {
                        Text(abbreviated(folder)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            settings.basePhotoFolders.removeAll { $0 == folder }
                            base.foldersChanged()
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(folder)")
                    }
                }
            }
            }
            Picker("Personal questions", selection: $settings.baseMode) {
                Text("Show source card").tag(PersonalRouter.Mode.show.rawValue)
                Text("Suggest source card").tag(PersonalRouter.Mode.suggest.rawValue)
                Text("Disabled (provider only)").tag(PersonalRouter.Mode.off.rawValue)
            }.pickerStyle(.radioGroup)
            if !base.isReadOnly {
            Toggle("Generate photo captions while indexing", isOn: $settings.basePhotoCaptions)
            Text("Search stays on your Mac. Showing source cards needs no network or model call. The provider can "
                + "generate a project diagram from a linked repository and, "
                + "if enabled, photo captions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Brain is read-only. Only Markdown notes are indexed; Obsidian configuration, attachments, symbolic links and detected credentials are excluded. Up to five relevant, sourced excerpts may accompany an answer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var indexSummary: String {
        var parts = ["\(base.status.items) items", "\(base.status.photos) photos"]
        if let date = base.status.lastIndexed {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() async -> URL? {
        do { refused = nil; return try await SystemDialogs.chooseFolder() }
        catch { refused = error.localizedDescription; return nil }
    }
}
