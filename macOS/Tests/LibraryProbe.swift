import Foundation
@main struct LibraryProbe {
 static func main() throws {
    let root=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL;let library=try TrainingLibrary.scan(root)
    print("BAGS",library.bags.count)
    let pilot=library.bags.first{TimingExtractor.normalized($0.track).contains("الاداء") && $0.domain=="قيادة المنظمة" && TimingExtractor.normalized($0.title).contains("الاولى")}!
    let prepared=try LibraryPreparation.prepare(pilot,in:library)
    let r=prepared.report
    print("PILOT",pilot.displayTitle,"agenda",r.agendaCount,"cards",r.cardCount,"activities",r.activities.count,"linked",r.activities.filter{$0.presentationID != nil}.count)
    print("ISSUES",r.issues)
    for a in r.activities {print(a.officialCode ?? "?",a.title,a.duration/60,a.startPage ?? 0,a.endPage ?? 0,a.mappingNote ?? "",a.evidence.map{$0.page})}
 }
}
