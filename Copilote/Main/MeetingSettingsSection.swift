import CopiloteKit
import SwiftUI

/// Settings → Réunions: default mode, end-of-meeting notes, self-review, history, menu bar, tour.
/// Shared with copilote-render.
struct MeetingSettingsSection: View {
    @ObservedObject var settings: SettingsStore
    var onHistoryChange: () -> Void = {}
    var onMenuBarChange: () -> Void = {}
    var onTour: () -> Void = {}

    var body: some View {
        Section(Copy.Settings.section) {
            Picker(Copy.Settings.defaultMode, selection: $settings.defaultMode) {
                ForEach(MeetingMode.allCases, id: \.self) { Text($0.name).tag($0.rawValue) }
            }.pickerStyle(.radioGroup)
            Toggle(isOn: $settings.notesAtEnd) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.Settings.notesAtEnd)
                    Text(Copy.Settings.notesAtEndHelp).font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.selfReview) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.Settings.review)
                    Text(Copy.Settings.reviewHelp).font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: Binding(get: { settings.keepHistory }, set: { settings.keepHistory = $0; onHistoryChange() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.Settings.keepHistory)
                    Text(Copy.Settings.keepHistoryHelp).font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker(Copy.Settings.retention, selection: Binding(get: { settings.historyRetentionDays }, set: { settings.historyRetentionDays = $0; onHistoryChange() })) {
                ForEach(Copy.Settings.retentionChoices, id: \.days) { Text($0.label).tag($0.days) }
            }
            .pickerStyle(.radioGroup)
            .disabled(!settings.keepHistory)
            Button(Copy.Settings.tour, action: onTour)
        }
    }
}
