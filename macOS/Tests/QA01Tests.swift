import Foundation
import PDFKit

@main struct QA01Tests {
    static var checks:[String]=[]
    static func check(_ condition:Bool,_ name:String) throws {
        checks.append((condition ? "PASS: ":"FAIL: ")+name)
        print(checks.last!)
        if !condition {throw PresenterError.message(name)}
    }
    static func stripped(_ project:Project)throws->NSDictionary {
        let encoder=JSONEncoder()
        var object=try JSONSerialization.jsonObject(with:encoder.encode(project)) as! [String:Any]
        var activities=object["activities"] as! [[String:Any]]
        for i in activities.indices {
            var evidence=activities[i]["evidence"] as! [[String:Any]]
            for j in evidence.indices {evidence[j].removeValue(forKey:"fileID");evidence[j].removeValue(forKey:"filename")}
            activities[i]["evidence"]=evidence
        }
        object["activities"]=activities
        return object as NSDictionary
    }
    static func main() throws {
        let source=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let index=try Data(contentsOf:source.appendingPathComponent("index.json"))
        let library=try JSONDecoder().decode(TrainingLibrary.self,from:index)
        let projects=out.appendingPathComponent("Library/Projects")
        try FileManager.default.createDirectory(at:projects,withIntermediateDirectories:true)
        try index.write(to:out.appendingPathComponent("Library/index.json"))
        var repaired=0,totalEvidence=0;var detail:[[String:Any]]=[]
        for bag in library.bags {
            let file=source.appendingPathComponent("Projects/"+bag.id+".stpresenter")
            let raw=try JSONDecoder().decode(Project.self,from:Data(contentsOf:file))
            var project=raw
            let count=ReferenceCatalog.bindEvidence(in:&project);repaired += count
            try check(try stripped(raw).isEqual(stripped(project)),"only source ID/name change: "+bag.displayTitle)
            try check(ReferenceCatalog.bindEvidence(in:&project)==0,"idempotent binding: "+bag.id)
            let loaded=try DocumentReader.load(file)
            try check(loaded.activities.map{$0.evidence.map(\.fileID)}==project.activities.map{$0.evidence.map(\.fileID)},"old saved project repaired on load: "+bag.id)
            for m in project.materials {
                try check(try DocumentReader.digest(URL(fileURLWithPath:m.path))==m.hash,"source exists with exact hash: "+m.id)
            }
            for a in project.activities {
                for e in a.evidence {
                    let material=project.materials.first{$0.id==e.fileID}
                    let pdf=material.flatMap{PDFDocument(url:URL(fileURLWithPath:$0.renderedPath ?? $0.path))}
                    try check(material != nil && pdf != nil && e.page>0 && e.page <= (pdf?.pageCount ?? 0),"resolvable evidence + actual PDF page: "+a.id+" / "+e.id)
                    totalEvidence += 1
                }
            }
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(project).write(to:projects.appendingPathComponent(bag.id+".stpresenter"),options:.atomic)
            if count>0 {
                var fresh=Project();fresh.materials=raw.materials
                fresh.activities=ReferenceCatalog.activities(material:raw.materials.first{$0.libraryRole=="slides"}!)!
                try check(ReferenceCatalog.bindEvidence(in:&fresh)==count,"new catalog generation binds every reference: "+bag.id)
                var missing=raw;missing.materials.removeAll{$0.libraryRole=="trainer"}
                try check(ReferenceCatalog.bindEvidence(in:&missing)==0,"missing trainer never guesses another PDF")
                var revised=raw;for i in revised.materials.indices where revised.materials[i].libraryRole=="trainer" {revised.materials[i].referenceHash=revised.materials[i].hash;revised.materials[i].hash="modified-trainer"}
                try check(ReferenceCatalog.bindEvidence(in:&revised)==0,"visually related trainer cannot reuse original pages")
                var duplicate=raw;var clone=raw.materials.first{$0.libraryRole=="trainer"}!;clone.id += "-duplicate";duplicate.materials.append(clone)
                try check(ReferenceCatalog.bindEvidence(in:&duplicate)==0,"ambiguous duplicate trainer not guessed")
                var invalid=raw;invalid.activities=Array(invalid.activities.prefix(1));invalid.activities[0].evidence[0].page=99999
                try check(ReferenceCatalog.bindEvidence(in:&invalid)==0,"invalid source page not bound")
            }
            detail.append(["id":bag.id,"repaired":count,"activities":project.activities.count,"approved":project.activities.filter(\.approved).count])
        }
        try check(repaired==70,"all seventy legacy references repaired")
        try check(library.bags.count==11,"all eleven bags checked without reanalysis")
        let report:[String:Any]=["repaired":repaired,"evidenceValidated":totalEvidence,"checks":checks,"bags":detail]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("qa01-tests.json"))
        print("ALL \(checks.count) QA01 CHECKS PASSED; repaired=\(repaired); evidence=\(totalEvidence)")
    }
}
