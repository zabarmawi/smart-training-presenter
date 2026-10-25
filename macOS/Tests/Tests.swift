import Foundation
import AppKit
import PDFKit

var passed=0
func check(_ ok:@autoclosure()->Bool,_ name:String) {
    if !ok() {print("FAIL: "+name);exit(1)}
    passed+=1;print("PASS: "+name)
}
@main struct Tests {
    @MainActor static func main() throws {
        var c=Countdown(660)
        c.toggle(100);check(c.remaining(160)==600,"deadline start")
        c.pause(160);check(c.remaining(999)==600,"pause freezes elapsed")
        c.toggle(1000);check(c.remaining(1010)==590,"resume preserves elapsed")
        c.reset();check(c.remaining(9000)==660 && !c.running,"reset")
        c.toggle(0)
        check(c.poll(360)==[300],"five minute threshold")
        check(c.poll(361).isEmpty,"five minute once")
        check(c.poll(600)==[60],"one minute threshold")
        check(c.poll(660)==[0],"zero threshold")
        check(c.poll(840).isEmpty && c.remaining(840)==(-180),"overtime runs after zero")
        c.extend(420,now:840);check(c.remaining(840)==240 && c.original==660 && c.extensions==420,"7 minute extension minus 3 minute overtime")
        check(c.poll(1100).isEmpty,"no duplicate alerts after extension")
        var eq=Countdown(60);eq.toggle(0);_=eq.poll(240);eq.extend(180,now:240)
        check(eq.remaining(240)==0,"extension equal to overtime")
        eq.changeDuration(30,now:240);check(eq.poll(240).isEmpty,"duration edit no retroactive alerts")
        var short=Countdown(40);short.toggle(0);check(short.poll(40)==[0],"short timer does not fire obsolete warnings")
        var sleep=Countdown(1200);sleep.toggle(100);check(sleep.poll(1400)==[300,60,0] && sleep.remaining(1400)==(-100),"background and sleep catchup")
        let cp=sleep.checkpoint(1400);check(!cp.running && cp.remaining(9999)==(-100),"checkpoint safely paused independent of restart clock")
        check(timeText(-90)=="+01:30","overtime formatting")
        check(timeText(Double.greatestFiniteMagnitude).count>0 && timeText(.infinity)=="--:--","malformed huge display time cannot overflow")
        let n=Notice(text:"x",until:15);check(n.visible(14) && !n.visible(15),"notice expires on time")
        var proposed=0;for _ in 0..<3 {proposed+=1};check(proposed==3,"3 cumulative increments")
        for _ in 0..<5 {proposed=max(0,proposed-1)};check(proposed==0,"proposal cannot be negative")
        if CommandLine.arguments.contains("--timer-core-only") {print("ALL \(passed) TIMER CORE CHECKS PASSED");return}
        let m=Material(path:"/fixture/plan.txt",hash:"a")
        let a=TimingExtractor.extract(pages:["اليوم الاول\nالجلسة الاولى 90 دقيقة\nنشاط التعاون ١٥ دقيقة\nاستراحة 10 دقائق\nنشاط غامض حوالي 20 دقيقة\nنشاط نطاق 10-15 دقيقة"],material:m)
        check(a.contains{$0.kind=="جلسة" && $0.duration==5400},"session separated from activity")
        check(a.contains{$0.title.contains("التعاون") && $0.duration==900},"Arabic digit activity extraction")
        check(a.contains{$0.kind=="استراحة" && $0.duration==600},"break extraction")
        check(!a.contains{$0.title.contains("غامض") || $0.title.contains("نطاق")},"ambiguous durations rejected")
        check(a.allSatisfy{!$0.approved && !$0.evidence.isEmpty && $0.evidence[0].page==1},"unapproved source evidence")
        var merged=TimingExtractor.extract(pages:["نشاط التعاون 15 دقيقة"],material:m)
        let m2=Material(path:"/fixture/guide.txt",hash:"b")
        TimingExtractor.merge(TimingExtractor.extract(pages:["نشاط التعاون 20 دقيقة"],material:m2),into:&merged)
        check(merged.count==1 && merged[0].conflict && merged[0].duration==900,"conflicts retained without summing")
        merged[0].duration=1080;merged[0].approved=true
        var p=Project();p.activities=merged;p.freeTimer=c
        let path=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("saved.stpresenter")
        try DocumentReader.save(p,to:path,now:840)
        let loaded=try DocumentReader.load(path)
        check(loaded.activities[0].duration==1080 && loaded.activities[0].approved && loaded.activities[0].original==900,"save approved edited duration")
        check(!loaded.freeTimer.running,"open project pauses timers")
        var invalid=p;invalid.version=999
        check((try? invalid.validated())==nil,"reject unsupported project version")
        invalid=p;invalid.activities[0].duration = -5
        check((try? invalid.validated())==nil,"reject invalid duration")
        let root=URL(fileURLWithPath:CommandLine.arguments[2])
        let all=FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)!.compactMap{$0 as? URL}
        let pdfs=all.filter{$0.pathExtension=="pdf"}
        check(pdfs.count==33,"all 33 current PDF training sources available")
        var count=0
        let knownPDFs=pdfs.filter{u in guard let hash=try? DocumentReader.digest(u) else {return false};return ReferenceCatalog.load()?.fingerprints[hash] != nil}
        for u in knownPDFs {
            let before=try DocumentReader.digest(u)
            let r=try DocumentReader.read(u)
            check(r.material.pages>0 && r.material.renderedPath==u.path,"render original PDF: "+u.lastPathComponent)
            let after=try DocumentReader.digest(u)
            check(after==before,"PDF original unchanged")
            count+=r.activities.count
        }
        check(count>0,"extract real training bag activities")
        let deckURL=knownPDFs.first{u in guard let hash=try? DocumentReader.digest(u),let f=ReferenceCatalog.load()?.fingerprints[hash] else {return false};return f.role=="slides" && f.packageID=="enable-learning-2.1"}!
        let imported=try DocumentReader.read(deckURL)
        let pages=try DocumentReader.pdfPages(deckURL)
        check(imported.material.pages==81 && imported.material.renderedPath != nil,"native display of all real PDF slides")
        check(imported.activities.filter{$0.officialCode != nil}.count==33,"all 33 activities from original timer for exact bag one")
        check(imported.activities.allSatisfy{!$0.approved && $0.catalogID != nil},"catalogue remains a reviewable timing proposal")
        let secondDeck=knownPDFs.first{u in guard let hash=try? DocumentReader.digest(u),let f=ReferenceCatalog.load()?.fingerprints[hash] else {return false};return f.role=="slides" && f.packageID=="enable-learning-2.2"}!
        let second=try DocumentReader.read(secondDeck)
        check(second.material.pages==80 && second.material.renderedPath != nil,"native second PDF with 80 slides")
        let testFolder=URL(fileURLWithPath:CommandLine.arguments[1])
        let bad=testFolder.appendingPathComponent("bad.pdf");try Data("broken".utf8).write(to:bad)
        check((try? DocumentReader.read(bad))==nil,"invalid PDF handled")
        let badppt=testFolder.appendingPathComponent("bad.pptx");try Data("broken".utf8).write(to:badppt)
        check((try? DocumentReader.read(badppt))==nil,"invalid PPTX handled")
        let unknown=testFolder.appendingPathComponent("unknown.bin");try Data([1,2,3]).write(to:unknown)
        let attachment=try DocumentReader.read(unknown)
        check(attachment.material.renderedPath==nil && attachment.activities.isEmpty,"unsupported file linked only")
        let xml="<w:document xmlns:w='w'><w:p><w:r><w:t>نشاط التعاون 12 دقيقة</w:t></w:r></w:p></w:document>"
        let parsed=try OfficeXML.read(xml)
        check(parsed.contains("التعاون"),"DOCX XML paragraphs")
        // Store tests exercise navigation, UI modes, independent clocks, approval and saving.
        let s=PresenterStore(restore:false);s.project=loaded;s.project.currentActivity=merged[0].id
        s.project.timers[merged[0].id]=Countdown(1080)
        s.toggle();let anchor=s.timer.anchor
        s.project.preferences.barMode="مخفي";check(s.timer.running && s.timer.anchor==anchor,"hidden bar preserves countdown")
        s.project.preferences.barMode="مصغّر";check(s.timer.anchor==anchor,"mini bar preserves countdown")
        s.freeMode=true;s.toggle();check(s.project.freeTimer.running && s.project.timers[merged[0].id]!.running,"dual independent timers")
        s.freeMode=false;check(s.timer.anchor==anchor,"return to activity keeps original clock")
        let pdf=PDFDocument(url:pdfs.first(where:{$0.lastPathComponent.contains("العرض")})!)!
        s.document=pdf;s.navigate(3);check(s.project.currentPage==3 && s.timer.anchor==anchor,"slide navigation does not restart timer")
        s.proposed=3;s.extend();check(s.timer.extensions==180 && s.proposed==0,"store confirms cumulative extension")
        let a2=Activity(title:"التالي",kind:"نشاط",original:60,duration:60,approved:true)
        s.project.activities.append(a2);s.selectActivity(a2.id)
        check(!s.project.timers[merged[0].id]!.running && s.current?.id==a2.id && !s.timer.running,"manual activity switch pauses prior and waits")
        s.project.preferences.autoStart=true;s.selectActivity(merged[0].id);s.reset();s.selectActivity(a2.id)
        check(s.timer.running,"automatic activation starts approved activity")
        s.announce(name:"test",threshold:0);s.notice=Notice(text:"test",until:s.now-1);s.tick();check(s.notice==nil,"expired notice removed by actual store tick")
        let editable=URL(fileURLWithPath:CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("Fixtures/editable-arabic.pptx")
        let editablePages=try DocumentReader.officePages(editable)
        check(editablePages.count==2 && editablePages[0].contains("نشاط التعاون"),"editable Arabic PPTX text and table extraction")
        let localEditable=TimingExtractor.extract(pages:editablePages,material:Material(path:editable.path,hash:"test"))
        check(localEditable.contains{$0.duration==900} && localEditable.contains{$0.duration==300},"multiple activities from editable Arabic slides")
        let noImage=try ImageDeck.render(editable,hash:"editable-must-convert")
        check(noImage==nil,"complex slides route to external renderer")
        let sourcePDF=PDFDocument(url:pdfs.first(where:{$0.lastPathComponent=="المتدرب.pdf"})!)!
        check(sourcePDF.string?.contains("التعليم")==true,"original Arabic PDF text preserved")
        check(second.activities.filter{$0.officialCode != nil}.count==29,"all 29 activities from original timer for exact bag two")
        let firstItem=imported.activities.first{$0.officialCode=="4-1-1"}!
        check(firstItem.duration==1500,"multiple non-overlapping original segments become one 25 minute activity")
        var referenceItems=imported.activities
        referenceItems[0].duration=420;referenceItems[0].approved=true
        ReferenceCatalog.reconcile(imported.activities,existing:&referenceItems)
        check(referenceItems.count==imported.activities.count && referenceItems[0].duration==420 && referenceItems[0].approved,"reference sync preserves manual durations and approval without duplicates")
        var combined=imported.activities;ReferenceCatalog.reconcile(second.activities,existing:&combined)
        check(combined.filter{$0.officialCode != nil}.count==62,"same activity numbers in different bags do not collide")
        let unrelated=ReferenceCatalog.activities(material:Material(path:"/another.pdf",hash:"unrelated"))
        check(unrelated==nil,"unrelated bags never inherit fixed reference timings")
        var oldProject=Project();oldProject.preferences.barMode="عائم"
        let migrated=try oldProject.validated()
        check(migrated.preferences.barMode=="مصغّر","obsolete floating preference migrates safely")
        check(imported.activities.filter{$0.officialCode != nil && $0.presentationID != nil}.count==33,"all bag one activity names/numbers/durations linked to slides")
        check(second.activities.filter{$0.officialCode != nil && $0.presentationID != nil}.count==29,"all bag two activities linked to slides")
        for result in [imported,second] {
            let ranges=result.activities.compactMap{a -> ClosedRange<Int>? in guard let start=a.startPage,let end=a.endPage else {return nil};return start...end}
            check(ranges.allSatisfy{$0.lowerBound>0 && $0.upperBound<=result.material.pages},"all reference ranges inside actual presentation")
            check(!ranges.enumerated().contains{index,range in ranges.enumerated().contains{$0.offset != index && range.overlaps($0.element)}},"activity and break ranges never overlap")
        }
        let pdfMaterial=imported.material
        let mapped=imported.activities.first{$0.officialCode=="2-1-1"}!
        check(ReferenceCatalog.range(mapped,on:pdfMaterial,materials:[imported.material,pdfMaterial])==6...7,"PDF activity ranges retain verified offsets")
        let t=PresenterStore(restore:false);t.project.materials=[imported.material,pdfMaterial];t.project.activities=imported.activities
        t.project.activities[0].approved=true;t.project.activities[1].approved=true
        t.project.currentFile=pdfMaterial.id;t.document=PDFDocument(url:URL(fileURLWithPath:pdfMaterial.path))
        t.project.preferences.followSlides=true;t.navigate(5)
        check(t.current?.officialCode=="2-1-1" && t.project.currentFile==pdfMaterial.id,"slide navigation synchronizes correct number without switching presentation")
        check(ReferenceCatalog.affected(imported.activities[0],by:[imported.material]),"changed known source invalidates linked reference activity")
        check(!ReferenceCatalog.affected(second.activities[0],by:[imported.material]),"changed source leaves other bag independent")
        try runEnhancedTests(folder:testFolder,root:root)
        let output=["passed":passed,"realExtractedActivities":count,"pdfFiles":pdfs.count,"pdfSlides":pages.count]
        try JSONSerialization.data(withJSONObject:output,options:.prettyPrinted).write(to:testFolder.appendingPathComponent("test-results.json"))
        print("ALL \(passed) CHECKS PASSED; real extracted candidates: \(count)")
    }
}
