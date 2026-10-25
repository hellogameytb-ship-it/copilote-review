import AppKit
import SwiftUI

/// Explicit, ordered screenshot collection. No capture happens until a button is pressed.
struct ScreenshotStackView: View {
    @ObservedObject var session: SessionController
    @State private var preview: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button("Capture screen", action: session.captureFullScreen)
                Button("Add region", action: session.captureRegion)
                Spacer(minLength: 0)
                if session.isAnswering { Button("Cancel", action: session.cancelCurrent) }
                Button("Answer screenshots", action: session.sendCaptures)
                    .disabled(session.stackImages.isEmpty)
            }
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(.plain)
            if !session.stackImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(session.stackImages.enumerated()), id: \.offset) { index, capture in
                            VStack(spacing: 3) {
                                Button { preview = preview == index ? nil : index } label: {
                                    if let image = NSImage(data: capture.data) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(width: 72, height: 42)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Preview screenshot \(index + 1)")
                                HStack(spacing: 6) {
                                    Text("\(index + 1)").monospacedDigit()
                                    Button { session.moveCapture(from: index, to: index - 1); preview = nil } label: { Image(systemName: "arrow.left") }
                                        .disabled(index == 0).accessibilityLabel("Move screenshot earlier")
                                    Button { session.moveCapture(from: index, to: index + 1); preview = nil } label: { Image(systemName: "arrow.right") }
                                        .disabled(index == session.stackImages.count - 1).accessibilityLabel("Move screenshot later")
                                    Button { session.removeCapture(at: index); preview = nil } label: { Image(systemName: "xmark") }
                                        .accessibilityLabel("Remove screenshot")
                                }.font(.system(size: 9)).buttonStyle(.plain)
                            }
                        }
                    }
                }.frame(height: 65)
                if let preview, session.stackImages.indices.contains(preview), let image = NSImage(data: session.stackImages[preview].data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                        .accessibilityLabel("Screenshot \(preview + 1) enlarged preview")
                }
            }
        }.padding(.horizontal, 10).padding(.vertical, 5)
    }
}
