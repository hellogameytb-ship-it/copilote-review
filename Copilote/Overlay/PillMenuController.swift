import AppKit
import CopiloteKit
import SwiftUI

/// The ⚙ menu in a panel of Copilote's own (`sharingType = .none`, like the pill): an NSMenu is a
/// system window, so it showed in screen shares. It takes the keyboard while open (↑ ↓, Home /
/// End, Return or Space, Échap) and gives it back to the app in front when it closes; a click
/// anywhere else closes it, like an NSMenu.
@MainActor
final class PillMenuController {
    /// Keys reach the menu before the hosting view. Above the pill and the panel, like a menu.
    private final class MenuPanel: OverlayPanel {
        var onKey: ((NSEvent) -> Bool)?

        init() {
            super.init(size: NSSize(width: 280, height: 300), resizable: false)
            level = .popUpMenu
            minSize = .zero
        }

        override func sendEvent(_ event: NSEvent) {
            if event.type == .keyDown, onKey?(event) == true { return }
            super.sendEvent(event)
        }
    }

    private let panel = MenuPanel()
    private let model = PillMenuModel()
    private var hosting: NSView!
    private var onChoose: (PillMenuAction) -> Void = { _ in }
    private var previousApp: NSRunningApplication?
    /// Its own flag: ordering the panel out makes it resign key, which calls `close` again.
    private(set) var isOpen = false
    /// Its window, for captures to leave out like the overlay's.
    var windowNumbers: [Int] { [panel.windowNumber] }
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// A click outside closed it: if that click was on ⚙, its button action must not open it again.
    private var closingClick: (at: NSPoint, time: Date)?

    init() {
        let host = FirstMouseHostingView(rootView: MenuHost(model: model, onChoose: { [weak self] in self?.choose($0) }))
        panel.contentView = OverlayController.surface(hosting: host, cornerRadius: 9)
        hosting = host
        panel.onKey = { [weak self] in self?.handle($0) ?? false }
        // Clicked into another app: the keyboard is already theirs.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(restoringKeyboard: false) }
        })
    }

    /// ⚙: opens under `anchor` (screen coordinates), or closes it.
    func toggle(_ menu: OverlayMenu, anchor: CGRect, onChoose: @escaping (PillMenuAction) -> Void) {
        if isOpen { return close(restoringKeyboard: true) }
        let click = closingClick
        closingClick = nil
        if let click, anchor.insetBy(dx: -2, dy: -2).contains(click.at), Date().timeIntervalSince(click.time) < 5 { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        guard let screen else { return }
        self.onChoose = onChoose
        model.menu = menu
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setFrame(PopoverPlacement.frame(size: size, anchor: anchor, on: screen.visibleFrame), display: true)
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        isOpen = true
        panel.allowsKey = true
        panel.orderFrontRegardless()
        panel.makeKey()
        watchClicks()
    }

    func close(restoringKeyboard: Bool) {
        guard isOpen else { return }
        isOpen = false
        let previous = previousApp
        previousApp = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.allowsKey = false
        panel.orderOut(nil)
        if restoringKeyboard, let previous, NSWorkspace.shared.frontmostApplication?.processIdentifier != previous.processIdentifier { previous.activate() }
    }

    func choose(_ id: String) {
        guard let action = PillMenuAction(id: id) else { return }
        // The main window takes the keyboard itself.
        close(restoringKeyboard: action != .openApp)
        onChoose(action)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let command = OverlayMenu.command(forKeyCode: Int(event.keyCode)) else { return false }
        switch command {
        case .down: model.menu.moveDown()
        case .up: model.menu.moveUp()
        case .first: model.menu.selectFirst()
        case .last: model.menu.selectLast()
        case .choose: if let id = model.menu.selectedID { choose(id) }
        case .close: close(restoringKeyboard: true)
        }
        return true
    }

    /// Any click outside the menu closes it. In the pill or the panel (they never take the
    /// keyboard), the keyboard goes back to the app in front; in the main window or another app,
    /// that window takes it.
    private func watchClicks() {
        let kinds: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel else { return }
                self.closingClick = (NSEvent.mouseLocation, Date())
                self.close(restoringKeyboard: event.window is OverlayPanel)
            }
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close(restoringKeyboard: false) }
        }) { monitors.append(global) }
    }
}

private final class PillMenuModel: ObservableObject {
    @Published var menu = OverlayMenu(entries: [])
}

private struct MenuHost: View {
    @ObservedObject var model: PillMenuModel
    let onChoose: (String) -> Void

    var body: some View {
        PillMenuView(menu: model.menu, onHover: { model.menu.select(index: $0) }, onChoose: onChoose)
    }
}
