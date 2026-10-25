import AppKit
import CopiloteKit

/// Invokes the action bound by the actual SwiftUI view through an opt-in headless seam.
/// The surrounding headless gate prevents ordering, key windows and desktop input ownership.
@MainActor
enum DiagnosticStealthConfirmation {
    static func run(folder:URL, overlay:OverlayController, settings:SettingsStore, listening:ListeningController,
                    assist:AssistController, session:SessionController, mainWindow:MainWindowController,
                    record:(String,Bool)->Void) async {
        guard DiagnosticAnchorFixture.isRequested,
              let pill = NSApp.windows.first(where:{$0.windowNumber == overlay.windowNumbers[0]}),
              let body = NSApp.windows.first(where:{$0.windowNumber == overlay.windowNumbers[1]}),
              let preferences = NSApp.windows.first(where:{$0.windowNumber == mainWindow.windowNumber}) else { return }
        var rows:[[String:Any]] = []
        var ownActivations = 0
        var spaceChanges = 0
        let workspace = NSWorkspace.shared.notificationCenter
        let activationObserver = workspace.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { note in
            if (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == ProcessInfo.processInfo.processIdentifier { ownActivations += 1 }
        }
        let spaceObserver = workspace.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,object:nil,queue:.main) { _ in spaceChanges += 1 }
        defer { workspace.removeObserver(activationObserver); workspace.removeObserver(spaceObserver) }
        func pause(_ ms:Int = 90) async { try? await Task.sleep(for:.milliseconds(ms)) }
        func marker(_ id:String, in view:NSView) -> NSView? {
            if view.identifier?.rawValue == id { return view }
            for child in view.subviews { if let found = marker(id,in:child) { return found } }
            return nil
        }
        func invokeBoundAction(_ id:String, in window:NSWindow) -> Bool {
            guard let content = window.contentView else { return false }
            content.layoutSubtreeIfNeeded()
            guard let target = marker(id,in:content), target.bounds.width > 0, target.bounds.height > 0 else { return false }
            return (target as? InlineControlMarker)?.invokeHeadlessAction() == true
        }
        func snapshot() -> [NSRect] { [pill.frame,body.frame,preferences.frame] }
        func geometry(_ name:String, _ before:[NSRect], stableBody:Bool = true) {
            let after = snapshot()
            let indices = stableBody ? [0,1,2] : [0,2]
            let delta = indices.map { max(abs(after[$0].minX-before[$0].minX),abs(after[$0].minY-before[$0].minY)) }.max() ?? 0
            rows.append(["name":name,"before":before.map(NSStringFromRect),"after":after.map(NSStringFromRect),"maxRequiredOriginDelta":delta])
            record(name + " keeps native origins", delta < 0.01)
        }
        settings.requestStealth(true,from:.pill)
        WindowPrivacy.authorizeFromUserGesture(); overlay.present(); mainWindow.show(); await pause(300)
        for source in [StealthChoice.Source.pill,.settings] {
            let owner = source == .pill ? pill : preferences
            let requestID = source == .pill ? "StealthRequestPill" : "StealthRequestSettings"
            let tag = source.rawValue
            for iteration in 1...3 {
                let before = snapshot()
                let preferenceBefore = settings.defaults.object(forKey:"stealth") as? Bool
                let requested = invokeBoundAction(requestID,in:owner)
                await pause()
                record("\(tag) \(iteration) bound request action",requested)
                guard let pending = settings.pendingStealthOff else {
                    record("\(tag) inline request exists",false); continue
                }
                if iteration == 1, let view = owner.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    try? bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("confirmation-\(tag)-fictional.png"))
                }
                record("\(tag) first request keeps sharing and persisted policy ON",settings.stealth && WindowPrivacy.enabled && owner.sharingType == .none && (settings.defaults.object(forKey:"stealth") as? Bool) == preferenceBefore)
                geometry("\(tag) request \(iteration)",before)
                settings.requestStealth(false,from:source)
                record("\(tag) repeated request is idempotent",settings.pendingStealthOff == pending)
                record("\(tag) bound Cancel action",invokeBoundAction("StealthCancel",in:owner))
                await pause(); settings.confirmStealthOff(pending.id)
                record("\(tag) cancel invalidates stale confirmation",settings.stealth && settings.pendingStealthOff == nil)
                geometry("\(tag) cancel \(iteration)",before)

                _ = invokeBoundAction(requestID,in:owner); await pause()
                let escaped = settings.pendingStealthOff?.id
                if let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:owner.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53) { owner.sendEvent(event) }
                if let escaped { settings.confirmStealthOff(escaped) }
                record("\(tag) own-window Escape cancels",escaped != nil && settings.stealth && settings.pendingStealthOff == nil)

