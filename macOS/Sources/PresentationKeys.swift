import AppKit
import PDFKit

// Local event monitor: never observes another app or installs a global shortcut.
@MainActor final class PresentationKeys {
    private var monitor:Any?
    func install(_ store:PresenterStore) {
        guard monitor == nil else {return}
        monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) {[weak store] event in
            guard let store=store else {return event}
            return Self.handle(event,store:store) ? nil:event
        }
    }
    static func delta(_ key:UInt16)->Int? {
        switch key {
        case 121,124,125,49:return 1 // Page Down, Right, Down, Space
        case 116,123,126,51:return -1 // Page Up, Left, Up, Backspace
        default:return nil
        }
    }
    static func handle(_ event:NSEvent,store:PresenterStore)->Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,
              let offset=delta(event.keyCode),let window=event.window,
              window === NSApp.keyWindow,NSApp.modalWindow == nil,
              window.attachedSheet == nil,window.sheetParent == nil,
              !store.busy,!store.libraryVisible,!store.review,!store.settings,
              !store.timeConflictsVisible,store.error == nil,
              store.document != nil else {return false}
        let audience=window === store.sharing.window
        let trainer=window.title == SharingSession.trainerTitle
        let panel=window === store.sharing.controls.window
        guard trainer || audience || panel else {return false}
        // Source previews stay private; the audience clicker must not turn guide pages.
        guard !store.privatePreview else {return false}
        var responder:NSResponder?=window.firstResponder
        while let current=responder {
            if current is NSTextView || current is NSTextField || current is NSComboBox || current is NSSearchField {return false}
            // Keep list selection, sliders and button Space activation native.
            if event.keyCode != 121 && event.keyCode != 116,
               current is NSTableView || current is NSOutlineView || current is NSCollectionView || current is NSSlider || current is NSPopUpButton {return false}
            if current is NSButton && event.keyCode == 49 {return false}
            responder=current.nextResponder
            if responder === window {break}
        }
        if !event.isARepeat {store.navigate(store.project.currentPage+offset)}
        // Consume handled events even at bounds/repeat: PDFKit must not advance twice.
        return true
    }
}

// Explicit, isolated executable acceptance test. Sends real local key events through
// NSApplication's event dispatch, including both actual presentation windows.
@MainActor enum PresentationKeysSmoke {
    static var started=false
    static func run(_ store:PresenterStore,args:[String])->Bool {
        guard let i=args.firstIndex(of:"--pointer-acceptance"),args.count>i+1 else {return false}
        guard !started else {return true};started=true
        let out=URL(fileURLWithPath:args[i+1])
        Task {
            var rows:[String]=[]
            func check(_ ok:Bool,_ name:String) {rows.append((ok ? "PASS: ":"FAIL: ")+name)}
            await AcceptanceSmoke.wait(1)
            guard let trainer=NSApp.windows.first(where:{$0.title==SharingSession.trainerTitle}) else {NSApp.terminate(nil);return}
            let pdf=PDFDocument()
            for n in 1...8 {
                let image=NSImage(size:NSSize(width:960,height:540));image.lockFocus()
                NSColor.white.setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:960,height:540)).fill()
                ("Pointer acceptance — slide \(n)" as NSString).draw(at:NSPoint(x:80,y:250),withAttributes:[.font:NSFont.systemFont(ofSize:32),.foregroundColor:NSColor.black]);image.unlockFocus()
                if let page=PDFPage(image:image) {pdf.insert(page,at:pdf.pageCount)}
            }
            store.project=Project();store.projectURL=nil;store.project.preferences.followSlides=false
            store.document=pdf;store.libraryVisible=false;store.review=false;store.settings=false
            store.project.preferences.sound=false
            // A synthetic document exists only in this test's cache.
            try? FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            let path=out.appendingPathComponent("synthetic.pdf");pdf.write(to:path)
            let material=Material(path:path.path,hash:"synthetic",pages:8,libraryRole:"slides")
            store.project.materials=[material];store.project.currentFile=material.id
            store.sharing.open();await AcceptanceSmoke.wait(0.4)
            func send(_ key:UInt16,_ window:NSWindow,flags:NSEvent.ModifierFlags=[],repeatKey:Bool=false) {
                if let e=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:repeatKey,keyCode:key) {NSApp.sendEvent(e)}
            }
            for (name,window) in [("trainer",trainer),("audience",store.sharing.window!)] {
                window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);window.makeFirstResponder(window.contentView)
                await AcceptanceSmoke.wait(0.15)
                for key:UInt16 in [121,116,124,123,125,126,49,51] {
                    store.navigate(3,follow:false);send(key,window)
                    check(store.project.currentPage == 3+PresentationKeys.delta(key)!,"\(name): key \(key) advances exactly one slide")
                }
                store.navigate(0,follow:false);send(116,window);check(store.project.currentPage==0,"\(name): first-page boundary")
                store.navigate(7,follow:false);send(121,window);check(store.project.currentPage==7,"\(name): last-page boundary")
                store.navigate(3,follow:false);send(121,window,repeatKey:true);check(store.project.currentPage==3,"\(name): held key does not race through slides")
                send(121,window,flags:.option);check(store.project.currentPage==3,"\(name): modified keys preserved")
            }
            trainer.makeKeyAndOrderFront(nil)
            let text=NSTextView(frame:NSRect(x:0,y:0,width:120,height:35));trainer.contentView?.addSubview(text);trainer.makeFirstResponder(text)
            store.navigate(3,follow:false);send(121,trainer);send(49,trainer);check(store.project.currentPage==3,"text input keeps Page Down and Space")
            text.removeFromSuperview();trainer.makeFirstResponder(trainer.contentView)
            store.review=true;send(121,trainer);check(store.project.currentPage==3,"review sheet state blocks clicker");store.review=false
            store.privatePreview=true;send(121,trainer);check(store.project.currentPage==3,"private source preview stays unchanged");store.privatePreview=false
            let dialog=NSWindow(contentRect:NSRect(x:0,y:0,width:180,height:80),styleMask:[.titled],backing:.buffered,defer:false)
            dialog.makeKeyAndOrderFront(nil);send(121,dialog);check(store.project.currentPage==3,"unrelated app dialog ignored");dialog.close()
            try? rows.joined(separator:"\n").write(to:out.appendingPathComponent("results.txt"),atomically:true,encoding:.utf8)
            store.sharing.close();store.checkpoint();NSApp.terminate(nil)
        }
        return true
    }
}
