import AppKit
import SwiftUI
import CopiloteKit

/// Explicit Paste actions on the production editor; all bytes and pasteboards belong to this fixture.
@MainActor
enum DiagnosticComposerPaste {
    static func run(folder: URL, overlay: OverlayController, settings: SettingsStore,
                    assist: AssistController, session: SessionController,
                    provider: RecetteProvider, record: (String, Bool) -> Void) async {
        guard DiagnosticAnchorFixture.isRequested else { return }
        var checks: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool) { checks.append(["name":name,"passed":passed]);record(name,passed) }
        func settle() async {
            for _ in 0..<1000 { if !session.isPastingImages { break };try? await Task.sleep(for:.milliseconds(5)) }
        }
        func bytes(_ color: NSColor, _ type: NSBitmapImageRep.FileType = .png, width: Int = 24) -> Data {
            let context=CGContext(data:nil,width:width,height:12,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            let rgb=color.usingColorSpace(.deviceRGB)!
            context.setFillColor(CGColor(red:rgb.redComponent,green:rgb.greenComponent,blue:rgb.blueComponent,alpha:1))
            context.fill(CGRect(x:0,y:0,width:width,height:12))
            let bitmap=NSBitmapImageRep(cgImage:context.makeImage()!)
            return bitmap.representation(using:type,properties:[:])!
        }
        let red=bytes(.red), green=bytes(.green,.tiff), blue=bytes(.blue), wide=bytes(.red,width:3200)
        let board=NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        func put(_ data: Data, type: NSPasteboard.PasteboardType = .png, text: String? = nil) {
            let item=NSPasteboardItem();item.setData(data,forType:type)
            if let text { item.setString(text,forType:.string) }
            board.clearContents();board.writeObjects([item])
        }
        let panel=OverlayPanel(size:NSSize(width:600,height:100))
        panel.isReleasedWhenClosed=false
        let host=NSHostingView(rootView:AskField(text:Binding(get:{assist.askText},set:{assist.askText=$0}),onPasteImages:session.pasteImages,wantsFocus:false))
        panel.contentView=host;host.layoutSubtreeIfNeeded()
        func find(_ view:NSView)->OverlayAskTextField? {
            if let field=view as? OverlayAskTextField { return field }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        guard let field=find(host),let editor=panel.fieldEditor(true,for:field) as? NSTextView else {
            check("paste fixture resolves production Ask editor",false);return
        }
        field.pasteboardForPaste={board}
        func draft(_ text:String, selection:NSRange? = nil) {
            assist.askText=text;field.stringValue=text
            field.cell?.select(withFrame:field.bounds,in:field,editor:editor,delegate:field,start:0,length:0)
            editor.string=text;editor.setSelectedRange(selection ?? NSRange(location:(text as NSString).length,length:0))
            _ = panel.makeFirstResponder(editor)
        }
        session.clear();await provider.resetConversations()
        func hasStatus(_ fragment:String)->Bool {
            func contains(_ view:NSView)->Bool {
                if let field=view as? NSTextField, field.stringValue.contains(fragment) { return true }
                return view.subviews.contains(where:contains)
            }
            return NSApp.windows.compactMap(\.contentView).contains(where:contains)
        }
        let initialFrame=panel.frame
        var pasteGeometry:[String:Any]=[:]
        let profile=settings.infosysInterviewContext, active=settings.infosysInterviewActive
        let prefs=settings.answerPreferences, notes=session.stickyNotes.notes, stealth=settings.stealth
        draft("Keep my draft",selection:NSRange(location:5,length:2))
        // Let the new hosting view establish its intrinsic size before measuring a paste.
        try? await Task.sleep(for:.milliseconds(40));host.layoutSubtreeIfNeeded()
        draft("Keep my draft",selection:NSRange(location:5,length:2))
        let frame=panel.frame,pill=overlay.pillFrame
        let responder=panel.firstResponder
        check("paste baseline has the native field editor as local responder",responder === editor)
        put(red,text:"IMAGE_METADATA_NOT_A_QUESTION")
        editor.doCommand(by:#selector(NSText.paste(_:)))
        check("image paste queues synchronously without changing draft or selection",session.isPastingImages && assist.askText == "Keep my draft" && editor.string == "Keep my draft" && editor.selectedRange() == NSRange(location:5,length:2))
        session.sendCaptures();session.sendClipboard();assist.submitAsk();assist.answerNow()
        check("send paths leave draft intact during import",assist.askText == "Keep my draft" && session.stackImages.isEmpty)
        await settle()
        check("PNG adds one JPEG preview without a request",await provider.conversations.count == 0 && session.stackImages.count == 1 && session.stackImages.first?.mediaType == "image/jpeg")
        let redImage=session.stackImages.first
        put(green,type:.tiff);editor.paste(nil);await settle()
        let greenImage=session.stackImages.last
        check("TIFF adds a distinct second preview",session.stackImages.count == 2 && greenImage != redImage)
        let both=NSPasteboardItem();both.setData(red,forType:.png);both.setData(green,forType:.tiff)
        board.clearContents();board.writeObjects([both]);editor.paste(nil);await settle()
        check("multiple representations on one item produce one image with PNG priority",session.stackImages.count == 3 && session.stackImages.last == redImage)
        put(wide);editor.paste(nil);await settle()
        check("large image uses existing 1600-pixel JPEG pipeline",session.stackImages.last?.pixelWidth == 1600 && session.stackImages.last?.mediaType == "image/jpeg")
        pasteGeometry=["initialFrame":NSStringFromRect(initialFrame),"baselineFrame":NSStringFromRect(frame),"afterPasteFrame":NSStringFromRect(panel.frame),"sameResponder":panel.firstResponder === responder,"samePill":overlay.pillFrame == pill]
        check("image paste preserves local focus and panel position",panel.firstResponder === responder && panel.frame == frame && overlay.pillFrame == pill)
        draft("abc DEF ghi",selection:NSRange(location:4,length:3))
        board.clearContents();board.setString("é🙂",forType:.string);editor.paste(nil)
        check("native text paste replaces selection and updates Ask binding",editor.string == "abc é🙂 ghi" && assist.askText == "abc é🙂 ghi" && editor.selectedRange().length == 0)
        draft("");board.clearContents();board.setString("https://example.invalid/picture.png",forType:.string);editor.paste(nil)
        check("plain URL stays text and never creates an image",assist.askText == "https://example.invalid/picture.png" && !session.isPastingImages && session.stackImages.count == 4)
        let files=folder.appendingPathComponent("paste-fixtures",isDirectory:true)
        try? FileManager.default.createDirectory(at:files,withIntermediateDirectories:true)
        let first=files.appendingPathComponent("first.png"), second=files.appendingPathComponent("second.tiff"), unsupported=files.appendingPathComponent("skip.txt")
        try? red.write(to:first);try? green.write(to:second);try? Data("not an image".utf8).write(to:unsupported)
        board.clearContents();board.writeObjects([first,unsupported,second].map { url in
            let item=NSPasteboardItem();item.setString(url.absoluteString,forType:.fileURL);item.setData(blue,forType:.png);item.setString("Finder name",forType:.string);return item
        })
        editor.paste(nil);await settle()
        check("copied image files keep order and skip unsupported files instead of Finder icons",session.stackImages.count == 6 && Array(session.stackImages.suffix(2)) == [redImage!,greenImage!])
        session.clear()
        let items=[red,blue].map { data in let item=NSPasteboardItem();item.setData(data,forType:.png);return item }
        board.clearContents();board.writeObjects(items);editor.paste(nil)
        put(green,type:.tiff);editor.paste(nil)
        board.clearContents();board.setString("changed after gesture",forType:.string)
        await settle()
        check("rapid gestures snapshot bytes and preserve cross-batch order",session.stackImages.count == 3 && session.stackImages.first == redImage && session.stackImages.last == greenImage && session.stackImages[1] != redImage && session.stackImages[1] != greenImage)
        board.clearContents();board.writeObjects((0..<22).map { _ in let item=NSPasteboardItem();item.setData(red,forType:.png);return item })
        let bounded=Clipboard.composerImages(from:board)
        check("pasteboard snapshot caps the batch and reports overflow",bounded?.images.count == 20 && bounded?.skipped == 2)
        put(Data(repeating:0,count:32*1024*1024+1))
        let oversized=Clipboard.composerImages(from:board)
        check("oversized image is rejected before decoding",oversized?.images.isEmpty == true && oversized?.skipped == 1)
        let beforeInvalid=session.stackImages
        put(Data("broken PNG".utf8));editor.paste(nil);await settle()
        check("malformed image completes without changing previews or sending",await provider.conversations.count == 0 && session.stackImages == beforeInvalid && !session.isPastingImages)
        check("malformed image reports an inline error",hasStatus("1 skipped"))
        session.pasteImages(ComposerImagePaste(images:Array(repeating:red,count:21),skipped:0));await settle()
        check("stack enforces 20 images while retaining earlier order",session.stackImages.count == 20 && Array(session.stackImages.prefix(3)) == beforeInvalid)
        check("full stack reports skipped images inline",hasStatus("skipped"))
        session.clear();session.pasteImages(ComposerImagePaste(images:Array(repeating:wide,count:20),skipped:0))
        for _ in 0..<100 { if !session.stackImages.isEmpty { break };try? await Task.sleep(for:.milliseconds(1)) }
        let partial=session.stackImages
        check("cancellation fixture reaches a partially imported batch",!partial.isEmpty && partial.count < 20 && session.isPastingImages)
        session.cancelImagePaste()
        try? await Task.sleep(for:.milliseconds(80))
        check("cancel during decoding keeps only previews already added",session.stackImages == partial && !session.isPastingImages)
        session.clear();session.pasteImages(ComposerImagePaste(images:[wide,red],skipped:0));session.cancelImagePaste()
        session.pasteImages(ComposerImagePaste(images:[green],skipped:0));await settle()
        try? await Task.sleep(for:.milliseconds(150))
        check("cancel invalidates old decode and queued work without affecting next paste",session.stackImages == [greenImage!])
        session.pasteImages(ComposerImagePaste(images:Array(repeating:wide,count:20),skipped:0))
        for _ in 0..<100 { if session.stackImages.count > 1 { break };try? await Task.sleep(for:.milliseconds(1)) }
        check("reset fixture reaches a partially imported batch",session.stackImages.count > 1 && session.stackImages.count < 20 && session.isPastingImages)
        session.clear()
        try? await Task.sleep(for:.milliseconds(150))
        check("full reset prevents late image reappearance",session.stackImages.isEmpty && !session.isPastingImages)
        session.pasteImages(ComposerImagePaste(images:[red],skipped:0));await settle()
        session.removeCapture(at:0)
        try? await Task.sleep(for:.milliseconds(30))
        check("removed preview does not reappear",session.stackImages.isEmpty)
        session.pasteImages(ComposerImagePaste(images:[red],skipped:0));await settle();assist.refresh()
        for item in assist.context.items where item.kind == .capture { assist.toggle(item.id) }
        session.pasteImages(ComposerImagePaste(images:[green],skipped:0));session.clearChat();await settle();assist.refresh()
        check("Clear chat retains pending images and existing exclusions",session.stackImages == [redImage!,greenImage!] && assist.context.items.contains { $0.kind == .capture && !$0.isIncluded })
        check("paste preserves profile, notes, preferences and Stealth",settings.infosysInterviewContext == profile && settings.infosysInterviewActive == active && settings.answerPreferences == prefs && session.stickyNotes.notes == notes && settings.stealth == stealth)
        check("no paste action sends automatically",await provider.conversations.count == 0)
        session.sendCaptures()
        for _ in 0..<200 { if !session.isAnswering { break };try? await Task.sleep(for:.milliseconds(5)) }
        check("explicit send still submits previews through the existing path",await provider.conversations.count == 1 && session.stackImages.isEmpty)
        check("quiet editor keeps system text services disabled",!editor.isContinuousSpellCheckingEnabled && !editor.isAutomaticSpellingCorrectionEnabled && !editor.isAutomaticTextCompletionEnabled && !editor.isAutomaticTextReplacementEnabled)
        check("paste fixture never shows a window or takes desktop focus",!NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
        try? JSONSerialization.data(withJSONObject:["checks":checks,"geometry":pasteGeometry,"isolatedPasteboard":true,"physicalKeyboard":false,"desktopCaptured":false,"audioCaptured":false,"liveAIRequests":0],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("paste.json"))
        _ = panel.makeFirstResponder(nil);panel.close();session.clear();overlay.hide()
    }
}
