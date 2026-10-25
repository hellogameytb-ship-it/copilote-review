import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplay
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Copilote cannot access the screen. Allow access in System Settings → Privacy & Security → "
                + "Screen & System Audio Recording, then reopen Copilote."
        case .noDisplay:
            return "No display available for capture."
        case let .failed(reason):
            return "Capture failed : \(reason)"
        }
    }
}

/// Screenshots through ScreenCaptureKit, always without Copilote's own windows.
@MainActor
final class ScreenCapturer {
    /// Window numbers to leave out explicitly (the overlay), on top of every window this app owns.
    var excludedWindowNumbers: () -> [Int] = { [] }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; afterwards the user has to go to System Settings.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// The screen under the mouse pointer: where the user is looking.
    static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    func capture(_ screen: NSScreen) async throws -> CGImage {
        guard Self.hasPermission else {
            Self.requestPermission()
            throw CaptureError.permissionDenied
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw Self.map(error)
        }
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        // No fallback to another display: the region selector maps points with this screen's size.
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excludedNumbers = Set(excludedWindowNumbers())
        let excluded = content.windows.filter {
            excludedNumbers.contains(Int($0.windowID)) || $0.owningApplication?.processID == ownPID
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> CaptureError {
        if (error as NSError).domain == SCStreamErrorDomain,
           (error as NSError).code == SCStreamError.userDeclined.rawValue {
            return .permissionDenied
        }
        return .failed(error.localizedDescription)
    }
}
