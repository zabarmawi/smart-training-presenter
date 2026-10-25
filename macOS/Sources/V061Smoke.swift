import AppKit
import SwiftUI
import PDFKit

// Opt-in acceptance runner. It only uses the isolated cache supplied by the test
// script; no meeting or other application's windows are controlled here.
@MainActor enum V061Smoke {
    static var started=false
    static func run(_ store:PresenterStore,args:[String])->Bool {
        if let i=args.firstIndex(of:"--v061-theme-restore"),args.count>i+1 {
            guard !started else {return true};started=true
            let ok=UIAppearance.shared.theme == .sand
            try? (ok ? "PASS: theme restored after executable restart":"FAIL: theme restore").write(toFile:args[i+1],atomically:true,encoding:.utf8)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2){NSApp.terminate(nil)};return true
        }
        guard let i=args.firstIndex(of:"--v061-acceptance"),args.count>i+2 else {return false}
        guard !started else {return true};started=true
        NSApp.accessibilitySetValue(NSNumber(value:true),forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        let out=URL(fileURLWithPath:args[i+1]),fixture=URL(fileURLWithPath:args[i+2])
        Task {
            do {
                try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
                AcceptanceSmoke.output=out;AcceptanceSmoke.rows=[]
                await AcceptanceSmoke.wait(1)
                try await exercise(store,out:out,fixture:fixture)
            } catch {AcceptanceSmoke.record(false,error.localizedDescription)}
            try? AcceptanceSmoke.rows.joined(separator:"\n").write(to:out.appendingPathComponent("results.txt"),atomically:true,encoding:.utf8)
            store.sharing.close();store.checkpoint();NSApp.terminate(nil)
        }
        return true
    }
    static func enterPage(_ text:String,window:NSWindow)->Bool {
        guard let element=UISmoke.nodes(window).first(where:{UISmoke.value($0,"accessibilityIdentifier") as? String=="jumpPage"}) else {return false}
        let selector=NSSelectorFromString("accessibilityFrame")
        guard element.responds(to:selector) else {return false}
        typealias FrameGetter = @convention(c) (AnyObject,Selector)->CGRect
        let getter=unsafeBitCast(element.method(for:selector),to:FrameGetter.self)
        let rect=getter(element,selector),point=window.convertPoint(fromScreen:NSPoint(x:rect.midX,y:rect.midY))
        guard let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1),let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime+0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0) else {return false}
        // Text selection tracks until mouseUp inside mouseDown. Queue release
        // before dispatching down, so this test never waits for a human click.
        NSApp.postEvent(up,atStart:true);window.sendEvent(down)
        guard let editor=window.firstResponder as? NSTextView else {return false}
        editor.selectAll(nil);editor.insertText(text,replacementRange:editor.selectedRange())
        if let event=NSEvent.keyEvent(with:.keyDown,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36) {window.sendEvent(event)}
        return true
    }
    static func exercise(_ store:PresenterStore,out:URL,fixture:URL)async throws {
        func check(_ ok:Bool,_ text:String){AcceptanceSmoke.record(ok,text)}
        func wait(_ seconds:Double)async {await AcceptanceSmoke.wait(seconds)}
        guard let trainer=NSApp.windows.first(where:{$0.title==SharingSession.trainerTitle}) else {throw PresenterError.message("No trainer window")}
        trainer.setContentSize(NSSize(width:1280,height:900));trainer.makeKeyAndOrderFront(nil)
        store.project=try DocumentReader.load(fixture);store.projectEpoch=UUID();store.loadDisplay()
        store.project.preferences.sound=false
        store.project.materials[0].libraryRole="slides"
        let slides=store.project.materials[0]
        guard let bag=store.library.bags.first,let project=try? DocumentReader.load(TrainingLibrary.projectURL(bag.id)),let t=project.materials.first(where:{$0.libraryRole=="trainer"}),let l=project.materials.first(where:{$0.libraryRole=="learner"}) else {throw PresenterError.message("Missing isolated guide fixtures")}
        store.project.materials += [t,l]
        guard let activity=store.project.activities.first(where:{$0.approved}) else {throw PresenterError.message("No approved fixture activity")}
        store.selectActivity(activity.id);store.setFollowing(true);store.navigate(4,follow:false);store.toggle()
        let source=Evidence(fileID:t.id,filename:t.name,page:3,excerpt:"مصدر اختبار",seconds:600)
        store.project.activities[0].evidence=[source]
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let original=try encoder.encode(store.project.activities),anchor=store.timer.anchor,used=store.timer.used(continuousSeconds())
        await wait(0.7)
        UISmoke.capture(trainer,out.appendingPathComponent("initial-trainer.png").path)
        let identifiers=UISmoke.nodes(trainer).map{"\(type(of:$0)) | \(UISmoke.value($0,"accessibilityIdentifier") ?? "") | \(UISmoke.value($0,"accessibilityLabel") ?? "")"}
        try identifiers.joined(separator:"\n").write(to:out.appendingPathComponent("initial-accessibility.txt"),atomically:true,encoding:.utf8)
        check(NSApp.windows.filter{$0.title==SharingSession.audienceTitle}.isEmpty,"trainer-only launch has no audience window")
        store.sharing.setMode(.single)
        check(UISmoke.press("toggleSharedPresentation",window:trainer),"actual open sharing button")
        await wait(1)
        guard let audience=store.sharing.window else {throw PresenterError.message("No audience window")}
        let publicDoc=store.sharing.presentation.document
        check(store.sharing.effectiveMode == .single && audience.collectionBehavior.contains(.fullScreenNone),"single mode disables native Spaces fullscreen")
        let frame=audience.frame
        store.sharing.maximize();await wait(0.4)
        check(audience.frame.width>=frame.width && !audience.styleMask.contains(.fullScreen),"maximize audience inside a normal window")
        trainer.makeKeyAndOrderFront(nil);await wait(0.4)
        check(!audience.isKeyWindow && audience.isVisible,"audience remains visible while trainer takes focus")
        store.navigate(5,follow:false);await wait(0.5)
        check(store.sharing.presentation.page==5,"public page updates while trainer is key")
        func canvas(_ view:NSView)->SharedSlideView? {if let view=view as? SharedSlideView {return view};return view.subviews.compactMap{canvas($0)}.first}
        guard let surface=audience.contentView.flatMap({canvas($0)}) else {throw PresenterError.message("No persistent audience surface")}
        if let image=surface.retainedImage {
            let bitmap=NSBitmapImageRep(cgImage:image),box=surface.page!.bounds(for:.cropBox)
            let ratio=Double(image.width)/Double(image.height)
            check(abs(ratio-Double(box.width/box.height))<0.02,"audience preserves original page aspect ratio")
            var bright=0
            for x in stride(from:0,to:bitmap.pixelsWide,by:max(1,bitmap.pixelsWide/30)) {
                for y in stride(from:0,to:bitmap.pixelsHigh,by:max(1,bitmap.pixelsHigh/20)) {
                    if let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),max(c.redComponent,max(c.greenComponent,c.blueComponent))>0.15 {bright+=1}
                }
            }
            check(bright>50,"audience page raster contains visible non-black pixels")
        }
        check(surface.retainedImage != nil && surface.page === publicDoc?.page(at:5),"durable page layer populated independent of draw callback")
        audience.orderBack(nil);trainer.setFrame(audience.frame,display:true);await wait(0.5)
        store.navigate(6,follow:false);await wait(0.5)
        check(surface.retainedImage != nil && surface.page === publicDoc?.page(at:6),"occluded audience updates durable pixels")
        audience.miniaturize(nil);await wait(0.8)
        check(!audience.isMiniaturized,"audience minimization is restored to retain capture surface")
        let sharedPage=store.sharing.presentation.page
        check(UISmoke.press("openTrainerGuide",window:trainer),"actual trainer guide button")
        await wait(0.4)
        check(store.material?.id==t.id && store.document != nil,"trainer PDF actually loaded")
        check(UISmoke.press("nextPage",window:trainer),"actual guide next page button")
        check(enterPage("12",window:trainer),"actual page field receives text and Return")
        await wait(0.3)
        check(store.project.currentPage==11 && store.sharing.presentation.document === publicDoc && store.sharing.presentation.page==sharedPage,"guide page jump stays private")
        check(UISmoke.press("openLearnerGuide",window:trainer),"actual learner guide button")
        await wait(0.4);store.navigate(8)
        check(store.material?.id==l.id && store.document != nil && store.sharing.presentation.page==sharedPage,"learner PDF loads privately")
        _=UISmoke.press("openTrainerGuide",window:trainer);await wait(0.3)
        check(store.project.currentPage==11,"trainer guide prior position restored")
        _=UISmoke.press("returnToPresentation",window:trainer);await wait(0.4)
        check(store.material?.id==slides.id && store.project.currentPage==sharedPage,"return restores prior public slide position")
        _=UISmoke.press("openReview",window:trainer);store.selectedReview=activity.id;await wait(0.5)
        if let sheet=trainer.attachedSheet {check(UISmoke.press("sourceEvidence:"+source.id,window:sheet),"actual show-time-source button")} else {check(false,"review source sheet opened")}
        await wait(0.4)
        check(store.material?.id==t.id && store.project.currentPage==2 && store.sharing.presentation.page==sharedPage,"source preview retains private page semantics")
        store.returnToPresentation();await wait(0.4)
        check(store.project.currentActivity==activity.id && store.timer.anchor==anchor && store.timer.running && store.timer.used(continuousSeconds())>used,"file browsing preserves active activity and running timer anchor")
        check(original == (try encoder.encode(store.project.activities)),"guide browsing never changes durations approvals IDs or evidence")
        let missing=Material(id:"missing",path:out.appendingPathComponent("missing.pdf").path,hash:"",renderedPath:out.appendingPathComponent("missing.pdf").path,pages:1,libraryRole:"trainer")
        let corruptURL=out.appendingPathComponent("corrupt.pdf");try Data("not a PDF".utf8).write(to:corruptURL)
        let corrupt=Material(id:"corrupt",path:corruptURL.path,hash:"",renderedPath:corruptURL.path,pages:1,libraryRole:"learner")
        store.project.materials += [missing,corrupt]
        store.selectFile(missing.id);check(store.document==nil && store.displayMessage?.contains("مفقود")==true,"missing guide gives explicit message")
        store.selectFile(corrupt.id);check(store.document==nil && TimingExtractor.normalized(store.displayMessage ?? "").contains("تالف"),"corrupt guide gives explicit message")
        try (store.displayMessage ?? "").write(to:out.appendingPathComponent("corrupt-message.txt"),atomically:true,encoding:.utf8)
        store.returnToPresentation();await wait(0.4)
        var imageHash:String?
        for theme in PresenterTheme.allCases {
            UIAppearance.shared.theme=theme;await wait(0.5)
            check(UIAppearance.load()==theme,"theme persisted: "+theme.rawValue)
            if let image=surface.retainedImage {
                let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!
                let url=out.appendingPathComponent("slide-"+theme.rawValue+".png");try data.write(to:url)
                let hash=try DocumentReader.digest(url)
                if let prior=imageHash {check(hash==prior,"original PDF pixels unchanged: "+theme.rawValue)} else {imageHash=hash}
            }
            UISmoke.capture(trainer,out.appendingPathComponent("theme-"+theme.rawValue+".png").path)
            UISmoke.capture(audience,out.appendingPathComponent("audience-"+theme.rawValue+".png").path)
            check(store.timer.running && store.timer.anchor==anchor,"theme leaves clock untouched: "+theme.rawValue)
        }
        UIAppearance.shared.theme = .sand
        let labels=UISmoke.nodes(trainer).map{String(describing:UISmoke.value($0,"accessibilityLabel") ?? "")}.joined(separator:"\n")
        check(!labels.contains("Chat Completions") && !labels.contains("مفتاح الخدمة"),"no external analysis controls in trainer")
        store.settings=true;await wait(0.5)
        if let sheet=trainer.attachedSheet {
            let tree=UISmoke.nodes(sheet),ids=tree.compactMap{UISmoke.value($0,"accessibilityIdentifier") as? String}
            let text=tree.map{String(describing:UISmoke.value($0,"accessibilityLabel") ?? "")}.joined(separator:"\n")
            check(ids.contains("themePicker") && !text.contains("نموذج لغوي") && !text.contains("مفتاح الخدمة"),"settings shows themes without cancelled model feature")
        } else {check(false,"settings sheet opened")}
        store.settings=false;await wait(0.4)
        let help=UISmoke.nodes(trainer).compactMap{UISmoke.value($0,"accessibilityHelp") as? String}.filter{!$0.isEmpty}
        try help.joined(separator:"\n").write(to:out.appendingPathComponent("accessibility-help.txt"),atomically:true,encoding:.utf8)
        check(help.count>=6,"Arabic tooltip help exposed to accessibility")
        AcceptanceSmoke.note("NOT TESTED: visual hover tooltip timing needs a real pointer; native help metadata checked")
        store.sharing.setMode(.automatic);await wait(0.5)
        let physical=NSScreen.screens.count
        check(store.sharing.screenCount==physical && store.sharing.effectiveMode == (physical>1 ? .dual:.single),"auto mode follows actual connected screen count")
        if physical>1 {
            check(audience.screen === NSScreen.screens[1],"audience placed on physical second screen")
            await AcceptanceSmoke.fullscreen(audience,label:"audience",store:store)
        } else {AcceptanceSmoke.note("NOT TESTED: second physical display unavailable")}
        if physical != 1 {AcceptanceSmoke.note("NOT TESTED: one physical display only; manual single mode exercised with existing displays")}
        NotificationCenter.default.post(name:NSApplication.didChangeScreenParametersNotification,object:nil);await wait(0.4)
        check(store.sharing.isOpen && store.timer.running && store.sharing.presentation.document != nil,"screen-change notification preserves state")
        AcceptanceSmoke.note("NOT TESTED: physical display unplug during capture")
        await AcceptanceSmoke.fullscreen(trainer,label:"trainer",store:store)
        AcceptanceSmoke.checkAudience(store,"final privacy")
        try DocumentReader.save(store.project,to:out.appendingPathComponent("positions.stpresenter"),now:continuousSeconds())
        let reopened=try DocumentReader.load(out.appendingPathComponent("positions.stpresenter"))
        check(reopened.filePages?[t.id]==2 && reopened.filePages?[l.id]==8,"per-file page positions survive save and reopen")
        try JSONSerialization.data(withJSONObject:["physicalScreens":physical,"screenFrames":NSScreen.screens.map{NSStringFromRect($0.frame)},"teamsPeer":"NOT TESTED","fullscreenEvents":AcceptanceSmoke.events],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("environment.json"))
        AcceptanceSmoke.note("NOT TESTED: actual Teams participant capture; no meeting/participant controlled")
    }
}
