import AppKit
import PDFKit

// Opt-in acceptance harness. Never runs in ordinary application launches.
@MainActor enum QA01Smoke {
    static var started=false
    static var outputFolder=""
    static func record(_ ok:Bool,_ name:String) {
        UISmoke.record(ok,name)
        try? UISmoke.rows.joined(separator:"\n").write(toFile:outputFolder+"/qa01-ui-results.txt",atomically:true,encoding:.utf8)
    }
    static func wait(_ seconds:Double) async {try? await Task.sleep(nanoseconds:UInt64(seconds*1e9))}
    static func setText(_ id:String,_ text:String,window:NSWindow)->Bool {
        guard let element=UISmoke.nodes(window).first(where:{UISmoke.value($0,"accessibilityIdentifier") as? String==id}) else {return false}
        // Editing the native field editor exercises NSTextInputClient and sends
        // change notifications; setting an AX display value alone does not.
        func fields(_ view:NSView)->[NSTextField] {
            (view is NSTextField ? [view as! NSTextField]:[]) + view.subviews.flatMap(fields)
        }
        guard let view=window.contentView else {return false}
        let candidates=fields(view).filter(\.isEditable)
        guard candidates.count==1,let field=candidates.first else {return false}
        _=element // The requested accessible field was verified above.
        window.makeFirstResponder(field);field.selectText(nil)
        guard let editor=window.fieldEditor(true,for:field) as? NSTextView else {return false}
        editor.insertText(text,replacementRange:NSRange(location:0,length:editor.string.utf16.count))
        return true
    }
    static func run(_ store:PresenterStore,args:[String])->Bool {
        if let index=args.firstIndex(of:"--qa01-fullscreen"),args.count>index+1 {
            guard !started else {return true};started=true;outputFolder=args[index+1]
            Task {
                await wait(2)
                guard let window=NSApp.windows.first(where:{$0.contentView != nil}) else {return}
                NSApp.accessibilitySetValue(NSNumber(value:true),forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
                window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
                await wait(0.5)
                record(window.isKeyWindow && NSApp.keyWindow===window,"fullscreen test window has actual keyboard focus")
                record(UISmoke.press("presentationFocus",window:window),"focused window presentation button pressed")
                await wait(5)
                record(window.styleMask.contains(.fullScreen),"focused presentation button enters native fullscreen")
                UISmoke.capture(window,outputFolder+"/fullscreen-focused.png")
                let initial="key=\(window.isKeyWindow) style=\(window.styleMask.rawValue) behavior=\(window.collectionBehavior.rawValue) windows=\(NSApp.windows.map{($0.title,$0.styleMask.rawValue,$0.isKeyWindow)})"
                try? initial.write(toFile:outputFolder+"/fullscreen-diagnostic.txt",atomically:true,encoding:.utf8)
                let entered=window.styleMask.contains(.fullScreen)
                if entered {
                    window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
                    await wait(0.5)
                    _=UISmoke.press("presentationFocus",window:window)
                } else {
                    // Diagnostic AppKit call: distinguishes host fullscreen support
                    // from a button/keyboard-focus issue; never changes defaults.
                    window.toggleFullScreen(nil)
                }
                await wait(5)
                record(entered ? !window.styleMask.contains(.fullScreen):window.styleMask.contains(.fullScreen),entered ? "focused presentation control exits native fullscreen":"diagnostic direct AppKit fullscreen state after toggle")
                if window.styleMask.contains(.fullScreen) {window.toggleFullScreen(nil);await wait(2)}
                store.checkpoint();NSApp.terminate(nil)
            }
            return true
        }
        guard let i=args.firstIndex(of:"--qa01-smoke"),args.count>i+1 else {return false}
        guard !started else {return true};started=true
        let folder=args[i+1]
        outputFolder=folder
        Task {
            await wait(2)
            guard let window=NSApp.windows.first(where:{$0.contentView != nil}) else {return}
            NSApp.accessibilitySetValue(NSNumber(value:true),forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            window.setContentSize(NSSize(width:1280,height:900))
            let bags=store.library.bags.filter{bag in
                let p=try? DocumentReader.load(TrainingLibrary.projectURL(bag.id))
                return p?.activities.contains{$0.catalogID?.hasPrefix("enable-learning-")==true}==true
            }
            record(bags.count==2,"locate exactly two affected bags")
            for (number,bag) in bags.enumerated() {
                for kind in ["نشاط","استراحة"] {
                    store.openLibraryBag(bag.id,review:true)
                    await wait(0.9)
                    guard let activity=store.project.activities.first(where:{$0.kind==kind}),let evidence=activity.evidence.first else {record(false,"sample exists");continue}
                    store.selectedReview=activity.id
                    await wait(0.5)
                    guard let sheet=window.attachedSheet else {record(false,"source review sheet exists");continue}
                    UISmoke.capture(sheet,folder+"/source-\(number+1)-\(kind)-before.png")
                    let pressed=UISmoke.press("sourceEvidence:"+evidence.id,window:sheet)
                    record(pressed,"press source button bag \(number+1) \(kind)")
                    await wait(2.5)
                    record(store.project.currentFile==evidence.fileID && store.project.currentPage==evidence.page-1 && store.document != nil && window.attachedSheet==nil,"source PDF visible at exact evidence page bag \(number+1) \(kind)")
                    UISmoke.capture(window,folder+"/source-\(number+1)-\(kind)-after.png")
                }
            }
            store.libraryVisible=true
            await wait(0.6)
            if let sheet=window.attachedSheet {
                record(setText("librarySearch","عمليات التعليم",window:sheet),"enter actual text through native field editor")
                await wait(0.5)
                let results=UISmoke.nodes(sheet).compactMap{UISmoke.value($0,"accessibilityIdentifier") as? String}.filter{$0.hasPrefix("libraryBag:")}
                let expected=store.library.bags.filter{$0.domain.contains("عمليات التعليم")}.map{"libraryBag:"+$0.id}
                record(Set(results)==Set(expected) && results.count==4,"search returns exactly four matching bags")
                UISmoke.capture(sheet,folder+"/search-matches.png")
                record(setText("librarySearch","NO-MATCH-QA01-2026",window:sheet),"enter unmatched query in actual search field")
                await wait(0.5)
                record(!UISmoke.nodes(sheet).contains{(UISmoke.value($0,"accessibilityIdentifier") as? String)?.hasPrefix("libraryBag:")==true},"unmatched search has zero bag rows")
                UISmoke.capture(sheet,folder+"/search-empty.png")
            } else {record(false,"library search sheet opens")}
            store.libraryVisible=false;await wait(0.5)
            if let bag=bags.first {store.openLibraryBag(bag.id)}
            guard let id=store.project.activities.first?.id else {return}
            store.approve(id);store.selectActivity(id)
            store.project.preferences.barMode="ثابت"
            await wait(0.4)
            record(UISmoke.press("extendPlus",window:window),"click +1 first")
            record(UISmoke.press("extendPlus",window:window),"click +1 second")
            record(UISmoke.press("extendMinus",window:window),"click minus one")
            record(store.proposed==1,"two increments minus one leaves one minute")
            let original=store.timer.original,extensions=store.timer.extensions
            record(UISmoke.press("confirmExtension",window:window),"click confirm extension")
            record(store.proposed==0 && store.timer.extensions==extensions+60 && store.timer.original==original,"confirmed extension adds sixty seconds and retains original")
            UISmoke.capture(window,folder+"/extension.png")
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            await wait(0.5)
            record(UISmoke.press("presentationFocus",window:window),"click fullscreen presentation control")
            await wait(5)
            record(window.styleMask.contains(.fullScreen),"window actually enters macOS fullscreen")
            UISmoke.capture(window,folder+"/fullscreen.png")
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            await wait(0.5)
            _=UISmoke.press("presentationFocus",window:window)
            await wait(5)
            record(!window.styleMask.contains(.fullScreen),"window exits fullscreen")
            store.project.preferences.visual=true;store.project.preferences.sound=false;store.project.preferences.noticeSeconds=2
            var timer=Countdown(600);timer.elapsed=599.7;timer.toggle(continuousSeconds())
            store.project.timers[id]=timer;store.notice=nil
            await wait(0.9)
            record(store.notice?.text.contains("انتهى الوقت")==true && store.timer.fired.contains(0),"real ticker crosses zero and displays finish notice")
            record(store.project.currentPage>=0 && store.timer.remaining(store.now)<0,"overtime continues with source page retained")
            UISmoke.capture(window,folder+"/finish-visible.png")
            await wait(2.2)
            record(store.notice==nil,"finish notice automatically disappears after configured duration")
            UISmoke.capture(window,folder+"/finish-expired.png")
            store.project.timers[id]?.pause(store.now)
            for threshold in [300,60,0] {
                record(store.playSound(threshold),"NSSound playback starts for threshold \(threshold)")
                await wait(2)
            }
            if args.count>i+2 {
                let ppt=URL(fileURLWithPath:args[i+2])
                do {
                    let before=try DocumentReader.digest(ppt)
                    let result=try await Task.detached {try DocumentReader.read(ppt)}.value
                    let pdf=result.material.renderedPath.flatMap{PDFDocument(url:URL(fileURLWithPath:$0))}
                    record(pdf?.pageCount==2,"actual PPTX conversion produces two-page PDF")
                    record(try DocumentReader.digest(ppt)==before,"PPTX fixture unchanged after conversion")
                    if pdf != nil {
                        store.project.materials.append(result.material);store.selectFile(result.material.id)
                        await wait(0.8);UISmoke.capture(window,folder+"/pptx-rendered.png")
                        store.navigate(1);await wait(0.4)
                        record(store.document?.pageCount==2 && store.project.currentPage==1,"converted PPTX displays and navigates in executable")
                        UISmoke.capture(window,folder+"/pptx-page-two.png")
                    } else {record(false,"PPTX conversion status: "+result.material.status)}
                } catch {record(false,"PPTX conversion: "+error.localizedDescription)}
            }
            try? UISmoke.rows.joined(separator:"\n").write(toFile:folder+"/qa01-ui-results.txt",atomically:true,encoding:.utf8)
            store.checkpoint();NSApp.terminate(nil)
        }
        return true
    }
}
