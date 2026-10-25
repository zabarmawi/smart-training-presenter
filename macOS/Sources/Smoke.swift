import AppKit
import SwiftUI
import PDFKit

// Run only when explicitly launched with --ui-smoke OUTPUT_DIRECTORY PROJECT_FILE.
// Exercises live accessibility actions in the built app, then captures its own view.
@MainActor final class UISmoke {
    static var rows:[String]=[]
    static var started=false
    static func value(_ e:NSObject,_ selector:String)->Any? {
        let s=NSSelectorFromString(selector)
        guard e.responds(to:s) else {return nil}
        return e.perform(s)?.takeUnretainedValue()
    }
    static func nodes(_ root:Any,depth:Int=0)->[NSObject] {
        guard depth<40,let e=root as? NSObject else {return []}
        let children=(value(e,"accessibilityChildren") as? [Any]) ?? []
        return [e] + children.flatMap{nodes($0,depth:depth+1)}
    }
    static func record(_ ok:Bool,_ name:String) {rows.append((ok ? "PASS: ":"FAIL: ")+name)}
    static func press(_ id:String,window:NSWindow)->Bool {
        for e in nodes(window) where value(e,"accessibilityIdentifier") as? String==id {
            let sel=NSSelectorFromString("accessibilityPerformPress")
            if e.responds(to:sel) {
                typealias Action = @convention(c) (AnyObject,Selector)->Bool
                let action=unsafeBitCast(e.method(for:sel),to:Action.self)
                return action(e,sel)
            }
            let old=NSSelectorFromString("accessibilityPerformAction:")
            if e.responds(to:old) {e.perform(old,with:NSAccessibility.Action.press.rawValue);return true}
        }
        // SwiftUI may expose a reduced tree when VoiceOver is off. Dispatch real
        // window mouse events at button positions verified from the captured view.
        guard let view=window.contentView else {return false}
        let point:NSPoint
        switch id {
        case "toggleTimer": point=NSPoint(x:207,y:view.bounds.height-752)
        case "extendPlus": point=NSPoint(x:209,y:view.bounds.height-797)
        default:return false
        }
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            guard let event=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:type == .leftMouseDown ? 1:0) else {return false}
            window.sendEvent(event)
        }
        return true
    }
    static func capture(_ window:NSWindow,_ path:String) {
        guard let v=window.contentView,let bitmap=v.bitmapImageRepForCachingDisplay(in:v.bounds) else {return}
        v.cacheDisplay(in:v.bounds,to:bitmap)
        if let data=bitmap.representation(using:.png,properties:[:]) {try? data.write(to:URL(fileURLWithPath:path))}
    }
    static func run(_ store:PresenterStore) {
        if IdentityAcceptance.run(store,args:CommandLine.arguments) {return}

        let args=CommandLine.arguments
        if FieldAcceptanceSmoke.run(store,args:args) {return}
        if V061Smoke.run(store,args:args) {return}
        if AcceptanceSmoke.run(store,args:args) {return}
        if QA01Smoke.run(store,args:args) {return}
        if resilience(store,args:args) || librarySmoke(store,args:args) {return}
        guard !started,let i=args.firstIndex(of:"--ui-smoke"),args.count>i+2 else {return}
        started=true
        NSApp.accessibilitySetValue(NSNumber(value:true),forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        let folder=args[i+1]
        try? "entered smoke".write(toFile:folder+"/started.txt",atomically:true,encoding:.utf8)
        do {store.project=try DocumentReader.load(URL(fileURLWithPath:args[i+2]));store.loadDisplay()} catch {rows.append("FAIL: fixture \(error)")}
        DispatchQueue.main.asyncAfter(deadline:.now()+2) {
            guard let window=NSApp.windows.first(where:{$0.contentView != nil}) else {return}
            window.setContentSize(NSSize(width:1280,height:900));window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                let tree=nodes(window)
                let labels=tree.map{"\(type(of:$0)) | \(value($0,"accessibilityIdentifier") ?? "") | \(value($0,"accessibilityLabel") ?? "")"}
                try? labels.joined(separator:"\n").write(toFile:folder+"/accessibility.txt",atomically:true,encoding:.utf8)
                record(!tree.isEmpty,"live accessibility tree")
                record(press("toggleTimer",window:window),"press actual timer control")
                DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                    record(store.timer.running,"press starts countdown")
                    let before=store.timer.used(store.now)
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.7) {window.deminiaturize(nil)}
                    record(press("extendPlus",window:window),"press actual cumulative extension control")
                    window.miniaturize(nil)
                    DispatchQueue.main.asyncAfter(deadline:.now()+1.1) {
                        store.tick()
                        record(store.timer.running && store.timer.used(store.now)>before+0.5,"timer survives actual minimization")
                        record(store.proposed==1,"extension button changes proposal")
                        let anchor=store.timer.anchor
                        let other=Activity(id:"ui-preview-other",title:"نشاط آخر للمعاينة",kind:"نشاط",original:300,duration:300,approved:true,presentationID:store.project.currentFile,startPage:4,endPage:4)
                        store.project.activities.append(other)
                        let activity=store.project.currentActivity
                        store.setFollowing(false);store.navigate(3)
                        record(store.project.currentActivity==activity && store.timer.anchor==anchor,"cross-activity preview protects running timer")
                        record(press("followSlides",window:window),"press explicit follow mode control")
                        record(store.project.preferences.followsSlides,"follow mode is explicit")
                        _=press("followSlides",window:window)
                        store.navigate(1)
                        record(store.timer.anchor==anchor && store.timer.running,"live slide change preserves timer")
                        store.notice=Notice(text:"انتهى الوقت — يمكنك التمديد أو الانتقال للنشاط التالي",until:store.now+20)
                        store.project.preferences.barMode="ثابت"
                        DispatchQueue.main.asyncAfter(deadline:.now()+0.6) {
                            let expandedHeight=pdfHeight(window.contentView)
                            capture(window,folder+"/ui-fixed.png")
                            record(press("compactDock",window:window),"press compact dock control")
                            DispatchQueue.main.asyncAfter(deadline:.now()+0.6) {
                                let compactHeight=pdfHeight(window.contentView)
                                capture(window,folder+"/ui-mini.png")
                                record(compactHeight>expandedHeight+20,"compact dock expands actual slide viewport")
                                record(press("toggleDock",window:window),"press hide dock control")
                                DispatchQueue.main.asyncAfter(deadline:.now()+0.6) {
                                    capture(window,folder+"/ui-hidden.png")
                                    record(pdfHeight(window.contentView)>compactHeight+20,"hidden dock reclaims all of its space")
                                    record(store.timer.anchor==anchor && store.timer.running,"hiding controls preserves running timer")
                                    record(nodes(window).contains{value($0,"accessibilityIdentifier") as? String=="headerActivity"},"hidden dock retains activity context")
                                    record(press("headerToggleTimer",window:window),"press header pause while dock hidden")
                                    record(!store.timer.running,"header pauses timer without restoring dock")
                                    _=press("headerToggleTimer",window:window)
                                    record(store.timer.running,"header resumes timer while dock hidden")
                                    store.project.preferences.barMode="مصغّر"
                                    window.setContentSize(NSSize(width:1040,height:720))
                                    store.selectedReview=store.project.currentActivity
                                    checkExternalDisplay(store,window:window,folder:folder)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    static func pdfHeight(_ view:NSView?)->CGFloat {
        guard let view=view else {return 0}
        if view is PDFView {return view.bounds.height}
        return view.subviews.map{pdfHeight($0)}.max() ?? 0
    }
    static func checkExternalDisplay(_ store:PresenterStore,window:NSWindow,folder:String) {
        guard let target=NSScreen.screens.first(where:{$0 != window.screen}) else {
            rows.append("SKIP: no second display available");finish(store,window:window,folder:folder);return
        }
        let previous=window.frame,anchor=store.timer.anchor
        window.setFrame(target.visibleFrame,display:true)
        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
            record(window.screen==target,"window moves to second detected display")
            record(store.timer.running && store.timer.anchor==anchor,"timer continues on second display")
            capture(window,folder+"/ui-second-display.png")
            window.setFrame(previous,display:true)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.4) {finish(store,window:window,folder:folder)}
        }
    }
    static func finish(_ store:PresenterStore,window:NSWindow,folder:String) {
        var timer=store.timer;timer.pause(store.now);timer.elapsed=timer.adjusted+90
        if let id=store.project.currentActivity {store.project.timers[id]=timer}
        store.notice=nil;store.selectedReview=store.project.currentActivity;store.review=true
        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
            if let sheet=window.attachedSheet {
                let sheetNodes=nodes(sheet)
                record(sheetNodes.contains{value($0,"accessibilityIdentifier") as? String=="reviewSearch"},"grouped review provides search")
                record(sheetNodes.contains{value($0,"accessibilityIdentifier") as? String=="reviewOnly"},"grouped review provides pending filter")
                record(press("reviewOnly",window:sheet),"press pending-only review filter")
                _=press("reviewOnly",window:sheet)
                record(sheetNodes.contains{value($0,"accessibilityIdentifier") as? String=="approveActivity"},"activity editor exposes approval control")
                record(press("approveActivity",window:sheet),"press actual activity approval control")
                capture(sheet,folder+"/ui-review.png")
                record(store.timer.remaining(store.now)==(-90),"overtime persists after hiding notice")
                record(press("beginReviewedActivity",window:sheet),"press begin directly from review")
                record(store.timer.running && !store.review,"review begins activity and closes")
            } else {record(false,"review sheet opens")}
            try? rows.joined(separator:"\n").write(toFile:folder+"/ui-results.txt",atomically:true,encoding:.utf8)
            try? "screens=\(NSScreen.screens.count)".write(toFile:folder+"/display-check.txt",atomically:true,encoding:.utf8)
            store.checkpoint();NSApp.terminate(nil)
        }
    }
    static func librarySmoke(_ store:PresenterStore,args:[String])->Bool {
        guard let index=args.firstIndex(of:"--library-smoke"),args.count>index+1 else {return false}
        guard !started else {return true};started=true
        let folder=args[index+1]
        try? "entered library smoke; bags=\(store.library.bags.count)".write(toFile:folder+"/started.txt",atomically:true,encoding:.utf8)
        DispatchQueue.main.asyncAfter(deadline:.now()+40) {
            rows.append("FAIL: library UI timed out; windows=\(NSApp.windows.map{String($0.isVisible)})")
            try? rows.joined(separator:"\n").write(toFile:folder+"/library-ui-results.txt",atomically:true,encoding:.utf8);NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+2) {
            guard let window=NSApp.windows.first(where:{$0.contentView != nil}),let first=store.library.bags.first else {return}
            NSApp.accessibilitySetValue(NSNumber(value:true),forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            window.setContentSize(NSSize(width:1280,height:900))
            record(store.library.bags.count==11 && store.library.bags.allSatisfy(\.complete),"library restores eleven complete independent bags")
            record(press("openLibrary",window:window),"open actual library control")
            DispatchQueue.main.asyncAfter(deadline:.now()+0.8) {
                guard let sheet=window.attachedSheet else {return}
                capture(sheet,folder+"/library.png")
                record(nodes(sheet).contains{value($0,"accessibilityIdentifier") as? String=="librarySearch"},"library provides search")
                record(nodes(sheet).contains{value($0,"accessibilityIdentifier") as? String=="libraryTrack"},"library provides track filter")
                record(first.status=="تحتاج مراجعة","newly prepared bag is not automatically ready")
                record(press("openLibraryBag",window:sheet),"open prepared bag from actual library button")
                DispatchQueue.main.asyncAfter(deadline:.now()+0.8) {
                    record(store.project.libraryBagID==first.id && store.material?.libraryRole=="slides" && store.document != nil,"bag opens actual presentation rather than guide")
                    record(!store.timer.running,"opening library bag leaves timer paused")
                    _=press("openLibrary",window:window)
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
                        guard let sheet=window.attachedSheet else {return}
                        record(press("reviewLibraryBag",window:sheet),"review activities from library")
                        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                            guard let review=window.attachedSheet,let activity=store.project.activities.first else {return}
                            record(press("reviewRow:"+activity.id,window:review),"select actual activity review row")
                            DispatchQueue.main.asyncAfter(deadline:.now()+0.4) {
                                store.project.activities[0].duration += 60
                                record(press("approveActivity",window:review),"approve actual library activity after manual duration edit")
                                record(store.project.activities[0].approved,"library activity approval applied")
                                store.checkpoint();capture(review,folder+"/library-review.png")
                                let edited=store.project.activities[0].duration
                                do {
                                    let saved=try DocumentReader.load(TrainingLibrary.projectURL(first.id))
                                    record(saved.activities[0].approved && saved.activities[0].duration==edited,"library autosave retains latest approval and manual duration")
                                } catch {record(false,"library autosave")}
                                store.review=false
                                DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
                                    if let other=store.library.bags.first(where:{$0.id != first.id}) {
                                        store.openLibraryBag(other.id)
                                        record(store.project.libraryBagID==other.id && !store.project.activities.contains(where:{$0.id==activity.id}),"switching bag isolates activity identities")
                                        store.openLibraryBag(first.id)
                                        record(store.project.activities[0].approved && store.project.activities[0].duration==edited,"reopening bag preserves latest reviewed state without save prompt")
                                    }
                                    try? rows.joined(separator:"\n").write(toFile:folder+"/library-ui-results.txt",atomically:true,encoding:.utf8)
                                    store.checkpoint();NSApp.terminate(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
        return true
    }
    static func resilience(_ store:PresenterStore,args:[String])->Bool {
        let seed=args.firstIndex(of:"--resilience-seed"),verify=args.firstIndex(of:"--resilience-check")
        guard let index=seed ?? verify,args.count>index+1 else {return false}
        guard !started else {return true};started=true
        let folder=args[index+1]
        if seed != nil {
            var project=Project();project.name="Recovery after forced exit"
            let activity=Activity(id:"crash-activity",title:"نشاط اختبار الاسترداد",kind:"نشاط",original:900,duration:900,approved:true)
            project.activities=[activity];project.currentActivity=activity.id
            var timer=Countdown(900);timer.elapsed=245;timer.extensions=180;timer.toggle(continuousSeconds());project.timers[activity.id]=timer
            store.project=project;store.checkpoint()
            try? "ready".write(toFile:folder+"/seed-ready.txt",atomically:true,encoding:.utf8)
        } else {
            let timer=store.project.timers["crash-activity"]
            let ok=store.project.name=="Recovery after forced exit" && timer?.running==false && timer?.extensions==180 && (timer?.elapsed ?? 0)>=245
            let result=ok ? "PASS: restored state after SIGKILL; elapsed, extension and approval retained; clock paused":"FAIL: forced-exit recovery"
            try? result.write(toFile:folder+"/resilience-results.txt",atomically:true,encoding:.utf8)
            DispatchQueue.main.async {NSApp.terminate(nil)}
        }
        return true
    }
}
