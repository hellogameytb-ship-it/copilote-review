import AppKit
import CopiloteKit
import SwiftUI

/// The capture pipeline receives only generated fixture pixels, never ambient desktop content.
@MainActor
enum DiagnosticCaptureButton {
    final class Capturer: ScreenCapturing {
        private(set) var calls = 0
        func capture(_ screen: NSScreen) async throws -> CGImage {
            guard DiagnosticAnchorFixture.isRequested,
                  ProcessInfo.processInfo.environment["COPILOTE_HEADLESS_GEOMETRY"] == "1" else { throw CaptureError.noDisplay }
            let colors = [NSColor.systemRed, .systemGreen, .systemBlue, .systemOrange]
            let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:320,pixelsHigh:180,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
            colors[calls % colors.count].setFill(); NSRect(x:0,y:0,width:320,height:180).fill()
            NSGraphicsContext.restoreGraphicsState()
            calls += 1
            return bitmap.cgImage!
        }
    }

    static func run(folder:URL, overlay:OverlayController, settings:SettingsStore, listening:ListeningController,
                    assist:AssistController, session:SessionController, capturer:Capturer, provider:RecetteProvider,
                    record:(String,Bool)->Void) async {
        guard DiagnosticAnchorFixture.isRequested,
              let pill = NSApp.windows.first(where:{$0.windowNumber == overlay.windowNumbers[0]}),
              let panel = NSApp.windows.first(where:{$0.windowNumber == overlay.windowNumbers[1]}) as? OverlayPanel,
              let content = panel.contentView else { return }
        var layouts:[[String:Any]] = []
        var geometry:[[String:Any]] = []
        func pause(_ ms:Int = 60) async { try? await Task.sleep(for:.milliseconds(ms)) }
        func marker(_ id:String, in view:NSView) -> InlineControlMarker? {
            if view.identifier?.rawValue == id, view.bounds.width > 0, view.bounds.height > 0 { return view as? InlineControlMarker }
            return view.subviews.lazy.compactMap { marker(id,in:$0) }.first
        }
        func invoke(_ id:String) -> Bool {
            content.layoutSubtreeIfNeeded()
            return marker(id,in:content)?.invokeHeadlessAction() == true
        }
        func checkGeometry(_ name:String, anchor:NSRect, body:NSRect) {
            let delta = max(abs(pill.frame.minX-anchor.minX),abs(pill.frame.minY-anchor.minY),abs(panel.frame.minX-body.minX),abs(panel.frame.minY-body.minY))
            geometry.append(["name":name,"maxOriginDelta":delta])
            record(name + " keeps native origins",delta < 0.01 && pill.frame.size == anchor.size && panel.frame.size == body.size)
        }
        func checkLayout(_ name:String) {
            content.layoutSubtreeIfNeeded()
            guard let button = marker("CaptureScreen",in:content), let title = marker("CaptureScreenTitle",in:content), let keys = marker("CaptureScreenKeys",in:content) else {
                record(name + " capture button markers exist",false); return
            }
            let buttonRect = button.convert(button.bounds,to:content)
            let titleRect = title.convert(title.bounds,to:content)
            let keysRect = keys.convert(keys.bounds,to:content)
            let fits = content.bounds.contains(buttonRect) && buttonRect.contains(titleRect) && buttonRect.contains(keysRect)
            record(name + " capture target at least 220 by 40",buttonRect.width >= 220 && buttonRect.height >= 40)
            record(name + " title and shortcut fit without clipping",fits)
            layouts.append(["name":name,"content":NSStringFromRect(content.bounds),"button":NSStringFromRect(buttonRect),"title":NSStringFromRect(titleRect),"keys":NSStringFromRect(keysRect),"fits":fits])
        }
        func snapshot(_ name:String) {
            guard let bitmap = content.bitmapImageRepForCachingDisplay(in:content.bounds) else { return }
            content.cacheDisplay(in:content.bounds,to:bitmap)
            try? bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent(name + ".png"))
        }
        session.clear(); await provider.resetConversations()
        WindowPrivacy.authorizeFromUserGesture(); overlay.present(); overlay.reveal(); await pause(200)
        let originalSize = panel.frame.size
        let stealth = settings.stealth, state = listening.state
        assist.askText = "Fictional unsent screenshot question"
        let draft = assist.askText
        for width:CGFloat in [600,420] {
            panel.setContentSize(NSSize(width:width,height:540)); await pause(150)
            checkLayout("empty width=\(Int(width))")
            snapshot("capture-empty-\(Int(width))")
        }
        panel.setContentSize(NSSize(width:600,height:640)); await pause(150)
        let anchor = pill.frame, body = panel.frame
        for index in 0..<3 {
            record("capture button action \(index)",invoke("CaptureScreen"))
            for _ in 0..<100 { await pause(10); if session.stackImages.count == index + 1 { break } }
            record("one image per button action \(index)",capturer.calls == index + 1 && session.stackImages.count == index + 1)
            checkGeometry("capture \(index)",anchor:anchor,body:body)
        }
        let original = session.stackImages
        record("capture pipeline produces distinct encoded images",Set(original.map(\.data)).count == 3 && original.allSatisfy { $0.mediaType == "image/jpeg" })
        record("adding screenshots does not submit or change session",await provider.conversations.isEmpty && session.history.isEmpty && !session.isAnswering && assist.askText == draft && listening.state == state && settings.stealth == stealth)
        record("bound preview action",invoke("CapturePreview1")); await pause()
        record("enlarged preview appears",marker("CaptureEnlargedPreview",in:content) != nil)
        checkLayout("expanded preview"); snapshot("capture-preview-600")
        record("bound preview closes",invoke("CapturePreview1")); await pause()
        record("bound reorder action",invoke("CaptureEarlier2")); await pause()
        record("bound removal action",invoke("CaptureRemove0")); await pause()
        let expected = original.count == 3 ? [original[2],original[1]] : []
        record("reorder and remove preserve displayed order",session.stackImages == expected && expected.count == 2)
        for width:CGFloat in [600,420] {
            panel.setContentSize(NSSize(width:width,height:540)); await pause(150)
            checkLayout("stack width=\(Int(width))"); snapshot("capture-stack-\(Int(width))")
        }
        // A direct invocation exercises the exact action registered for the existing keyboard shortcut.
        session.captureFullScreen()
        for _ in 0..<100 { await pause(10); if capturer.calls == 4 && session.stackImages.count == 3 { break } }
        record("shortcut action adds exactly one image after ordered stack",capturer.calls == 4 && session.stackImages.count == 3 && Array(session.stackImages.prefix(2)) == expected)
        let pending = session.stackImages
        await provider.delayNext()
        record("bound explicit send action",invoke("CaptureSend")); await pause(80)
        record("explicit send drains stack and begins answer",session.isAnswering && session.stackImages.isEmpty)
        checkLayout("answer with cancel width420")
        record("bound cancel action",invoke("CaptureCancel")); await pause(1100)
        record("cancel restores screenshots in order",!session.isAnswering && session.stackImages == pending && session.history.first?.note == "Cancelled")
        let requests = await provider.conversations
        let messages = requests.last?.messages ?? []
        let blocks: [JSONValue] = messages.flatMap { $0["content"]?.arrayValue ?? [] }
        let sent = blocks.filter { $0["type"] == "image" }.compactMap { $0["source"]?["data"]?.stringValue }
        record("only explicit send reaches provider with ordered captures",requests.count == 1 && sent == pending.map { $0.data.base64EncodedString() })
        record("capture controls do not change draft stealth or listening",assist.askText == draft && settings.stealth == stealth && listening.state == state)
        record("capture fixture does not show or take desktop windows",!NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
        session.clear(); await provider.resetConversations()
        panel.setContentSize(originalSize); overlay.hide()
        let result:[String:Any] = ["layouts":layouts,"geometry":geometry,"captureCalls":capturer.calls,"ambientDesktopCaptured":false,"globalShortcutEventsSent":false,
            "limitations":"Generated image source through production capture action/encoding/stack. View-bound callbacks and own view rendering, not physical clicks or OS hotkey delivery."]
        try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("capture-button.json"))
    }
}
