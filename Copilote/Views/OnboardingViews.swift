import AppKit
import CopiloteKit
import SwiftUI

struct PermissionState: Equatable {
    var screen = false
    var microphone = false
}

/// What the welcome shows, read when it opens and refreshed while it runs. Data only (shared with
/// copilote-render).
struct OnboardingStatus: Equatable {
    var permissions = PermissionState()
    var codexReady = false
    /// "Codex · gpt-5.6-luna" when ready, otherwise why not.
    var codexDetail = ""
    var basePath = "Brain · iCloud Obsidian"
    var baseItems = 0
    var isStealth = true
    var labels = ShortcutLabels()
}

/// One step of the first-launch welcome, in the small panel under the pill.
struct OnboardingStepView: View {
    let onboarding: Onboarding
    var status = OnboardingStatus()
    var onOpenScreenSettings: () -> Void = {}
    var onOpenMicrophoneSettings: () -> Void = {}
    var onRetryCodex: () -> Void = {}
    var onOpenBase: () -> Void = {}
    var onBack: () -> Void = {}
    var onNext: () -> Void = {}
    var onSkip: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(Copy.Welcome.progress(onboarding.number, of: Onboarding.count))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if !onboarding.isLast { Button(Copy.Welcome.skip, action: onSkip).buttonStyle(.plain).foregroundStyle(.secondary) }
            }
            content
            HStack(spacing: 10) {
                ProgressDots(current: onboarding.number - 1, count: Onboarding.count)
                Spacer()
                // The pill's styles: the panel is never key, a system prominent button would look inactive.
                if onboarding.canGoBack {
                    Button(action: onBack) { Text(Copy.Welcome.back).font(.system(size: 13, weight: .medium)) }
                        .buttonStyle(PillButtonStyle())
                }
                Button(action: onNext) {
                    Text(onboarding.isLast ? Copy.Welcome.start : Copy.Welcome.next).font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
        .padding(22)
        .frame(width: 440)
        .animation(FicheStyle.motion(reduceMotion), value: onboarding.step)
    }

    @ViewBuilder
    private var content: some View {
        switch onboarding.step {
        case .welcome:
            step(Copy.Welcome.welcomeTitle, Copy.Welcome.welcomeBody)
        case .permissions:
            step(Copy.Welcome.permissionsTitle, Copy.Welcome.permissionsBody) {
                row(Copy.Welcome.microphone, Copy.Welcome.microphoneWhy, isDone: status.permissions.microphone) {
                    Button(Copy.Welcome.allow, action: onOpenMicrophoneSettings)
                }
                row(Copy.Welcome.screen, Copy.Welcome.screenWhy, isDone: status.permissions.screen) {
                    Button(Copy.Welcome.allow, action: onOpenScreenSettings)
                }
            }
        case .codex:
            step(Copy.Welcome.codexTitle, Copy.Welcome.codexBody) {
                row(status.codexReady ? Copy.Welcome.codexReady : Copy.Welcome.codexMissing, status.codexDetail, isDone: status.codexReady) {
                    Button(Copy.Welcome.retry, action: onRetryCodex)
                }
            }
        case .base:
            step(Copy.Welcome.baseTitle, Copy.Welcome.baseBody) {
                row(status.basePath, Copy.Welcome.baseCount(status.baseItems), isDone: status.baseItems > 0) {
                    Button(Copy.Welcome.openFolder, action: onOpenBase)
                }
            }
        case .shortcuts:
            step(Copy.Welcome.shortcutsTitle, Copy.Welcome.shortcutsBody) {
                VStack(spacing: 6) {
                    key(status.labels.toggleOverlay, Copy.Welcome.keyToggle)
                    key(status.labels.ask, Copy.Welcome.keyAsk)
                    key(status.labels.sendCaptures, Copy.Welcome.keyScreen)
                    key(status.labels.toggleListening, Copy.Welcome.keyListen)
                }
            }
        case .stealth:
            step(Copy.Welcome.stealthTitle, Copy.Welcome.stealthBody(status.labels.toggleMode)) {
                row(status.isStealth ? Copy.Welcome.stealthOn : Copy.Welcome.stealthOff, Copy.Welcome.stealthWhere, isDone: status.isStealth) {
                    EmptyView()
                }
            }
        }
    }

    private func step(_ title: String, _ body: String) -> some View {
        step(title, body) { EmptyView() }
    }

    private func step<Extra: View>(_ title: String, _ body: String, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 20, weight: .semibold)).tracking(-0.3)
            Text(body).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            extra()
        }
        .accessibilityElement(children: .contain)
    }

    /// A line with its state: green once done, its button otherwise.
    private func row<Action: View>(_ title: String, _ detail: String, isDone: Bool, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Color.green : Color.secondary)
                .font(.system(size: 15))
                .accessibilityLabel(isDone ? Copy.Welcome.done : Copy.Welcome.toDo)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !isDone { action() }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func key(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(minWidth: 56)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(FicheStyle.accent.opacity(0.45), lineWidth: 1))
            Text(label).font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? FicheStyle.accent : Color.white.opacity(index < current ? 0.4 : 0.15))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The optional menu bar menu, drawn (an NSMenu can't be rendered off-screen): same items as
/// `MenuBarController`.
struct MenuBarMenuPreview: View {
    let isVisible: Bool
    let isListening: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(isVisible ? Copy.MenuBar.hide : Copy.MenuBar.show, "")
            row(isListening ? Copy.MenuBar.stopListening : Copy.MenuBar.listen, "")
            Divider().padding(.vertical, 4)
            row(Copy.MenuBar.settings, "⌘,")
            Divider().padding(.vertical, 4)
            row(Copy.MenuBar.quit, "⌘Q")
        }
        .padding(5)
        .frame(width: 230)
        .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func row(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Text(keys).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
    }
}
