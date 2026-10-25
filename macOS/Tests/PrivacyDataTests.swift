import Foundation
import PDFKit

@main struct PrivacyDataTests {
    static func main()throws {
        let libraryURL=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let library=try JSONDecoder().decode(TrainingLibrary.self,from:Data(contentsOf:libraryURL.appendingPathComponent("index.json")))
        var lines:[String]=[],pdfs:[String:PDFDocument]=[:],counts=["bags":library.bags.count,"activities":0,"breaks":0,"evidence":0,"approvals":0]
        func check(_ value:Bool,_ label:String)throws {lines.append((value ? "PASS: ":"FAIL: ")+label);if !value {throw PresenterError.message(label)}}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        for bag in library.bags {
            let url=libraryURL.appendingPathComponent("Projects/"+bag.id+".stpresenter")
            let raw=try JSONDecoder().decode(Project.self,from:Data(contentsOf:url)),loaded=try DocumentReader.load(url)
            try check(encoder.encode(raw.activities)==encoder.encode(loaded.activities),"legacy activities IDs evidence durations approvals preserved: "+bag.id)
            try check(encoder.encode(raw.materials)==encoder.encode(loaded.materials),"legacy material order roles and paths preserved: "+bag.id)
            try check(loaded.timers.values.allSatisfy{!$0.running && $0.anchor==nil} && !loaded.freeTimer.running,"legacy timers open safely paused: "+bag.id)
            for material in loaded.materials {
                if let path=material.renderedPath,pdfs[path]==nil {pdfs[path]=PDFDocument(url:URL(fileURLWithPath:path))}
            }
            for activity in loaded.activities {
                counts[activity.kind=="استراحة" ? "breaks":"activities"]!+=1
                if activity.approved {counts["approvals"]!+=1}
                for source in activity.evidence {
                    let m=loaded.materials.first{$0.id==source.fileID},pdf=m.flatMap{$0.renderedPath}.flatMap{pdfs[$0]}
                    try check(pdf != nil && source.page>0 && source.page <= (pdf?.pageCount ?? 0),"source resolves to existing PDF and valid page: "+source.id)
                    counts["evidence"]!+=1
                }
            }
        }
        counts["pdfs"]=pdfs.count
        let result:[String:Any]=["counts":counts,"checks":lines.count,"failed":lines.filter{$0.hasPrefix("FAIL:")},"notes":"Read saved projects and PDF metadata only; no reindex or activity extraction"]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("data-results.json"))
        try lines.joined(separator:"\n").write(to:out.appendingPathComponent("results.txt"),atomically:true,encoding:.utf8)
        print("PASS: \(lines.count) data checks; \(counts)")
    }
}
