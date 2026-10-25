import Foundation
import AppKit
import PDFKit

struct ThirdBag {
    static let names=["استكشاف الاحتياجات","تحليل الموقف","تخطيط الحلول","تقويم التعلم"]
    static let codes=["1-1-1","2-1-1","3-1-1","4-1-1"]
    static let minutes=[12,18,25,10]
    static func create(at folder:URL) throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let native=folder.appendingPathComponent("عرض جديد.pdf"),raster=folder.appendingPathComponent("عرض مصور جديد.pdf")
        var box=CGRect(x:0,y:0,width:1000,height:700)
        let vector=CGContext(native as CFURL,mediaBox:&box,nil)!,imagePDF=CGContext(raster as CFURL,mediaBox:&box,nil)!
        for i in 0..<4 {
            let lines=["اليوم الأول","الجلسة الأولى", "النشاط: \(names[i])",codes[i],"مدة النشاط: \(minutes[i]) دقيقة","ناقش مع مجموعتك ثم قدم النتائج"]
            func draw(_ context:CGContext) {
                context.setFillColor(CGColor(gray:1,alpha:1));context.fill(box)
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
                let style=NSMutableParagraphStyle();style.alignment = .right;style.baseWritingDirection = .rightToLeft
                for (j,line) in lines.enumerated() {
                    style.baseWritingDirection = j==3 ? .leftToRight:.rightToLeft
                    let font=NSFont(name:"Arial",size:j==2 ? 42:34) ?? .systemFont(ofSize:34)
                    (line as NSString).draw(in:NSRect(x:50,y:560-j*80,width:900,height:88),withAttributes:[.font:font,.foregroundColor:NSColor.black,.paragraphStyle:style])
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            vector.beginPDFPage(nil);draw(vector);vector.endPDFPage()
            let context=CGContext(data:nil,width:1600,height:1120,bitsPerComponent:8,bytesPerRow:1600*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x:1.6,y:1.6);draw(context)
            imagePDF.beginPDFPage(nil);imagePDF.draw(context.makeImage()!,in:box);imagePDF.endPDFPage()
        }
        vector.closePDF();imagePDF.closePDF()
        let csv="رقم النشاط,اسم النشاط,المدة بالدقائق,اليوم,الجلسة\n"+(0..<4).map{"\(codes[$0]),\(names[$0]),\(minutes[$0]),اليوم الأول,الجلسة الأولى"}.joined(separator:"\n")
        try csv.write(to:folder.appendingPathComponent("جدول أنشطة جديد.csv"),atomically:true,encoding:.utf8)
        let gold=(0..<4).map{["code":codes[$0],"title":names[$0],"minutes":String(minutes[$0])]}
        try JSONSerialization.data(withJSONObject:gold,options:.prettyPrinted).write(to:folder.appendingPathComponent("expected.json"))
    }
}
@MainActor func runEnhancedTests(folder:URL,root:URL) throws {
    let bag=folder.deletingLastPathComponent().appendingPathComponent("Fixtures/third-bag")
    try ThirdBag.create(at:bag)
    let pdf=bag.appendingPathComponent("عرض جديد.pdf")
    let native=try DocumentReader.read(pdf)
    let activities=native.activities.filter{$0.kind=="نشاط"}
    check(activities.count==4,"unseen native Arabic bag extracts four distinct activities")
    check(Set(activities.compactMap(\.officialCode))==Set(ThirdBag.codes),"unseen bag preserves printed activity numbers")
    check(activities.allSatisfy{a in guard let i=ThirdBag.codes.firstIndex(of:a.officialCode ?? "") else {return false};return a.duration==Double(ThirdBag.minutes[i]*60)},"unseen bag exact durations without reference lookup")
    check(activities.allSatisfy{$0.catalogID==nil && !$0.approved && !$0.evidence.isEmpty && $0.day=="اليوم 1"},"unseen bag evidence and hierarchy remain unapproved")
    let csv=try DocumentReader.read(bag.appendingPathComponent("جدول أنشطة جديد.csv"))
    check(csv.activities.count==4 && csv.activities.map(\.duration)==ThirdBag.minutes.map{Double($0*60)},"CSV units come from header without guessing")
    var merged=csv.activities;TimingExtractor.merge(activities,into:&merged)
    check(merged.count==4 && merged.allSatisfy{$0.presentationID==native.material.id},"guide and presentation synchronize by number with no duplicate activities")
    let ambiguous=TimingExtractor.extract(pages:["النشاط 1-1-1: العمل\nالزمن: حوالي 15 دقيقة\nالجلسة الثانية 90 دقيقة"],material:Material(path:"/unseen/guide.txt",hash:"unknown"))
    check(!ambiguous.contains{$0.kind=="نشاط"} && ambiguous.contains{$0.kind=="جلسة"},"ambiguous timing not borrowed from session total")
    let fragments=TimingExtractor.extract(pages:["نشاط 1-1-1: التحليل\nتحليل فردي 10 دقائق\nمناقشة 15 دقيقة"],material:Material(path:"/unseen/guide.txt",hash:"unknown"))
    check(fragments.count==1 && fragments[0].conflict && fragments[0].duration != 1500,"multiple unlabeled segment times require review rather than summing")

    let s=PresenterStore(restore:false);s.project.materials=[native.material];s.document=PDFDocument(url:pdf)
    s.project.activities=activities;for i in s.project.activities.indices {s.project.activities[i].approved=true}
    s.selectActivity(activities[0].id);s.toggle();let anchor=s.timer.anchor
    s.navigate(3)
    check(!s.project.preferences.followsSlides && s.current?.id==activities[0].id && s.timer.anchor==anchor && s.timer.running,"safe preview is default and preserves active countdown across activity slides")
    s.setFollowing(true);s.navigate(3)
    check(s.current?.officialCode==ThirdBag.codes[3] && !s.project.timers[activities[0].id]!.running,"explicit follow mode changes activity only by user choice")
    s.project.preferences.autoStart=true;s.beginActivity(activities[0].id);let activeAnchor=s.timer.anchor
    s.previewSource(Evidence(fileID:native.material.id,filename:"guide",page:4,excerpt:"source",seconds:60))
    check(s.current?.id==activities[0].id && s.timer.anchor==activeAnchor,"source preview never switches activity even in follow mode")
    s.freeMode=true;s.project.freeTimer=Countdown(300);s.toggle();s.setFollowing(false);s.navigate(2)
    check(s.freeMode && s.project.freeTimer.running && s.project.timers[activities[0].id]!.running,"preview protects both independent timers")
    s.beginActivity(activities[1].id)
    check(!s.freeMode && s.current?.id==activities[1].id && s.timer.running && !s.review,"begin reviewed activity selects starts and closes review")

    let proof=folder.appendingPathComponent("portable-proof-"+UUID().uuidString)
    let originals=proof.appendingPathComponent("originals");try FileManager.default.createDirectory(at:originals,withIntermediateDirectories:true)
    let source=originals.appendingPathComponent("source.pdf");try FileManager.default.copyItem(at:pdf,to:source)
    var p=Project();let imported=try DocumentReader.read(source);p.materials=[imported.material];p.activities=imported.activities;p.currentFile=imported.material.id;p.name="Portable verification"
    p.activities[0].approved=true;p.activities[0].duration=780;p.freeTimer=Countdown(600);p.freeTimer.toggle(0);p.freeTimer.extend(120,now:100)
    let package=proof.appendingPathComponent("training.stbag")
    let saved=try PortableProject.save(p,to:package,now:100)
    check(saved.materials[0].path.hasPrefix(package.path) && saved.materials[0].hash==p.materials[0].hash,"portable package includes source and retains original hash")
    let relocated=proof.appendingPathComponent("relocated/training.stbag")
    try FileManager.default.createDirectory(at:relocated.deletingLastPathComponent(),withIntermediateDirectories:true)
    try FileManager.default.moveItem(at:package,to:relocated);try FileManager.default.removeItem(at:originals)
    let loaded=try DocumentReader.load(relocated)
    check(PDFDocument(url:URL(fileURLWithPath:loaded.materials[0].renderedPath!))?.pageCount==4,"portable bag opens after relocation and removal of originals")
    check(loaded.activities[0].approved && loaded.activities[0].duration==780 && !loaded.freeTimer.running && loaded.freeTimer.extensions==120,"portable transfer preserves approval manual duration and timer checkpoint")
    let overwritten=try PortableProject.save(loaded,to:relocated,now:100)
    check(FileManager.default.fileExists(atPath:overwritten.materials[0].path),"atomic portable save replaces existing package safely")
    check((try? PortableProject.resolve("../../outside.txt",inside:relocated))==nil,"portable reader rejects traversal")
    let link=relocated.appendingPathComponent("escape");try FileManager.default.createSymbolicLink(atPath:link.path,withDestinationPath:proof.path)
    check((try? PortableProject.resolve("escape/file",inside:relocated))==nil,"portable reader rejects symlink escape")

    let signature=[UInt8](repeating:80,count:384)
    let refs=["reference":[signature,[UInt8](repeating:140,count:384),[UInt8](repeating:200,count:384)]]
    let version=DocumentRevision.suggest(refs["reference"]!,references:refs)
    check(version?.pageMap==["1":1,"2":2,"3":3],"metadata-only revision recognized by visual content")
    var inserted=refs["reference"]!;inserted.insert([UInt8](repeating:240,count:384),at:1)
    // A short document with one extra slide has only 75% coverage and stays unknown.
    check(DocumentRevision.suggest(inserted,references:refs)==nil,"weak visual similarity cannot assign old timings")
    let long=(0..<20).map{[UInt8](repeating:UInt8($0*10),count:384)}
    var shifted=long;shifted.insert([UInt8](repeating:251,count:384),at:5)
    let proposed=DocumentRevision.suggest(shifted,references:["long":long])
    check(proposed?.pageMap["6"]==7 && proposed?.changedPages==[6],"modified version proposes shifted ranges and identifies inserted page")
    check(DocumentRevision.suggest(long,references:["a":long,"b":long])==nil,"ambiguous reference versions require manual review")

    var dayTimer=Countdown(8*3600);dayTimer.toggle(1000);var fired:[Int]=[]
    for step in 1...21600 {fired += dayTimer.poll(1000+Double(step*2))}
    check(fired==[300,60,0] && dayTimer.remaining(44200)==(-14400),"twelve-hour virtual session keeps exact overtime and single alerts")
    let restore=proof.appendingPathComponent("recovery.stpresenter");let writer=RecoveryWriter()
    var recovery=Project();recovery.name="latest"
    writer.schedule(Project(),to:restore,now:0,onError:{_ in});try writer.flush(recovery,to:restore,now:0)
    let latest=try DocumentReader.load(restore)
    check(latest.name=="latest","recovery flush commits latest state after coalesced edits")
    let report:[String:Any]=["bag":"third-bag","expected":4,"found":activities.count,"correctCodes":activities.filter{ThirdBag.codes.contains($0.officialCode ?? "")}.count,"wrongDurations":activities.filter{a in guard let i=ThirdBag.codes.firstIndex(of:a.officialCode ?? "") else {return true};return a.duration != Double(ThirdBag.minutes[i]*60)}.count,"missing":max(0,4-activities.count),"duplicates":activities.count-Set(activities.compactMap(\.officialCode)).count]
    try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:folder.appendingPathComponent("third-bag-results.json"))
}
