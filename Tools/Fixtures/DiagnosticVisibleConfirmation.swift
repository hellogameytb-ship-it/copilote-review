import AppKit
import CopiloteKit

/// Supplementary visible harness; copied into a separate source tree, never into the installed candidate.
@MainActor
enum DiagnosticVisibleConfirmation {
    static func run(folder:URL, overlay:OverlayController, settings:SettingsStore, listening:ListeningController,
                    assist:AssistController, session:SessionController, mainWindow:MainWindowController,
                    menu:PillMenuController) async {
        var checks:[[String:Any]] = [], frames:[[String:Any]] = []
        func record(_ name:String,_ passed:Bool) {
            checks.append(["name":name,"passed":passed])
            let report:[String:Any] = ["checks":checks,"frames":frames,"hardwareCapture":false,"desktopCapture":false,
                "input":"Mouse events sent only to own visible NSWindow; native field editor; no global posting or cursor warp",
                "physicalMouseDeviceTested":false,"isolatedPreferences":true,"fakeProvider":true]
            try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("visible.json"),options:.atomic)
        }
        func pause(_ ms:Int = 180) async { try? await Task.sleep(for:.milliseconds(ms)) }
        guard let pill = NSApp.windows.first(where:{$0.windowNumber == overlay.windowNumbers[0]}),
              let body = NSApp.windows.first(where:{$0.windowNumber == overlay.windowNumbers[1]}),
              let preferences = NSApp.windows.first(where:{$0.windowNumber == mainWindow.windowNumber}),let screen=NSScreen.main else { record("native fixture windows",false);return }
        func marker(_ id:String,_ view:NSView)->NSView? {
            if view.identifier?.rawValue == id {return view}
            return view.subviews.lazy.compactMap {marker(id,$0)}.first
        }
        func click(_ id:String,_ window:NSWindow)->Bool {
            guard window.isVisible,let content=window.contentView else{return false}
            content.layoutSubtreeIfNeeded()
            guard let target=marker(id,content),target.bounds.width>0,target.bounds.height>0 else{return false}
            // A switch label is not its track: target the measured right-hand switch, not the label midpoint.
            let x=id == "PillAutoAnswer" ? target.bounds.maxX-16:target.bounds.midX
            let point=target.convert(NSPoint(x:x,y:target.bounds.midY),to:nil)
            for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
                guard let event=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1) else{return false}
                window.sendEvent(event)
            }
            return true
        }
        func escape(_ window:NSWindow) {
            if let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53) {window.sendEvent(event)}
        }
        func snapshot()->[NSRect] {[pill.frame,body.frame,preferences.frame]}
        func stable(_ name:String,_ before:[NSRect],bodyRequired:Bool=true) {
            let after=snapshot(),indices=bodyRequired ? [0,1,2]:[0,2]
            let delta=indices.map {max(abs(before[$0].minX-after[$0].minX),abs(before[$0].minY-after[$0].minY))}.max() ?? 0
            frames.append(["name":name,"before":before.map(NSStringFromRect),"after":after.map(NSStringFromRect),"requiredOriginDelta":delta])
            record(name+" keeps origins",delta<0.01)
        }
        let focusWindow=OverlayPanel(size:NSSize(width:240,height:100),resizable:false)
        focusWindow.title="Fictional focus target";focusWindow.allowsKey=true
        let focusField=NSTextField(string:"Fictional input");focusWindow.contentView=focusField
        settings.requestStealth(true,from:.pill);WindowPrivacy.authorizeFromUserGesture();overlay.present()
        await pause(400)
        record("visible fixture remains idle",pill.isVisible && body.isVisible && !listening.isListening)
        if ProcessInfo.processInfo.arguments.contains("-RecetteAutoOnly") {
            for iteration in 1...2 {
                let before=snapshot(),value=settings.autoAnswer
                let pressed=click("PillAutoAnswer",pill);await pause()
                record("actual Auto switch click \(iteration)",pressed && settings.autoAnswer != value)
                record("Auto keeps Stealth ON without taking keyboard \(iteration)",settings.stealth && !pill.isKeyWindow && !body.isKeyWindow)
                stable("Auto switch \(iteration)",before)
            }
            overlay.hide();record("Auto-only fixture finishes hidden idle",NSApp.windows.allSatisfy{!$0.isVisible} && !listening.isListening)
            return
        }
        let area=screen.visibleFrame
        for (index,origin) in [NSPoint(x:area.midX-300,y:area.maxY-80),NSPoint(x:area.minX+40,y:area.maxY-170),NSPoint(x:area.maxX-640,y:area.minY+680)].enumerated() {
            pill.setFrameOrigin(origin);await pause()
            let before=snapshot(),count=session.history.count
            let front=NSWorkspace.shared.frontmostApplication?.processIdentifier
            record("Ask click target \(index)",click("PillAsk",pill));await pause(400)
            record("Ask click owns native keyboard \(index)",overlay.model.isTyping && body.isKeyWindow && body.firstResponder is NSTextView)
            if let editor=body.firstResponder as? NSTextView {
                editor.insertText("Fictional visible question \(index)",replacementRange:NSRange(location:NSNotFound,length:0))
                editor.doCommand(by:#selector(NSResponder.insertNewline(_:)))
            }
            for _ in 0..<80 {await pause(20);if !session.isAnswering && session.history.count>count {break}}
            record("Return submits and releases actual keyboard \(index)",!overlay.model.isTyping && !body.isKeyWindow && session.history.count>count && !session.isAnswering)
            record("nonactivating Ask preserves front application \(index)",NSWorkspace.shared.frontmostApplication?.processIdentifier == front)
            stable("Ask Return \(index)",before)
            _=click("PillAsk",pill);await pause(350);escape(body);await pause()
            record("Ask Escape releases actual keyboard \(index)",!overlay.model.isTyping && !body.isKeyWindow)
            stable("Ask Escape \(index)",before)
            overlay.hide();await pause();WindowPrivacy.authorizeFromUserGesture();overlay.present();await pause()
            record("hide reveal restores visible native group \(index)",pill.isVisible && body.isVisible && body.parent === pill)
            stable("hide reveal \(index)",before)
        }
        for source in [StealthChoice.Source.pill,.settings] {
            let owner=source == .pill ? pill:preferences
            let id=source == .pill ? "StealthRequestPill":"StealthRequestSettings"
            if source == .settings {mainWindow.show()} else {mainWindow.close()}
            await pause()
            for iteration in 1...2 {
                let before=snapshot()
                record("\(source) request click \(iteration)",click(id,owner));await pause()
                record("\(source) first click stays ON with real confirmation keyboard",settings.stealth && settings.pendingStealthOff?.source == source && owner.isKeyWindow && owner.sharingType == .none)
                if iteration == 1 {DiagnosticSnapshot.write(to:folder.appendingPathComponent("confirmation-\(source)"),spaceChanges:0)}
                stable("\(source) request \(iteration)",before)
                record("\(source) cancel click",click("StealthCancel",owner));await pause()
                record("\(source) cancel stays ON",settings.stealth && settings.pendingStealthOff == nil)
                _=click(id,owner);await pause();escape(owner);await pause()
                record("\(source) Escape stays ON",settings.stealth && settings.pendingStealthOff == nil)
                _=click(id,owner);await pause()
                record("\(source) confirm click",click("StealthConfirmOff",owner));await pause(350)
                record("\(source) explicit OFF uses regular policy",!settings.stealth && settings.pendingStealthOff == nil && NSApp.activationPolicy() == .regular && owner.sharingType == .readOnly)
                record("\(source) ON click",click(id,owner));await pause(350)
                record("\(source) ON immediate accessory policy",settings.stealth && settings.pendingStealthOff == nil && NSApp.activationPolicy() == .accessory && owner.sharingType == .none)
                stable("\(source) full confirmation cycle \(iteration)",before)
            }
            _=click(id,owner);await pause()
            let request=settings.pendingStealthOff
            focusWindow.makeKeyAndOrderFront(nil);_ = focusWindow.makeFirstResponder(focusField);await pause()
            record("\(source) real focus transfer cancels pending OFF",request != nil && focusWindow.isKeyWindow && settings.pendingStealthOff == nil && settings.stealth)
            focusWindow.orderOut(nil)
            if source == .settings {mainWindow.show()}
            _=click(id,owner);await pause();let closing=settings.pendingStealthOff
            if source == .settings {mainWindow.close()} else {overlay.hide()}
            await pause();WindowPrivacy.authorizeFromUserGesture();overlay.present();if source == .settings {mainWindow.show()};await pause()
            record("\(source) close and reopen cannot replay confirmation",closing != nil && settings.pendingStealthOff == nil && settings.stealth)
        }
        mainWindow.close();await pause()
        for id in ["PillPrivacyHelp","PillPrivacyHelp","PillFold","PillFold","PillAutoAnswer","PillAutoAnswer","PillMenu"] {
            let before=snapshot();let help=overlay.model.showsPrivacyHelp,unfolded=overlay.model.isUnfolded,automatic=settings.autoAnswer
            let pressed=click(id,pill);await pause()
            var changed=true
            switch id {
            case "PillPrivacyHelp":changed=overlay.model.showsPrivacyHelp != help
            case "PillFold":changed=overlay.model.isUnfolded != unfolded
            case "PillAutoAnswer":changed=settings.autoAnswer != automatic
            case "PillMenu":changed=menu.isOpen
            default:break
            }
            record("visible control click \(id)",pressed && changed);stable(id,before,bodyRequired:id != "PillFold")
        }
        menu.close(restoringKeyboard:true);focusWindow.orderOut(nil);mainWindow.close();overlay.hide()
        record("visible fixture finishes hidden idle and Stealth ON",NSApp.windows.allSatisfy{!$0.isVisible} && !listening.isListening && settings.stealth)
    }
}
