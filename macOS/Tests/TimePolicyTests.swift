import Foundation

@main enum TimePolicyTests {
    static func main()throws {
        var rows:[String]=[]
        func check(_ value:Bool,_ text:String)throws {rows.append((value ? "PASS: ":"FAIL: ")+text);if !value {throw PresenterError.message(text)}}
        let materials=[Material(id:"t",path:"/fixture/دليل المدرب.pdf",hash:"t",libraryRole:"trainer"),Material(id:"l",path:"/fixture/دليل المتدرب.pdf",hash:"l",libraryRole:"learner"),Material(id:"s",path:"/fixture/العرض.pdf",hash:"s",libraryRole:"slides")]
        func e(_ file:String,_ seconds:Double,_ kind:String="نشاط",_ location:String="بطاقة النشاط")->Evidence {Evidence(fileID:file,filename:materials.first{$0.id==file}!.name,page:2,excerpt:location,seconds:seconds,timeKind:kind,location:location)}
        func a(_ sources:[Evidence],_ kind:String="نشاط")->Activity {Activity(id:"stable-activity",title:"حالة معزولة",kind:kind,original:111,duration:111,evidence:sources,presentationID:"s",startPage:3,endPage:4)}
        let agree=a([e("t",900),e("l",900)])
        var proposed=agree;TimeSourcePolicy.propose(&proposed,materials:materials)
        try check(proposed.duration==900 && !proposed.approved && TimeSourcePolicy.assess(agree,materials:materials).sourceLabel=="دليل المدرب ودليل المتدرب","01 guides agree; proposal only")
        let session=a([e("t",7200,"جلسة","إجمالي صريح"),e("l",7200,"جلسة","إجمالي صريح"),e("s",6900,"جلسة","مجموع صفوف الجلسة")],"جلسة")
        let sessionResult=TimeSourcePolicy.assess(session,materials:materials)
        try check(sessionResult.proposed==7200 && sessionResult.deltas==[-300] && sessionResult.requiresReview,"02 explicit guide session total wins over slide sum; delta retained; no redistribution")
        let split=a([e("t",900),e("l",1200)])
        try check(TimeSourcePolicy.assess(split,materials:materials).proposed==nil && TimeSourcePolicy.assess(split,materials:materials).status=="تعارض بين الدليلين","03 guide disagreement unresolved")
        let inside=a([e("t",900,"نشاط","بطاقة النشاط"),e("t",1200,"نشاط","جدول الجلسة · صف النشاط")])
        try check(TimeSourcePolicy.assess(inside,materials:materials).proposed==nil && TimeSourcePolicy.assess(inside,materials:materials).status=="تعارض داخل الدليل","04 card versus table row retains both locations")
        try check(TimeSourcePolicy.assess(a([e("l",600)]),materials:materials).proposed==600 && TimeSourcePolicy.assess(a([e("l",600)]),materials:materials).sourceLabel=="دليل المتدرب","05 only one guide; no false agreement")
        let missing=a([e("s",600)])
        try check(TimeSourcePolicy.assess(missing,materials:materials).proposed==nil && TimeSourcePolicy.assess(missing,materials:materials).requiresReview,"06 both guides absent; auxiliary never trusted automatically")
        var approved=agree;approved.approved=true;approved.original=300;approved.duration=360
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let before=try encoder.encode(approved);TimeSourcePolicy.propose(&approved,materials:materials)
        try check(before==encoder.encode(approved) && TimeSourcePolicy.assess(approved,materials:materials).requiresReview,"07 approved activity byte-equivalent after policy including original duration links evidence")
        let mixed=a([e("t",600),e("t",7200,"جلسة","إجمالي الجلسة")])
        try check(TimeSourcePolicy.assess(mixed,materials:materials).proposed==600 && TimeSourcePolicy.assess(mixed,materials:materials).unrelated.count==1,"08 session total excluded from activity duration")
        let rest=a([e("t",900,"استراحة"),e("l",900,"استراحة")],"استراحة")
        let reflection=a([e("l",300,"تأمل"),e("s",900,"نشاط")],"تأمل")
        let closing=a([e("t",180,"ختام"),e("s",7200,"جلسة")],"ختام")
        try check(TimeSourcePolicy.assess(rest,materials:materials).proposed==900 && TimeSourcePolicy.assess(reflection,materials:materials).proposed==300 && TimeSourcePolicy.assess(closing,materials:materials).proposed==180,"09 break reflection and closing independent")
        try check(proposed.id==agree.id && proposed.evidence==agree.evidence && proposed.presentationID==agree.presentationID && proposed.startPage==3 && proposed.endPage==4 && proposed.original==111,"10 stable IDs sources ranges and original duration")
        var merged=[approved];TimingExtractor.merge([split],into:&merged)
        try check(merged[0].approved && merged[0].duration==360 && merged[0].original==300 && merged[0].startPage==3 && merged[0].evidence.contains(where:{$0.seconds==1200}),"approved value survives new conflicting local evidence; evidence retained")
        let old=Data("{\"showTimer\":true,\"showOvertime\":false,\"muteSound\":false}".utf8)
        let preferences=try JSONDecoder().decode(SharePreferences.self,from:old)
        try check(preferences.showTimer && !preferences.muteSound && preferences.mode == .automatic,"old sharing preferences migrate without losing opt-in settings")
        var project=Project();project.materials=materials;project.activities=[approved];project.filePages=["s":3,"t":11]
        let roundtrip=try JSONDecoder().decode(Project.self,from:encoder.encode(project)).validated()
        try check(roundtrip.filePages==project.filePages && encoder.encode(roundtrip.activities)==encoder.encode(project.activities),"new page positions roundtrip and approved data unchanged")
        let rowsFixture=[GuideRow(text:"النشاط 1-1-1",rect:CGRect(x:250,y:700,width:100,height:20)),GuideRow(text:"نوع النشاط",rect:CGRect(x:300,y:600,width:70,height:18)),GuideRow(text:"المدة الزمنية",rect:CGRect(x:80,y:550,width:70,height:18)),GuideRow(text:"15 دقيقة",rect:CGRect(x:80,y:500,width:60,height:18))]
        let card=GuideReader.cardTimes(rowsFixture,page:7,agenda:[])
        try check(card.count==1 && card[0].seconds==900 && card[0].page==7 && card[0].location.contains("بطاقة"),"future learner card duration retains page and location")
        let totalRows=[GuideRow(text:"إجمالي المدة الزمنية",rect:CGRect(x:280,y:100,width:150,height:20)),GuideRow(text:"120 دقيقة",rect:CGRect(x:70,y:100,width:90,height:20))]
        try check(GuideReader.sessionTotal(totalRows)==7200,"future explicit session total reads separately from row sum")
        let metadataOnly=Material(id:"metadata-guide",path:"/fixture/guide1.pdf",hash:"",libraryRole:"learner")
        let metadataEvidence=Evidence(fileID:metadataOnly.id,filename:metadataOnly.name,page:1,excerpt:"حقل مدة صريح",seconds:420)
        var metadataMerged:[Activity]=[]
        TimingExtractor.merge([a([metadataEvidence,e("s",600)])],into:&metadataMerged,materials:[metadataOnly,materials[2]])
        try check(metadataMerged.first?.duration==420 && metadataMerged.first?.approved==false,"metadata guide role honored during future local merge")
        let retained=TimeSourcePolicy.retaining(approved,adding:split.evidence)
        try check(retained.approved && retained.duration==approved.duration && retained.original==approved.original && retained.id==approved.id && retained.startPage==approved.startPage && approved.evidence.allSatisfy{retained.evidence.contains($0)} && retained.evidence.contains{$0.seconds==1200},"explicit future reread keeps approved value and every prior source while appending new discrepancy")
        let path=CommandLine.arguments[1];try rows.joined(separator:"\n").write(toFile:path,atomically:true,encoding:.utf8);print(rows.joined(separator:"\n"))
    }
}
