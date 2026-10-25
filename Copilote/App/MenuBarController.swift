import AppKit

/// The optional menu bar icon (off by default): Afficher / Start session / Settings / Quitter.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let isVisible: () -> Bool
    private let isListening: () -> Bool
    private let onToggleOverlay: () -> Void
    private let onToggleListening: () -> Void
    private let onSettings: () -> Void

    init(isVisible: @escaping () -> Bool, isListening: @escaping () -> Bool, onToggleOverlay: @escaping () -> Void,
         onToggleListening: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.isVisible = isVisible
        self.isListening = isListening
        self.onToggleOverlay = onToggleOverlay
        self.onToggleListening = onToggleListening
        self.onSettings = onSettings
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            // The logo's silhouette, a template image: macOS tints it like the other menu bar icons.
            let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "bubble.left", accessibilityDescription: "Copilote")
            icon?.isTemplate = true
            icon?.accessibilityDescription = "Copilote"
            item.button?.image = icon
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if !enabled, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    /// Built when opened, so the labels match the moment.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(entry(isVisible() ? Copy.MenuBar.hide : Copy.MenuBar.show, #selector(toggleOverlay)))
        menu.addItem(entry(isListening() ? Copy.MenuBar.stopListening : Copy.MenuBar.listen, #selector(toggleListening)))
        menu.addItem(.separator())
        menu.addItem(entry(Copy.MenuBar.settings, #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Copy.MenuBar.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleOverlay() { onToggleOverlay() }
    @objc private func toggleListening() { onToggleListening() }
    @objc private func openSettings() { onSettings() }
}
