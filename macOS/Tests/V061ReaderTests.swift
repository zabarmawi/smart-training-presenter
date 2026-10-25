import Foundation
import PDFKit
@main enum V061ReaderTests {
    static func main()throws {
        let base=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let library=try JSONDecoder().decode(TrainingLibrary.self,from:Data(contentsOf:base.appendingPathComponent("index.json")))
        guard let bag=library.bags.filter({$0.complete && $0.activityCount>0}).min(by:{$0.activityCount<$1.activityCount}) else {throw PresenterError.message("No prepared fixture")}
        let project=try DocumentReader.load(base.appendingPathComponent("Projects/"+bag.id+".stpresenter"))
        let t=project.materials.first{$0.libraryRole=="trainer"}!,s=project.materials.first{$0.libraryRole=="slides"}!,l=project.materials.first{$0.libraryRole=="learner"}!
        let result=GuideReader.read(trainer:t,slides:s,learner:l)
        var lines:[String]=[]
        func check(_ ok:Bool,_ label:String)throws {lines.append((ok ? "PASS: ":"FAIL: ")+label);if !ok {throw PresenterError.message(label)}}
        try check(result.cardCount>0 && result.agendaCount>0 && !result.activities.isEmpty,"real local PDF cards and agendas still extract without external feature")
        try check(result.activities.allSatisfy{!$0.approved},"all new extracted values remain unapproved")
        try check(Set(result.activities.map(\.id)).count==result.activities.count,"future read produces unique stable identities")
        try check(result.activities.allSatisfy{a in a.evidence.allSatisfy{e in [t,s,l].contains{$0.id==e.fileID && e.page>0 && e.page<=$0.pages}}},"future references resolve to correct material and page")
        try check(result.activities.filter{$0.kind=="جلسة"}.allSatisfy{$0.evidence.allSatisfy{$0.timeKind=="جلسة"}},"session totals stay separate from activity and break evidence")
        var previous=project
        let selected=previous.activities.firstIndex(where:{$0.kind=="نشاط"})!
        previous.activities[selected].approved=true;previous.activities[selected].duration+=17
        let approved=previous.activities[selected]
        let missing=Activity(id:"approved-missing-fixture",title:"قيمة معتمدة غير موجودة في القراءة الجديدة",kind:"تأمل",original:120,duration:150,evidence:approved.evidence,approved:true)
        previous.activities.append(missing)
        let prepared=try LibraryPreparation.prepare(bag,in:library,previous:previous).project
        let retained=prepared.activities.first{$0.id==approved.id}!
        try check(retained.approved && retained.duration==approved.duration && retained.original==approved.original && retained.startPage==approved.startPage && retained.endPage==approved.endPage,"real isolated reprepare keeps approved modified time and slide range")
        try check(approved.evidence.allSatisfy{retained.evidence.contains($0)},"real isolated reprepare retains every prior evidence ID and value")
        try check(prepared.activities.contains{$0.id==missing.id && $0.approved && $0.duration==150 && $0.original==120},"approved activity absent from new read remains approved and retained")
        let summary:[String:Any]=["bag":bag.displayTitle,"cards":result.cardCount,"agenda":result.agendaCount,"timeElements":result.activities.count,"sessions":result.activities.filter{$0.kind=="جلسة"}.count,"sourceCount":result.activities.reduce(0){$0+$1.evidence.count},"issues":result.issues,"checks":lines,"note":"One existing bag read in memory only. No reindex, preparation, project write, or other bag extraction."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out)
        print(lines.joined(separator:"\n"))
    }
}
