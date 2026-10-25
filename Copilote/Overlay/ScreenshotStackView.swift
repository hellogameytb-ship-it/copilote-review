import AppKit
import SwiftUI

/// Explicit, ordered screenshot collection. No capture happens until a button is pressed.
struct ScreenshotStackView: View {
    @ObservedObject var session: SessionController
    @State private var preview: Int?

    private var captureButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            CaptureScreenButton(keys: ShortcutCatalog.keys(for: .captureScreen), action: session.captureFullScreen)
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private var secondaryActions: some View {
        HStack(spacing: 10) {
            Button("Add region", action: session.captureRegion)
            Spacer(minLength: 0)
            if session.isAnswering {
                Button("Cancel", action: session.cancelCurrent)
                    .background(InlineControlBounds(id: "CaptureCancel", action: session.cancelCurrent))
            }
            Button("Answer screenshots", action: session.sendCaptures)
                .background(InlineControlBounds(id: "CaptureSend", action: session.sendCaptures))
                .disabled(session.stackImages.isEmpty)
        }
        .font(.system(size: 11, weight: .medium))
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    captureButton
                    secondaryActions
                }
                VStack(alignment: .leading, spacing: 6) {
                    captureButton
                    secondaryActions
                }
            }
            if !session.stackImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(session.stackImages.enumerated()), id: \.offset) { index, capture in
                            let previewAction = { preview = preview == index ? nil : index }
                            let earlierAction = { session.moveCapture(from: index, to: index - 1); preview = nil }
                            let removeAction = { session.removeCapture(at: index); preview = nil }
                            VStack(spacing: 3) {
                                Button(action: previewAction) {
                                    if let image = NSImage(data: capture.data) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(width: 72, height: 42)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Preview screenshot \(index + 1)")
                                .background(InlineControlBounds(id: "CapturePreview\(index)", action: previewAction))
                                HStack(spacing: 6) {
                                    Text("\(index + 1)").monospacedDigit()
                                    Button(action: earlierAction) { Image(systemName: "arrow.left") }
                                        .disabled(index == 0).accessibilityLabel("Move screenshot earlier")
                                        .background(InlineControlBounds(id: "CaptureEarlier\(index)", action: earlierAction))
                                    Button { session.moveCapture(from: index, to: index + 1); preview = nil } label: { Image(systemName: "arrow.right") }
                                        .disabled(index == session.stackImages.count - 1).accessibilityLabel("Move screenshot later")
                                    Button(action: removeAction) { Image(systemName: "xmark") }
                                        .accessibilityLabel("Remove screenshot")
                                        .background(InlineControlBounds(id: "CaptureRemove\(index)", action: removeAction))
                                }.font(.system(size: 9)).buttonStyle(.plain)
                            }
                        }
                    }
                }.frame(height: 65)
                if let preview, session.stackImages.indices.contains(preview), let image = NSImage(data: session.stackImages[preview].data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                        .accessibilityLabel("Screenshot \(preview + 1) enlarged preview")
                        .background(InlineControlBounds(id: "CaptureEnlargedPreview"))
                }
            }
        }.padding(.horizontal, 10).padding(.vertical, 5)
    }
}

/// A comfortable target in the expanded panel; the compact pill keeps its existing dimensions.
struct CaptureScreenButton: View {
    let keys: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder").font(.system(size: 16, weight: .semibold))
                Text("Capture screen")
                    .font(.system(size: 13, weight: .semibold))
                    .background(InlineControlBounds(id: "CaptureScreenTitle"))
                Text(keys)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .background(InlineControlBounds(id: "CaptureScreenKeys"))
            }
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minWidth: 220, minHeight: 40)
            .background(FicheStyle.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(FicheStyle.accent.opacity(0.4)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture screen")
        .accessibilityHint("Add a screenshot to the stack without sending it")
        .overlayHint("Add a screenshot · \(keys)")
        .background(InlineControlBounds(id: "CaptureScreen", action: action))
    }
}
