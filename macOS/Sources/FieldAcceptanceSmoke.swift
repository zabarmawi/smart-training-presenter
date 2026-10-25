import Foundation
import AppKit
import PDFKit

@MainActor enum FieldAcceptanceSmoke {
    static var started=false
    static var output=URL(fileURLWithPath:"/tmp")
    static var rows:[String]=[]
    static func check(_ ok:Bool,_ name:String) {rows.append((ok ? "PASS: ":"FAIL: ")+name);save()}
    static func note(_ name:String) {rows.append("NOT TESTED: "+name);save()}
    static func save() {try? rows.joined(separator:"\n").write(to:output.appendingPathComponent("results.txt"),atomically:true,encoding:.utf8)}
    static func wait(_ seconds:Double)async {await AcceptanceSmoke.wait(seconds)}
    static func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
    static func run(_ store:PresenterStore,args:[String])->Bool {
        guard let i=args.firstIndex(of:"--field-acceptance"),args.count>i+2 else {return false}
        guard !started else {return true};started=true
        output=URL(fileURLWithPath:args[i+1]);let fixture=URL(fileURLWithPath:args[i+2])
        try? FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        NSApp.accessibilitySetValue(NSNumber(value:true),forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        Task {
            do {await wait(1);try await exercise(store,fixture:fixture)} catch {check(false,error.localizedDescription)}
            store.sharing.close();store.checkpoint();save();NSApp.terminate(nil)
        }
        return true
    }
    static func installed(_ view:SharedSlideView,_ page:Int)async->Bool {
        for _ in 0..<200 {if view.lastInstalledPage==page {return true};await wait(0.05)}
        return false
    }
    static func hover(_ window:NSWindow,text:String)async {
        guard let root=window.contentView,let view=views(root).compactMap({$0 as? HelpTrackingView}).first(where:{$0.helpText.contains(text)}) else {check(false,"hover tracking view exists: "+text);return}
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);window.acceptsMouseMovedEvents=true
        view.updateTrackingAreas()
        let point=view.convert(NSPoint(x:view.bounds.midX,y:view.bounds.midY),to:nil)
        let event=NSEvent.enterExitEvent(with:.mouseEntered,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,trackingNumber:0,userData:nil)!
        view.mouseEntered(with:event)
        await wait(0.3)
        check(view.bounds.width>0 && !view.trackingAreas.isEmpty,"real tracking area registered for "+text)
        check(view.hub?.text==view.helpText,"pointer-entry event reveals rendered hint: "+text)
        UISmoke.capture(window,output.appendingPathComponent("hover-"+text+".png").path)
        try? (view.hub?.text ?? "").write(to:output.appendingPathComponent("hover-"+text+".txt"),atomically:true,encoding:.utf8)
    }
    static func exercise(_ store:PresenterStore,fixture:URL)async throws {
        guard let trainer=NSApp.windows.first(where:{$0.title==SharingSession.trainerTitle}) else {throw PresenterError.message("No trainer")}
        trainer.setContentSize(NSSize(width:1280,height:900));trainer.makeKeyAndOrderFront(nil)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        var saved:[String:Data]=[:]
        for bag in store.library.bags {if let p=try? DocumentReader.load(TrainingLibrary.projectURL(bag.id)) {saved[bag.id]=try encoder.encode(p.activities)}}
        store.freeMode=true;store.toggle();let initialAnchor=store.timer.anchor
        check(UISmoke.press("openReview",window:trainer),"open actual review sheet");await wait(0.5)
        guard let review=trainer.attachedSheet else {throw PresenterError.message("No review")}
        check(UISmoke.press("openTimeConflicts",window:review),"actual cross-library conflict entry");await wait(0.5)
        let cases=store.timeConflicts
        var json:[[String:Any]]=[]
        for item in cases {
            let sources=item.activity.evidence.map {e->[String:Any] in
                ["id":e.id,"fileID":e.fileID,"file":e.filename,"page":e.page,"minutes":e.seconds/60,"role":TimeSourcePolicy.role(e,materials:item.materials) ?? "auxiliary","scope":TimeSourcePolicy.kind(e,activity:item.activity),"location":e.location ?? e.excerpt]
            }
            json.append(["id":item.id,"track":item.bag.track,"domain":item.bag.domain,"bag":item.bag.title,"bagID":item.bag.id,"activity":item.activity.displayTitle,"activityID":item.activity.id,"day":item.activity.day,"session":item.activity.session,"kind":item.activity.kind,"approved":item.activity.approved,"duration_minutes":item.activity.duration/60,"status":item.assessment.status,"sources":sources])
        }
        try JSONSerialization.data(withJSONObject:json,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("conflicts.json"))
        check(!cases.isEmpty && store.timeConflictReadError==nil,"saved projects read without reindex or extraction; conflict count "+String(cases.count))
        check(store.timer.running && store.timer.anchor==initialAnchor,"listing cases does not touch running timer")
        if let first=cases.first,let source=first.assessment.primary.first {
            check(UISmoke.press("conflictSource:"+first.id+":"+source.id,window:review),"actual conflict source button")
            await wait(1)
            if let preview=review.attachedSheet ?? (trainer.attachedSheet !== review ? trainer.attachedSheet:nil) {
                check(preview !== review,"source opens private preview")
                UISmoke.capture(preview,output.appendingPathComponent("conflict-source.png").path)
                _=UISmoke.press("closeConflictSource",window:preview)
            } else {check(false,"private source preview window")}
            await wait(0.4)
            check(store.timer.running && store.timer.anchor==initialAnchor && store.project.libraryBagID==nil,"source preview preserves current project and clock")
            store.toggle();store.dirty=false // Discard only this empty, isolated timer fixture before changing bags.
            check(UISmoke.press("openTimeConflict:"+first.id,window:review),"actual case button opens editor directly")
            await wait(0.5)
            check(store.selectedReview==first.activity.id && store.project.libraryBagID==first.bag.id && !store.timeConflictsVisible,"first case selects exact bag and activity")
        }
        for item in cases {
            store.openTimeConflict(item);await wait(0.1)
            check(store.selectedReview==item.activity.id && store.project.libraryBagID==item.bag.id,"direct editor location: "+item.id)
            if let before=saved[item.bag.id] {check(try before==encoder.encode(store.project.activities),"opening case preserves values approval evidence: "+item.id)}
        }
        if let id=store.selectedReview,let index=store.project.activities.firstIndex(where:{$0.id==id}) {
            let original=store.project.activities[index]
            store.project.activities[index].approved=true
            let editor=ActivityEditor(store:store,activityID:id)
            editor.binding(\.title).wrappedValue=original.title
            check(store.project.activities[index].approved,"no-op editor binding preserves approval")
            editor.binding(\.title).wrappedValue=original.title+" اختبار معزول"
            check(!store.project.activities[index].approved && store.project.activities[index].title==original.title+" اختبار معزول","explicit editor change updates correct activity and requires approval")
            store.project.activities[index]=original
            let before=try encoder.encode(store.project.activities)
            ActivityEditor(store:store,activityID:"absent-isolated-test").binding(\.title).wrappedValue="ignored"
            check(try before==encoder.encode(store.project.activities),"retired editor identity never edits another activity")
        }
        UISmoke.capture(review,output.appendingPathComponent("conflict-editor.png").path)
        store.review=false;await wait(0.5)
        store.project=try DocumentReader.load(fixture);store.projectEpoch=UUID();store.privatePreview=false;store.loadDisplay()
        store.project.preferences.sound=false;store.setFollowing(false)
        let activity=store.project.activities.first(where:{$0.approved})!;store.selectActivity(activity.id);store.toggle()
        store.sharing.setMode(.single);await wait(0.4)
        check(UISmoke.press("toggleSharedPresentation",window:trainer),"actual sharing open");await wait(0.5)
        guard let audience=store.sharing.window,let root=audience.contentView,let canvas=views(root).compactMap({$0 as? SharedSlideView}).first else {throw PresenterError.message("Audience absent")}
        check(await installed(canvas,store.project.currentPage),"initial audience pixels installed")
        let trainerFrame=trainer.frame,audienceFrame=audience.frame,anchor=store.timer.anchor
        check(UISmoke.press("zoomAudience",window:trainer),"obvious audience size button");await wait(0.2)
        check(audience.frame.width>=audienceFrame.width && trainer.frame==trainerFrame && !audience.styleMask.contains(.fullScreen),"audience expands independently without Trainer resize or native Space")
        audience.standardWindowButton(.zoomButton)?.performClick(nil);await wait(0.2)
        check(audience.frame==audienceFrame && trainer.frame==trainerFrame,"native green zoom restores only audience geometry")
        let frame=audience.frame;trainer.setContentSize(NSSize(width:1100,height:780));await wait(0.3)
        check(audience.frame==frame,"Trainer resizing never resizes audience")
        let privateFrame=trainer.frame;audience.setContentSize(NSSize(width:1250,height:760));await wait(0.3)
        check(trainer.frame==privateFrame,"audience resize never changes Trainer")
        #if !TESTING
        if let panel=store.sharing.controls.window {
            check(panel.isVisible && panel !== audience && panel.sharingType == .none,"separate private floating control panel")
            check(UISmoke.press("panelNext",window:panel),"actual private next-slide control")
            check(await installed(canvas,store.project.currentPage),"panel next updates audience")
            check(UISmoke.press("headerToggleTimer",window:panel),"actual private pause control")
            check(!store.timer.running,"private pause changes current clock")
            _=UISmoke.press("headerToggleTimer",window:panel);await wait(0.2)
            check(store.timer.running,"private panel resumes clock")
            UISmoke.capture(panel,output.appendingPathComponent("private-controls.png").path)
        } else {check(false,"private controls visible on single mode")}
        #endif
        let resumed=store.timer.anchor
        await hover(trainer,text:"الصفحة التالية")
        await hover(trainer,text:"تكبير نافذة الجمهور")
        let nodes=UISmoke.nodes(audience)
        check(!nodes.contains{UISmoke.value($0,"accessibilityIdentifier") as? String=="visibleTrainerTooltip"} && views(root).allSatisfy{!($0 is HelpTrackingView)},"no tooltip or tracking control in audience")
        check(!audience.isMainWindow && audience.attachedSheet==nil,"private trainer scene and sheets remain separate")
        var samples:[[String:Any]]=[]
        let maxPage=max(0,(store.document?.pageCount ?? 1)-1)
        for target in [min(30,maxPage),min(31,maxPage),min(32,maxPage),min(31,maxPage)] {
            if target==31 {await wait(2.2)}
            let start=ProcessInfo.processInfo.systemUptime
            store.navigate(target,follow:false)
            let ok=await installed(canvas,target)
            let latency=(ProcessInfo.processInfo.systemUptime-start)*1000
            samples.append(["mode":"single","page":target+1,"navigation_to_layer_ms":latency,"sample":canvas.renderSamples.last ?? [:]])
            check(ok,"single-mode requested raster completes page "+String(target+1))
        }
        store.sharing.setMode(.dual);await wait(0.5)
        if NSScreen.screens.count>1 {
            check(audience.screen === NSScreen.screens[1],"audience placed on second detected display")
            await wait(2.2)
            for target in [min(33,maxPage),min(34,maxPage),min(33,maxPage)] {
                let start=ProcessInfo.processInfo.systemUptime;store.navigate(target,follow:false)
                let ok=await installed(canvas,target)
                samples.append(["mode":"dual","page":target+1,"navigation_to_layer_ms":(ProcessInfo.processInfo.systemUptime-start)*1000,"sample":canvas.renderSamples.last ?? [:]])
                check(ok,"second-display requested raster completes page "+String(target+1));await wait(2.2)
            }
        } else {note("second physical display unavailable")}
        for target in [min(2,maxPage),min(12,maxPage),min(40,maxPage)] {store.navigate(target,follow:false)}
        let rapidTarget=min(40,maxPage)
        check(await installed(canvas,rapidTarget),"rapid navigation installs final requested page")
        await wait(0.2)
        check(store.sharing.presentation.preparedPage==rapidTarget,"stale worker results never overwrite final public page")
        if let privateCanvas=trainer.contentView.flatMap({views($0).compactMap{$0 as? PreparedFrameCanvas.Canvas}.first}) {
            check(privateCanvas.image === canvas.retainedImage,"Trainer and audience reuse identical prepared pixels without duplicate PDF rendering")
        } else {check(false,"prepared trainer preview used during public sharing")}
        if let image=canvas.retainedImage {
            let pixels=NSBitmapImageRep(cgImage:image);var bright=0
            for x in stride(from:0,to:pixels.pixelsWide,by:max(1,pixels.pixelsWide/25)) {
                for y in stride(from:0,to:pixels.pixelsHigh,by:max(1,pixels.pixelsHigh/20)) {
                    if let color=pixels.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),max(color.redComponent,max(color.greenComponent,color.blueComponent))>0.15 {bright+=1}
                }
            }
            check(bright>25,"actual audience bitmap contains visible PDF pixels")
        }
        let count=canvas.installCount,layerCount=canvas.refreshCount
        trainer.makeKeyAndOrderFront(nil);audience.makeKeyAndOrderFront(nil);trainer.makeKeyAndOrderFront(nil)
        if let area=NSScreen.screens.first?.visibleFrame {audience.setFrameOrigin(NSPoint(x:area.minX+20,y:area.minY+20))}
        await wait(1)
        check(canvas.installCount==count,"focus and screen relocation do not rerasterize unchanged page")
        check(canvas.refreshCount-layerCount<4,"idle/focus layout avoids repeated layer refresh")
        check(store.timer.running && store.timer.anchor==resumed,"navigation focus and screen move preserve running timer anchor")
        check(canvas.retainedImage != nil,"durable non-empty pixels retained after moves")
        UISmoke.capture(audience,output.appendingPathComponent("audience.png").path)
        try JSONSerialization.data(withJSONObject:["physicalScreens":NSScreen.screens.count,"navigationSamples":samples,"rasterSamples":canvas.renderSamples,"installCount":canvas.installCount,"refreshCount":canvas.refreshCount,"drawCount":canvas.drawCount,"teams":"NOT TESTED"],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("latency.json"))
        if NSScreen.screens.count != 1 {note("one physical display only; manual single mode exercised on available displays")}
        note("Teams participant transport latency and new-build participant capture not measured")
        _=anchor
    }
}
