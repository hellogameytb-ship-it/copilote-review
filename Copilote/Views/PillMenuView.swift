import CopiloteKit
import SwiftUI

/// The ⚙ menu's entries for the pill's state. Data only: the app and copilote-render both use it.
enum PillMenuContent {
    static func menu(for state: PillState) -> OverlayMenu {
        let modes: [OverlayMenu.Entry] = MeetingMode.allCases.map {
            .choice(id: PillMenuAction.mode($0).id, title: $0.name, isChecked: $0 == state.mode)
        }
        return OverlayMenu(entries: [
            .info(state.provider == nil ? Copy.Pill.noProvider : Copy.Pill.provider(state.providerDetail)),
            .separator,
            .header(Copy.Pill.mode),
        ] + modes + [
            .separator,
            .action(id: PillMenuAction.openApp.id, title: Copy.Pill.openApp),
            .action(id: PillMenuAction.recenter.id, title: Copy.Pill.recenter),
            .action(id: PillMenuAction.tour.id, title: Copy.Pill.tour),
            .separator,
            .action(id: PillMenuAction.quit.id, title: Copy.Pill.quit),
        ])
    }
}

/// The ⚙ menu, drawn in one of Copilote's panels (an NSMenu is a system window, visible in a
/// screen share). Reads like an NSMenu: a highlighted row under the mouse or the arrows, a tick
/// on the current mode.
struct PillMenuView: View {
    let menu: OverlayMenu
    var onHover: (Int) -> Void = { _ in }
    var onChoose: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(menu.entries.enumerated()), id: \.offset) { index, entry in
                row(entry, at: index)
            }
        }
        .padding(5)
        .frame(width: 270)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.Pill.more)
    }

    @ViewBuilder
    private func row(_ entry: OverlayMenu.Entry, at index: Int) -> some View {
        switch entry {
        case let .info(text):
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 4)
        case let .header(text):
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 1)
        case .separator:
            Divider().padding(.horizontal, 6).padding(.vertical, 4)
        case let .choice(id, title, isChecked):
            MenuRow(title: title, isChecked: isChecked, isSelected: menu.selected == index, onHover: { onHover(index) }, onChoose: { onChoose(id) })
        case let .action(id, title):
            MenuRow(title: title, isChecked: false, isSelected: menu.selected == index, onHover: { onHover(index) }, onChoose: { onChoose(id) })
        }
    }
}

private struct MenuRow: View {
    let title: String
    let isChecked: Bool
    let isSelected: Bool
    let onHover: () -> Void
    let onChoose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .opacity(isChecked ? 1 : 0)
                .frame(width: 12)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? FicheStyle.accentFill : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
        .onHover { if $0 { onHover() } }
        .onTapGesture(perform: onChoose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onChoose() }
    }
}
