import Foundation

// A small, versioned data export from the user's previous timer. It applies only
// to exact, known file hashes: unrelated training bags never inherit these times.
struct ReferenceCatalog:Decodable {
    struct Fingerprint:Decodable {var packageID:String;var role:String}
    struct Link:Codable {var activityID:String;var start:Int;var end:Int;var note:String?}
    struct Package:Decodable {var id:String;var sourceFile:String;var days:[Day]}
    struct Day:Decodable {var day:Int;var sessions:[Session];var externalBreaks:[Break]}
    struct Session:Decodable {var session:Int;var title:String;var activities:[Item];var embeddedBreaks:[Break]}
    struct Item:Decodable {var id:String;var officialCode:String;var title:String;var segments:[Segment];var sourcePage:Int}
    struct Segment:Decodable {var id:String;var title:String;var durationMinutes:Double;var sourcePage:Int}
    struct Placement:Decodable {var status:String;var afterSegmentId:String?;var reason:String?}
    struct Break:Decodable {var afterSession:Int?;var durationMinutes:Double;var sourcePage:Int;var placement:Placement?}
    var packages:[Package]
    var fingerprints:[String:Fingerprint]
    var slideLinks:[String:[Link]]
    var visualSignatures:[String:[[UInt8]]]?
    private static let cached:ReferenceCatalog? = {
        let candidates=[Bundle.main.url(forResource:"reference-catalog",withExtension:"json"),URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/reference-catalog.json")]
        for u in candidates.compactMap({$0}) {if let data=try? Data(contentsOf:u),let c=try? JSONDecoder().decode(Self.self,from:data) {return c}}
        return nil
    }()
    static func load()->ReferenceCatalog? {cached}
    // Old catalog exports used a virtual source ID. Bind only to the exact
    // original trainer PDF for that package, never to a slide, filename guess,
    // or a visually similar revision whose page numbering may have changed.
    @discardableResult static func bindEvidence(in project:inout Project)->Int {
        guard let catalog=load() else {return 0}
        var repaired=0
        for i in project.activities.indices {
            for j in project.activities[i].evidence.indices {
                let evidence=project.activities[i].evidence[j]
                guard evidence.fileID.hasPrefix("reference:") else {continue}
                let package=String(evidence.fileID.dropFirst("reference:".count))
                let candidates=project.materials.filter {material in
                    guard let fingerprint=catalog.fingerprints[material.hash] else {return false}
                    return fingerprint.packageID==package && fingerprint.role=="trainer"
                        && evidence.page>0 && evidence.page<=material.pages
                }
                guard candidates.count==1,let source=candidates.first else {continue}
                project.activities[i].evidence[j].fileID=source.id
                project.activities[i].evidence[j].filename=source.name
                repaired += 1
            }
        }
        return repaired
    }
    func fingerprint(_ material:Material)->Fingerprint? {fingerprints[material.hash] ?? material.referenceHash.flatMap{fingerprints[$0]}}
    func links(_ material:Material)->[Link] {
        let original=slideLinks[material.referenceHash ?? material.hash] ?? []
        guard let map=material.referencePageMap else {return original}
        return original.compactMap {link in
            guard let start=map[String(link.start)],let end=map[String(link.end)],start<=end else {return nil}
            return Link(activityID:link.activityID,start:start,end:end,note:material.versionNote ?? link.note)
        }
    }
    static func activities(material:Material)->[Activity]? {
        guard let c=load(),let f=c.fingerprint(material),let p=c.packages.first(where:{$0.id==f.packageID}) else {return nil}
        var output:[Activity]=[]
        func breakActivity(_ b:Break,_ day:Int,_ session:String,_ key:String)->Activity {
            let unresolved=b.placement?.status=="unresolved"
            let title="استراحة"+(unresolved ? " — موضعها يحتاج مراجعة":"")
            let evidence=Evidence(id:"ref-evidence-"+key,fileID:"reference:"+p.id,filename:"المؤقت السابق · "+p.sourceFile,page:b.sourcePage,excerpt: "مدة الاستراحة \(b.durationMinutes) دقيقة. "+(b.placement?.reason ?? "موضعها مثبت في خريطة المؤقت السابق"),seconds:b.durationMinutes*60)
            return Activity(id:"catalog:"+key,title:title,kind:"استراحة",catalogID:key,day:"اليوم \(day)",session:session,original:b.durationMinutes*60,duration:b.durationMinutes*60,evidence:[evidence])
        }
        for day in p.days {
            var unresolved:[Activity]=[]
            for session in day.sessions {
                let name="الجلسة \(session.session) · "+session.title
                for item in session.activities {
                    let seconds=item.segments.reduce(0){$0+$1.durationMinutes*60}
                    let evidence=Evidence(id:"ref-evidence-"+item.id,fileID:"reference:"+p.id,filename:"المؤقت السابق · "+p.sourceFile,page:item.sourcePage,excerpt:"رقم النشاط: \(item.officialCode) · \(item.title)\n"+item.segments.map{"\($0.title): \($0.durationMinutes) دقيقة"}.joined(separator:"؛ "),seconds:seconds)
                    var a=Activity(id:"catalog:"+item.id,title:item.title,kind:"نشاط",officialCode:item.officialCode,catalogID:item.id,day:"اليوم \(day.day)",session:name,original:seconds,duration:seconds,evidence:[evidence])
                    if f.role=="slides",let link=c.links(material).first(where:{$0.activityID==item.id}) {
                        a.presentationID=material.id;a.startPage=link.start;a.endPage=link.end;a.mappingNote=material.versionNote ?? link.note
                    }
                    output.append(a)
                    for (i,b) in session.embeddedBreaks.enumerated() where b.placement?.afterSegmentId != nil && item.segments.contains(where:{$0.id==b.placement?.afterSegmentId}) {
                        output.append(breakActivity(b,day.day,name,"\(p.id)-d\(day.day)-s\(session.session)-break\(i)"))
                    }
                }
                for (i,b) in session.embeddedBreaks.enumerated() where b.placement?.status=="unresolved" {
                    unresolved.append(breakActivity(b,day.day,name,"\(p.id)-d\(day.day)-s\(session.session)-unplaced\(i)"))
                }
                for (i,b) in day.externalBreaks.enumerated() where b.afterSession==session.session {
                    output.append(breakActivity(b,day.day,name,"\(p.id)-d\(day.day)-external\(i)"))
                }
            }
            output += unresolved
        }
        if f.role=="slides" {
            for i in output.indices where output[i].presentationID==nil {
                if let link=c.links(material).first(where:{$0.activityID==output[i].catalogID}) {
                    output[i].presentationID=material.id;output[i].startPage=link.start;output[i].endPage=link.end;output[i].mappingNote=link.note
                }
            }
        }
        let shared=output.filter{$0.kind=="استراحة" && $0.presentationID != nil}.filter {a in
            output.contains{b in b.id != a.id && b.kind=="استراحة" && b.presentationID==a.presentationID && b.startPage==a.startPage && b.endPage==a.endPage}
        }.map(\.id)
        for i in output.indices where shared.contains(output[i].id) {
            output[i].presentationID=nil;output[i].startPage=nil;output[i].endPage=nil
            output[i].mappingNote="شريحة الاستراحة مشتركة بين مواضع متعددة؛ تُفعّل هذه الاستراحة يدويًا بعد مراجعة ترتيبها"
        }
        return output
    }
    static func affected(_ activity:Activity,by materials:[Material])->Bool {
        if materials.contains(where:{$0.id==activity.presentationID}) {return true}
        guard let id=activity.catalogID,let c=load() else {return false}
        return materials.compactMap{c.fingerprint($0)?.packageID}.contains{id.hasPrefix($0+"-")}
    }
    static func range(_ activity:Activity,on material:Material,materials:[Material])->ClosedRange<Int>? {
        if activity.presentationID==material.id,let start=activity.startPage,let end=activity.endPage,start<=end {return start...end}
        guard let c=load(),let id=activity.catalogID,
              let original=materials.first(where:{$0.id==activity.presentationID}),
              let originalLink=c.links(original).first(where:{$0.activityID==id}),
              activity.startPage==originalLink.start,activity.endPage==originalLink.end,
              let link=c.links(material).first(where:{$0.activityID==id}) else {return nil}
        return link.start...link.end
    }
    // Keep user duration/approval and elapsed time. New source ranges are proposals
    // until approved, and may never silently retarget a running activity.
    static func reconcile(_ incoming:[Activity],existing:inout [Activity]) {
        for a in incoming {
            if let i=existing.firstIndex(where:{$0.catalogID==a.catalogID && a.catalogID != nil}) {
                if a.mappingNote != nil && a.presentationID==existing[i].presentationID {
                    existing[i].mappingNote=a.mappingNote
                    if a.startPage != existing[i].startPage || a.endPage != existing[i].endPage {
                        existing[i].proposedStartPage=a.startPage;existing[i].proposedEndPage=a.endPage
                        existing[i].approved=false
                    }
                }
                if existing[i].presentationID==nil, a.presentationID != nil {
                    existing[i].presentationID=a.presentationID;existing[i].startPage=a.startPage;existing[i].endPage=a.endPage;existing[i].mappingNote=a.mappingNote
                    existing[i].approved=false
                }
            } else {existing.append(a)}
        }
    }
}