                _ = invokeBoundAction(requestID,in:owner); await pause()
                let confirmed = settings.pendingStealthOff?.id
                record("\(tag) bound Confirm off action",invokeBoundAction("StealthConfirmOff",in:owner))
                await pause()
                record("\(tag) explicit confirmation permits sharing and persists OFF",!settings.stealth && !WindowPrivacy.enabled && owner.sharingType == .readOnly && !SettingsStore(defaults:settings.defaults,loadCredentials:false).stealth)
                if let confirmed { settings.confirmStealthOff(confirmed) }
                record("\(tag) duplicate confirmation stays OFF",!settings.stealth && settings.pendingStealthOff == nil)
                geometry("\(tag) confirmed OFF \(iteration)",before)
                record("\(tag) bound ON action",invokeBoundAction(requestID,in:owner)); await pause()
                record("\(tag) ON is immediate",settings.stealth && settings.pendingStealthOff == nil && owner.sharingType == .none)
                geometry("\(tag) ON \(iteration)",before)
            }
            for reason in ["close","focus","suspend","session-start","session-pause"] {
                settings.requestStealth(true,from:source)
                WindowPrivacy.authorizeFromUserGesture(); overlay.present(); mainWindow.show(); await pause()
                _ = invokeBoundAction(requestID,in:owner); await pause()
                let stale = settings.pendingStealthOff?.id
                switch reason {
                case "close": owner.orderOut(nil)
                case "focus": NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:owner)
                case "suspend": WindowPrivacy.suspend()
                case "session-start": listening.beginRecetteConversation()
                default:
                    listening.beginRecetteConversation()
                    settings.requestStealth(false,from:source)
                    listening.pauseOrResume()
                }
                await pause()
                if let stale { settings.confirmStealthOff(stale) }
                record("\(tag) \(reason) invalidates pending OFF",stale != nil && settings.stealth && settings.pendingStealthOff == nil)
                await listening.stop()
                WindowPrivacy.authorizeFromUserGesture(); overlay.present(); mainWindow.show(); await pause()
                record("\(tag) reopen never confirms or replays request",settings.stealth && settings.pendingStealthOff == nil)
            }
        }

        // Further view-bound actions retain the root and settings; visible hit testing is deferred.
        for id in ["PillAsk","PillPrivacyHelp","PillPrivacyHelp","PillFold","PillFold","PillAutoAnswer","PillAutoAnswer","PillMenu"] {
            let before = snapshot()
            let help = overlay.model.showsPrivacyHelp, folded = overlay.model.isUnfolded, automatic = settings.autoAnswer
            let pressed = invokeBoundAction(id,in:pill); await pause(250)
            record("bound control action \(id)",pressed)
            switch id {
            case "PillAsk": record("Ask action enters typing",overlay.model.isTyping)
            case "PillPrivacyHelp": record("privacy help action changes content",overlay.model.showsPrivacyHelp != help)
            case "PillFold": record("fold action changes presentation",overlay.model.isUnfolded != folded)
            case "PillAutoAnswer": record("Auto action changes preference",settings.autoAnswer != automatic)
            default: break
            }
            geometry("control \(id)",before,stableBody:id != "PillFold")
        }
        overlay.endTyping(); overlay.reveal()
        let mover = OverlayMovementShortcuts(overlay:overlay,register:false)
        defer { mover.stop() }
        overlay.startTyping(); await pause()
        let beforeTyping = snapshot()
        mover.moveIfAllowed(.left)
        record("Ask blocks workspace movement registration",!mover.enabled && pill.frame == beforeTyping[0])
        let editor = NSTextView(frame:NSRect(x:0,y:0,width:100,height:30))
        body.contentView?.addSubview(editor); _ = body.makeFirstResponder(editor)
        editor.string = "alpha beta"; editor.setSelectedRange(NSRange(location:10,length:0))
        if let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:body.windowNumber,context:nil,characters:"\u{F702}",charactersIgnoringModifiers:"\u{F702}",isARepeat:false,keyCode:123) { editor.keyDown(with:event) }
        record("own editor Command Left moves caret instead of group",editor.selectedRange().location == 0 && pill.frame == beforeTyping[0])
        _ = body.makeFirstResponder(nil); editor.removeFromSuperview(); overlay.endTyping()
        func askField(in view:NSView) -> OverlayAskTextField? {
            if let field = view as? OverlayAskTextField { return field }
            return view.subviews.lazy.compactMap { askField(in:$0) }.first
        }
        overlay.startTyping(); await pause()
        if let content = body.contentView, let field = askField(in:content), let delegate = field.delegate {
            let before = snapshot()
            let cancelled = delegate.control?(field,textView:editor,doCommandBy:#selector(NSResponder.cancelOperation(_:))) == true
            record("Ask native delegate Escape ends typing",cancelled && !overlay.model.isTyping)
            geometry("Ask delegate Escape",before)
            overlay.startTyping(); assist.askText = "Fictional native Return check"; await pause()
            let count = session.history.count
            let submitted = delegate.control?(field,textView:editor,doCommandBy:#selector(NSResponder.insertNewline(_:))) == true
            for _ in 0..<100 { await pause(10); if !session.isAnswering && session.history.count > count { break } }
            record("Ask native delegate Return submits and releases typing",submitted && !overlay.model.isTyping && !session.isAnswering && session.history.count > count)
            geometry("Ask delegate Return",before)
        } else { record("Ask native field and delegate available",false) }
        overlay.recenter(); let moveStart = pill.frame; mover.moveIfAllowed(.left)
        record("explicit keyboard movement action moves native group",mover.enabled && pill.frame != moveStart && body.parent === pill)
        overlay.hide(); mover.moveIfAllowed(.right)
        record("hidden workspace releases movement",!mover.enabled)
        record("all confirmation/control checks remained headless",ownActivations == 0 && !NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
        let report:[String:Any] = ["geometry":rows,"entryPoints":["pill","settings"],"input":"View-bound action callbacks via opt-in native markers, own-window Escape and native Ask delegate; no mouse events", "physicalClicksTested":false,"desktopCapture":false,"audio":false,"ownApplicationActivations":ownActivations,"spaceChangesObserved":spaceChanges,"nativeVisibleFocusTested":false,"headlessOffActivationPolicy":"accessory; regular activation deferred until safe visible test"]
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("stealth-confirmation.json"))
    }
}
