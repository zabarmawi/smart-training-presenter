import Foundation
import PDFKit

@main struct LibraryIntegration {
 static var checks:[String]=[]
 static func check(_ ok:Bool,_ name:String) throws {
    checks.append((ok ? "PASS: ":"FAIL: ")+name);print(checks.last!)
    if !ok {throw PresenterError.message(name)}
 }
 static func main() throws {
    let root=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
    let output=URL(fileURLWithPath:CommandLine.arguments[2]).standardizedFileURL
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    var library=try TrainingLibrary.scan(root)
    try check(library.bags.count==11 && library.bags.allSatisfy(\.complete),"stage one: eleven independent complete PDF bags")
    try check(library.bags.flatMap(\.files).count==33 && Set(library.bags.flatMap(\.files).map(\.relativePath)).count==33,"every PDF assigned once to its role")
    let counts=Dictionary(grouping:library.bags,by:{$0.track}).values.map(\.count).sorted()
    try check(counts==[1,5,5],"track distribution is 5 / 5 / 1")
    let pilot=library.bags.first{TimingExtractor.normalized($0.track).contains("الاداء") && $0.domain=="قيادة المنظمة" && TimingExtractor.normalized($0.title).contains("الاولى")}!
    let prepared=try LibraryPreparation.prepare(pilot,in:library)
    let activities=prepared.project.activities.filter{$0.kind=="نشاط"}
    let gold=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"Tests/Fixtures/pilot-org-performance-1.json"))) as! [[String:Any]]
    try check(activities.count==39 && gold.count==39 && Set(activities.compactMap(\.officialCode)).count==39,"stage two: all 39 pilot cards; no omissions or duplicate codes")
    for row in gold {
        let code=row["code"] as! String
        let expected=(row["minutes"] as? Int) ?? 10
        try check(activities.first(where:{$0.officialCode==code})?.duration==Double(expected*60),"pilot duration vs independent PDF reader: "+code)
    }
    try check(activities.first{$0.officialCode=="1-1-1"}?.title=="الترحيب بالمتدربين" && activities.first{$0.officialCode=="2-1-1"}?.title=="نشاط تمهيدي","pilot names match manually inspected first session")
    try check(activities.first{$0.officialCode=="1-1-1"}?.startPage==1 && activities.first{$0.officialCode=="1-1-1"}?.endPage==6 && activities.first{$0.officialCode=="2-1-1"}?.startPage==7,"pilot explicit printed slide references verified")
    try check(activities.first{$0.officialCode=="5-4-2"}?.evidence.contains{$0.page==176}==true && activities.first{$0.officialCode=="5-4-2"}?.mappingNote != nil,"evaluation duration cited to real agenda rather than invented in card")
    try check(activities.allSatisfy{!$0.approved && !$0.evidence.isEmpty} && activities.contains{$0.conflict} && activities.contains{$0.mappingNote?.contains("يتداخل")==true},"conflicting times and overlapping ranges remain explicit unapproved proposals")
    var summaries:[[String:Any]]=[]
    for i in library.bags.indices {
        let bag=library.bags[i]
        let result=bag.id==pilot.id ? prepared:try LibraryPreparation.prepare(bag,in:library)
        let p=result.project;let times=p.activities.filter{!["جلسة","يوم"].contains($0.kind)}
        try check(!p.activities.isEmpty && p.libraryBagID==bag.id,"stage three: prepare "+bag.displayTitle)
        try check(Set(p.activities.map(\.id)).count==p.activities.count && p.activities.allSatisfy{!$0.approved && !$0.evidence.isEmpty},"stable unique activities with sources and manual approval")
        let slides=p.materials.first{$0.libraryRole=="slides"}!
        try check(p.currentFile==slides.id && p.activities.allSatisfy{a in guard a.presentationID != nil else {return true};return a.presentationID==slides.id && (a.startPage ?? 0)>0 && (a.endPage ?? 99999)<=slides.pages},"only actual presentation receives bounded slide links")
        let path=TrainingLibrary.projectURL(bag.id)
        try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
        try DocumentReader.save(p,to:path,now:0)
        library.bags[i].preparedHashes=Dictionary(uniqueKeysWithValues:bag.files.map{($0.role,$0.hash)})
        library.bags[i].activityCount=times.count;library.bags[i].approvedCount=0;library.bags[i].linkedCount=times.filter{$0.presentationID != nil}.count;library.bags[i].issues=result.report.issues
        summaries.append(["id":bag.id,"track":bag.track,"domain":bag.domain,"title":bag.title,"activities":p.activities.filter{$0.kind=="نشاط"}.count,"breaks":times.filter{$0.kind=="استراحة"}.count,"linked":times.filter{$0.presentationID != nil}.count,"agendaRows":result.report.agendaCount,"cards":result.report.cardCount,"notes":result.report.issues,"reviewRequired":p.activities.filter{$0.conflict || $0.mappingNote != nil}.count])
    }
    try library.save()
    let again=try TrainingLibrary.scan(root,previous:library)
    try check(again.bags.map(\.id)==library.bags.map(\.id) && again.bags.allSatisfy{!$0.changed && $0.preparedHashes != nil},"refresh preserves stable identity prepared state and file hashes")
    var prior=prepared.project;prior.activities[0].duration += 60;prior.activities[0].approved=true
    let retained=try LibraryPreparation.prepare(pilot,in:library,previous:prior)
    try check(retained.project.activities[0].duration==prior.activities[0].duration && retained.project.activities[0].approved,"reanalysis keeps approved manual duration for unchanged sources")
    var changed=prior;changed.materials[0].hash="changed"
    let invalidated=try LibraryPreparation.prepare(pilot,in:library,previous:changed)
    try check(!invalidated.project.activities[0].approved && invalidated.project.activities[0].duration==prior.activities[0].duration,"changed source invalidates approval while retaining manual duration")
    let report:[String:Any]=["bags":summaries,"checks":checks,"pilotGoldActivities":39,"totalActivities":summaries.reduce(0){$0+($1["activities"] as! Int)},"totalBreaks":summaries.reduce(0){$0+($1["breaks"] as! Int)}]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("library-validation.json"))
    print("ALL \(checks.count) LIBRARY CHECKS PASSED")
 }
}
