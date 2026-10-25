import Foundation
import AppKit
import PDFKit

@MainActor enum AcceptanceSmoke {
    static var started=false
    static var output=URL(fileURLWithPath:"/tmp")
    static var rows:[String]=[]
    static var events:[[String:Any]]=[]
    static var observers:[NSObjectProtocol]=[]
    static var entered:Set<Int>=[]
    static var exited:Set<Int>=[]
    static func record(_ value:Bool,_ label:String) {
        rows.append((value ? "PASS: ":"FAIL: ")+label)
        try? rows.joined(separator:"\n").write(to:output.appendingPathComponent("results.txt"),atomically:true,encoding:.utf8)
    }
    static func note(_ label:String) {rows.append(label);try? rows.joined(separator:"\n").write(to:output.appendingPathComponent("results.txt"),atomically:true,encoding:.utf8)}
    static func wait(_ seconds:Double)async {try? await Task.sleep(nanoseconds:UInt64(seconds*1e9))}
    static func snapshot(_ label:String,_ window:NSWindow) {
        let frame=window.frame,screen=window.screen?.frame ?? .zero
        events.append(["event":label,"window":window.windowNumber,"style":window.styleMask.rawValue,"behavior":window.collectionBehavior.rawValue,"visible":window.isVisible,"key":window.isKeyWindow,"main":window.isMainWindow,"canBecomeKey":window.canBecomeKey,"canBecomeMain":window.canBecomeMain,"frame":[frame.minX,frame.minY,frame.width,frame.height],"screen":[screen.minX,screen.minY,screen.width,screen.height],"appActive":NSApp.isActive,"activationPolicy":NSApp.activationPolicy().rawValue,"frontmostPID":NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,"ownPID":ProcessInfo.processInfo.processIdentifier])
        if let data=try? JSONSerialization.data(withJSONObject:events,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("window-events.json"))}
    }
    static func observe(_ window:NSWindow) {
        for name in [NSWindow.willEnterFullScreenNotification,NSWindow.didEnterFullScreenNotification,NSWindow.willExitFullScreenNotification,NSWindow.didExitFullScreenNotification,NSWindow.didBecomeKeyNotification,NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main){_ in
                MainActor.assumeIsolated {
                    if name==NSWindow.didEnterFullScreenNotification {entered.insert(window.windowNumber)}
                    if name==NSWindow.didExitFullScreenNotification {exited.insert(window.windowNumber)}
                    snapshot(name.rawValue,window)
                }
            })
        }
    }
    static func fullscreen(_ window:NSWindow,label:String,store:PresenterStore)async {
        if !NSApp.isActive,NSWorkspace.shared.frontmostApplication?.bundleIdentifier=="com.apple.loginwindow" {
            snapshot(label+" session locked",window);note("NOT TESTED: "+label+" native fullscreen requires an unlocked interactive Mac session");return
        }
        observe(window);window.makeKeyAndOrderFront(nil);if window.canBecomeMain {window.makeMain()};NSApp.activate(ignoringOtherApps:true);await wait(1)
        let anchor=store.timer.anchor,used=store.timer.used(continuousSeconds())
        let priorBar=store.project.preferences.barMode
        if label=="trainer",let audience=store.sharing.window {audience.makeKeyAndOrderFront(nil);if audience.canBecomeMain {audience.makeMain()};await wait(0.3)}
        snapshot(label+" before enter",window)
        if label=="trainer" {record(UISmoke.press("presentationFocus",window:window),"trainer fullscreen toolbar pressed")} else {store.sharing.windowState.toggle()}
        for _ in 0..<120 {if entered.contains(window.windowNumber) {break};await wait(0.1)}
        snapshot(label+" after enter",window)
        let success=entered.contains(window.windowNumber) && window.styleMask.contains(.fullScreen)
        record(success,label+" enters native full screen with didEnter notification")
        record(store.timer.running && store.timer.anchor==anchor && store.timer.used(continuousSeconds())>used,label+" timer continues during fullscreen request")
        if success {
            let oldPage=store.project.currentPage
            store.navigate(min(oldPage+1,(store.document?.pageCount ?? 1)-1));await wait(0.4)
            record(store.project.currentPage != oldPage || (store.document?.pageCount ?? 0)<=1,label+" slide navigation works in native fullscreen")
            store.navigate(oldPage)
            if label=="trainer" {record(UISmoke.press("presentationFocus",window:window),"trainer fullscreen exit toolbar pressed")} else {store.sharing.windowState.toggle()}
            for _ in 0..<120 {if exited.contains(window.windowNumber) {break};await wait(0.1)}
            record(exited.contains(window.windowNumber) && !window.styleMask.contains(.fullScreen),label+" exits native full screen with didExit notification")
        }
        if label=="trainer" {await wait(0.3);record(store.project.preferences.barMode==priorBar,"fullscreen exit restores trainer dock preference")}
        snapshot(label+" finished",window)
    }
    static func run(_ store:PresenterStore,args:[String])->Bool {
        let mode=args.contains("--powerpoint-acceptance") ? "--powerpoint-acceptance":"--privacy-acceptance"
        guard let index=args.firstIndex(of:mode),args.count>index+2 else {return false}
        guard !started else {return true};started=true
        output=URL(fileURLWithPath:args[index+1]);try? FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        Task {
            await wait(2)
            do {
                if mode=="--powerpoint-acceptance" {
                    PowerPointSmoke.folder=output.path;try await PowerPointSmoke.conversion(store,fixture:URL(fileURLWithPath:args[index+2]));try await sentinelConversion(store,fixture:URL(fileURLWithPath:args[index+2]))
                } else {try await privacy(store,fixture:URL(fileURLWithPath:args[index+2]))}
            } catch {record(false,"unexpected error: "+error.localizedDescription)}
            for observer in observers {NotificationCenter.default.removeObserver(observer)}
            observers=[];if let error=store.error {note("DETAIL: "+error)};store.error=nil;store.review=false;store.settings=false;store.libraryVisible=false;store.sharing.close();store.checkpoint();await wait(0.4);NSApp.terminate(nil)
        }
        return true
    }
    static func canvas(_ root:NSView?)->SharedSlideView? {
        guard let root=root else {return nil};if let result=root as? SharedSlideView {return result}
        for view in root.subviews {if let result=canvas(view) {return result}};return nil
    }
    static func checkAudience(_ store:PresenterStore,_ label:String,document:PDFDocument?=nil,page:Int?=nil) {
        guard let window=store.sharing.window,let content=window.contentView else {record(false,label+" audience missing");return}
        let publicView=store.sharing.presentation
        let tree=UISmoke.nodes(content)
        let identifiers=tree.compactMap{UISmoke.value($0,"accessibilityIdentifier") as? String}.filter{!$0.isEmpty}
        let roles=tree.compactMap{UISmoke.value($0,"accessibilityRole") as? String}
        let text=tree.flatMap{element in ["accessibilityLabel","accessibilityValue","accessibilityTitle"].compactMap{UISmoke.value(element,$0) as? String}}.joined(separator:" ")
        record(window.isVisible && window.title==SharingSession.audienceTitle && String(describing:type(of:content)).contains("SharedPresentationView"),label+" dedicated audience view")
        let privateFree = !identifiers.contains(where:{$0 != "participantTimer"}) && !roles.contains(where:{["AXButton","AXTextField","AXTable","AXPopUpButton","AXCheckBox"].contains($0)}) && !text.contains("PRIVATE_CANARY")
        if !privateFree,let data=try? JSONSerialization.data(withJSONObject:["identifiers":identifiers,"roles":roles,"text":text],options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("privacy-diagnostic-"+label+".json"))}
        record(privateFree,label+" no private controls or data")
        if let document=document {record(publicView.document===document && publicView.page==page,label+" public slide unchanged")}
        if let pdf=publicView.document {record(canvas(content)?.page === pdf.page(at:publicView.page),label+" actual native canvas matches public slide")}
        record(window.attachedSheet==nil && !window.isMainWindow,label+" trainer sheets cannot attach to audience")
    }
    static func privacy(_ store:PresenterStore,fixture:URL)async throws {
        guard let main=NSApp.windows.first(where:{$0.isVisible && $0.title==SharingSession.trainerTitle}) else {throw PresenterError.message("trainer unavailable")}
        NSApp.accessibilitySetValue(NSNumber(value:true),forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        main.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        store.project=try DocumentReader.load(fixture);store.projectEpoch=UUID();store.project.preferences.sound=false;store.project.preferences.barMode="مصغّر";store.privatePreview=false
        store.project.name="PRIVATE_CANARY_PROJECT";store.loadDisplay()
        guard let slide=store.material,let activity=store.project.activities.first(where:{$0.approved}) else {throw PresenterError.message("fixture missing")}
        store.selectActivity(activity.id);store.setFollowing(false);store.sharing.preferences=SharePreferences()
        record(store.library.bags.count==11,"eleven-bag library available without reindex")
        record(UISmoke.press("toggleSharedPresentation",window:main),"open audience using simplified actual button");await wait(0.7)
        guard let audience=store.sharing.window else {throw PresenterError.message("audience unavailable")}
        checkAudience(store,"open")
        record(store.sharing.presentation.timer==nil,"participant timer defaults to explicit opt-in")
        store.navigate(2);await wait(0.4);record(store.sharing.presentation.page==2,"slide navigation reaches audience");checkAudience(store,"navigate")
        if !store.timer.running {store.toggle()};let anchor=store.timer.anchor
        store.sharing.preferences.showTimer=true;store.sharing.save();await wait(0.4)
        record(store.sharing.presentation.timer != nil,"chosen activity timer is visible");checkAudience(store,"running")
        store.toggle();await wait(0.4);record(!store.timer.running,"pause activity timer");checkAudience(store,"paused")
        store.toggle();let resumed=store.timer.anchor;await wait(0.3)
        let publicPDF=store.sharing.presentation.document!,publicPage=store.sharing.presentation.page
        store.libraryVisible=true;await wait(0.5);checkAudience(store,"library",document:publicPDF,page:publicPage);store.libraryVisible=false;await wait(0.4)
        if let bag=store.library.bags.first {
            for role in ["trainer","learner"] {
                guard let source=bag.files.first(where:{$0.role==role}) else {throw PresenterError.message("guide missing")}
                let url=store.library.url(source),pdf=PDFDocument(url:url)!
                let m=Material(id:"private-"+role,path:url.path,hash:source.hash,renderedPath:url.path,pages:pdf.pageCount,libraryRole:role)
                store.project.materials.append(m);store.previewSource(Evidence(fileID:m.id,filename:m.name,page:2,excerpt:"PRIVATE_CANARY",seconds:600));await wait(0.4)
                checkAudience(store,role+" guide",document:publicPDF,page:publicPage)
            }
        }
        // The old role-only mirror would publish this source page from slides.
        store.previewSource(Evidence(fileID:slide.id,filename:slide.name,page:6,excerpt:"PRIVATE_CANARY",seconds:600));await wait(0.5)
        record(store.privatePreview && store.project.currentPage==5,"same-slide-file source opens privately")
        checkAudience(store,"source from slide file",document:publicPDF,page:publicPage)
        store.navigate(6,follow:false);await wait(0.4);checkAudience(store,"navigate private preview",document:publicPDF,page:publicPage)
        store.review=true;await wait(0.5)
        if let sheet=main.attachedSheet {record(UISmoke.press("reviewRow:"+activity.id,window:sheet),"select activity in actual private editor")}
        else {record(false,"private review sheet visible")}
        if let i=store.project.activities.firstIndex(where:{$0.id==activity.id}) {store.project.activities[i].title="PRIVATE_CANARY_ACTIVITY";store.project.activities[i].duration+=60;store.changed()}
        await wait(0.3);checkAudience(store,"review and edit isolated duration",document:publicPDF,page:publicPage);store.review=false;await wait(0.4)
        store.settings=true;await wait(0.5);checkAudience(store,"settings",document:publicPDF,page:publicPage);store.settings=false;await wait(0.4)
        audience.makeKeyAndOrderFront(nil);await wait(0.3);main.makeKeyAndOrderFront(nil);await wait(0.4)
        record(store.timer.running && store.timer.anchor==resumed,"focus changes never restart activity clock");checkAudience(store,"focus",document:publicPDF,page:publicPage)
        main.miniaturize(nil);await wait(0.5);record(main.isMiniaturized,"trainer actually miniaturized");checkAudience(store,"trainer minimized",document:publicPDF,page:publicPage);main.deminiaturize(nil);await wait(0.4);record(!main.isMiniaturized,"trainer restored")
        audience.setContentSize(NSSize(width:700,height:540));await wait(0.4);checkAudience(store,"resized",document:publicPDF,page:publicPage)
        store.selectFile(slide.id);store.navigate(publicPage);await wait(0.4)
        await fullscreen(main,label:"trainer",store:store);checkAudience(store,"trainer fullscreen transition")
        if store.sharing.effectiveMode == .dual {await fullscreen(audience,label:"audience",store:store)}
        else {store.sharing.maximize();record(!audience.styleMask.contains(.fullScreen),"single mode maximizes without a separate Space")}
        checkAudience(store,"audience fullscreen transition")
        store.sharing.close();await wait(0.4);record(!store.sharing.isOpen && store.sharing.window==nil,"close releases audience state")
        record(UISmoke.press("toggleSharedPresentation",window:main),"reopen using actual button");await wait(0.5);checkAudience(store,"reopened")
        if let window=store.sharing.window {UISmoke.capture(window,output.path+"/shared-presentation.png")}
        try await timerChecks(store,main:main)
        let portable=output.appendingPathComponent("roundtrip.stbag"),ids=store.project.activities.map(\.id),durations=store.project.activities.map(\.duration),approvals=store.project.activities.map(\.approved)
        let snapshot=store.project
        _=try await Task.detached {try PortableProject.save(snapshot,to:portable,now:continuousSeconds())}.value
        let loaded=try DocumentReader.load(portable)
        record(loaded.activities.map(\.id)==ids && loaded.activities.map(\.duration)==durations && loaded.activities.map(\.approved)==approvals,"stbag export/import preserves activity IDs durations approvals")
        record(loaded.materials.allSatisfy{FileManager.default.fileExists(atPath:$0.path)},"portable bag source files resolve")
        let legacy=DocumentReader.cache.deletingLastPathComponent().appendingPathComponent("RemoteWorkspace-v05.json")
        record(FileManager.default.fileExists(atPath:legacy.path),"legacy workspace retained for rollback and ignored")
        record(!UISmoke.nodes(main).contains(where:{UISmoke.value($0,"accessibilityIdentifier") as? String=="openRemoteTools"}),"obsolete toolbox absent from executable")
        _=anchor
    }
    static func timerChecks(_ store:PresenterStore,main:NSWindow)async throws {
        store.freeMode=false;if let id=store.project.currentActivity {store.approve(id)};record(store.current?.approved==true,"isolated edited activity explicitly reapproved before control test");if !store.timer.running {store.toggle()};let anchor=store.timer.anchor
        store.freeMode=true;store.toggle();let freeAnchor=store.timer.anchor;await wait(0.5)
        record(store.project.timers[store.project.currentActivity!]!.running && store.project.timers[store.project.currentActivity!]!.anchor==anchor && freeAnchor != nil,"activity and free timers run independently")
        store.toggle();record(!store.timer.running && store.project.timers[store.project.currentActivity!]!.running,"pausing free timer preserves activity timer")
        store.duration(3);record(store.timer.adjusted==180,"free timer duration edit")
        store.reset();record(!store.timer.running && store.timer.elapsed==0,"free timer reset")
        store.freeMode=false;let extensions=store.timer.extensions
        record(UISmoke.press("extendPlus",window:main),"click plus one first");await wait(0.2)
        record(UISmoke.press("extendPlus",window:main),"click plus one repeatedly");await wait(0.2)
        record(UISmoke.press("extendMinus",window:main),"click minus one correction");await wait(0.2)
        record(UISmoke.press("confirmExtension",window:main),"click confirm extension");await wait(0.3)
        record(store.timer.extensions==extensions+60 && store.proposed==0,"cumulative extension commits exactly one minute")
        let activityID=store.project.currentActivity!,page=store.project.currentPage
        var clock=store.timer;clock.elapsed=clock.adjusted+clock.extensions+5;clock.anchor=continuousSeconds();clock.running=true;store.project.timers[activityID]=clock;await wait(0.3)
        record(store.timer.remaining(continuousSeconds())<0 && store.timer.running && store.project.currentPage==page,"overtime continues without advancing slide")
        record(store.sharing.presentation.timer=="00:00","trainer overtime hidden by default")
        let canvasHeight=canvas(store.sharing.window?.contentView)?.bounds.height
        store.project.preferences.noticeSeconds=1
        for threshold in [300,60,0] {store.announce(name:"PRIVATE_CANARY",threshold:threshold);await wait(0.2);record(store.notice != nil,"basic visual alert \(threshold)")}
        record(canvas(store.sharing.window?.contentView)?.bounds.height==canvasHeight,"private alerts never cover audience slide")
        await wait(1.2);record(store.notice==nil,"visual finish alert expires in executable")
        store.project.preferences.volume=0
        for threshold in [300,60,0] {record(store.playSound(threshold),"sound \(threshold) starts programmatically at zero test volume")}
        store.sharing.preferences.showOvertime=true;await wait(0.3);record(store.sharing.presentation.timer?.hasPrefix("+")==true,"overtime sharing requires explicit choice")
    }
    static func sentinelConversion(_ store:PresenterStore,fixture:URL) async throws {
        if let path=store.material?.renderedPath,let main=NSApp.windows.first(where:{$0.contentView != nil}) {
            main.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);await wait(1)
            let canvas=SharedSlideView(frame:NSRect(x:0,y:0,width:1200,height:675));canvas.sourceDocument=PDFDocument(url:URL(fileURLWithPath:path));canvas.page=canvas.sourceDocument?.page(at:0)
            let preview=NSWindow(contentRect:canvas.bounds,styleMask:[.titled,.closable],backing:.buffered,defer:false);preview.isReleasedWhenClosed=false;preview.contentView=canvas;preview.makeKeyAndOrderFront(nil);await wait(0.5)
            UISmoke.capture(preview,output.path+"/converted-live-canvas.png");record(canvas.page != nil,"converted PDF renders in actual native presentation canvas");preview.close()
        }
        let sentinel=output.appendingPathComponent("unrelated-owned-sentinel.pptx")
        try FileManager.default.copyItem(at:fixture,to:sentinel)
        _=try await Task.detached {try command("/usr/bin/open",["-b",PowerPointConversion.identifier,sentinel.path],timeout:10)}.value
        await wait(2)
        let before=try DocumentReader.digest(fixture)
        let hash=try DocumentReader.digest(fixture),pdf=DocumentReader.cache.appendingPathComponent(hash+"/slides.pdf")
        if FileManager.default.fileExists(atPath:pdf.path) {try FileManager.default.removeItem(at:pdf)}
        let result=try await Task.detached {try DocumentReader.read(fixture)}.value
        record(result.material.renderedPath != nil,"uncached export with another presentation open")
        let check=try await Task.detached {try command("/usr/bin/osascript",["-e","tell application id \"com.microsoft.Powerpoint\" to get full name of presentation \"unrelated-owned-sentinel.pptx\""],timeout:10)}.value
        record(check.status==0 && check.text.contains(sentinel.path),"unrelated presentation remains open after conversion")
        _=try await Task.detached {try command("/usr/bin/osascript",["-e","tell application id \"com.microsoft.Powerpoint\" to close presentation \"unrelated-owned-sentinel.pptx\" saving no"],timeout:10)}.value
        record(try DocumentReader.digest(fixture)==before,"fixture original unchanged after sentinel test")
    }
}
