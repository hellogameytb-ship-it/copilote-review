import CopiloteKit
import SwiftUI

/// Settings → Réponses: standing instructions, language, text size. Shared with copilote-render.
struct AnswerSettingsSection: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Section(Copy.Settings.answersSection) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Copy.Settings.instructions)
                TextEditor(text: $settings.answerInstructions)
                    .font(.body)
                    .frame(minHeight: 64, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                    .accessibilityLabel(Copy.Settings.instructions)
                Text(Copy.Settings.instructionsHelp).font(.caption).foregroundStyle(.secondary)
            }
            Picker(Copy.Settings.language, selection: $settings.answerLanguage) {
                ForEach(AnswerPreferences.Language.allCases, id: \.self) { Text($0.name).tag($0.rawValue) }
            }
            PercentSlider(label: Copy.Settings.textSize, value: $settings.answerTextScale, range: TextScale.range, step: TextScale.step)
        }
        Section(Copy.Settings.overlaySection) {
            Picker("Background", selection: $settings.overlayBackground) {
                ForEach(OverlayBackgroundMode.allCases, id: \.self) { Text($0.name).tag($0) }
            }.pickerStyle(.segmented)
            Text("System follows macOS accessibility. Translucent shows the background independently. Text always stays opaque.")
                .font(.caption).foregroundStyle(.secondary)
            PercentSlider(label: Copy.Settings.opacity, value: $settings.overlayOpacity, range: SettingsStore.opacityRange, step: 0.05)
        }
    }
}

/// A slider with its value as a percentage.
private struct PercentSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(Copy.Settings.percent(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            }
        }
    }
}
