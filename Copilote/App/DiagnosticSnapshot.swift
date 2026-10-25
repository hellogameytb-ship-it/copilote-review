import AppKit

/// Launched with `-CopiloteSnapshot <folder>` (and optionally `-CopiloteSnapshotQuit YES`):
/// Copilote writes, for its own windows only, their frame, screen, Space and content as PNG, so a
/// real launch can be checked without capturing the screen (the overlay is excluded from
/// captures, and nothing else on screen is read). Off unless the argument is given.
@MainActor
enum DiagnosticSnapshot {
    static func scheduleIfAsked() {
        // The launch's own arguments only: a value left in the preferences never turns it on.
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-CopiloteSnapshot"), arguments.indices.contains(flag + 1) else { return }
        let folder = arguments[flag + 1]
        let quit = arguments.contains("-CopiloteSnapshotQuit")
        var spaceChanges = 0
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in spaceChanges += 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            write(to: URL(fileURLWithPath: folder), spaceChanges: spaceChanges)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            if quit { NSApp.terminate(nil) }
        }
    }

    static func write(to folder: URL, spaceChanges: Int) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var windows: [[String: Any]] = []
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            let name = "\(index)-\(String(describing: type(of: window)))"
            var info: [String: Any] = [
                "name": name,
                "frame": NSStringFromRect(window.frame),
                "onActiveSpace": window.isOnActiveSpace,
                "level": window.level.rawValue,
                "sharingNone": window.sharingType == .none,
                "collectionBehavior": window.collectionBehavior.rawValue,
                "alpha": window.alphaValue,
                "isKey": window.isKeyWindow,
            ]
            if let screen = window.screen {
                info["screenFrame"] = NSStringFromRect(screen.frame)
                info["visibleFrame"] = NSStringFromRect(screen.visibleFrame)
                info["insideVisibleFrame"] = screen.visibleFrame.contains(window.frame)
                info["safeAreaTop"] = screen.safeAreaInsets.top
            }
            if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: folder.appendingPathComponent(name + ".png"))
                }
            }
            windows.append(info)
        }
        let report: [String: Any] = [
            "activationPolicy": NSApp.activationPolicy().rawValue,
            "isActive": NSApp.isActive,
            "spaceChangesSinceLaunch": spaceChanges,
            "windows": windows,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("windows.json"))
        }
    }
}
