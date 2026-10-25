import Foundation
import PDFKit
@main struct OCRIntegration {
 static func main() throws {
    let root=URL(fileURLWithPath:CommandLine.arguments[1])
    let url=root.appendingPathComponent("عرض مصور جديد.pdf")
    let before=try DocumentReader.digest(url)
    let material=try DocumentReader.read(url)
    let activities=material.activities.filter{$0.kind=="نشاط"}
    let expectedCodes=["1-1-1","2-1-1","3-1-1","4-1-1"]
    let expectedMinutes=[12,18,25,10]
    let pairs=activities.map{a -> [String:Any] in ["code":a.officialCode ?? "","title":a.title,"seconds":a.duration,"page":a.evidence.first?.page ?? 0]}
    let matched=activities.filter{a in guard let i=expectedCodes.firstIndex(of:a.officialCode ?? "") else {return false};return a.duration==Double(expectedMinutes[i]*60)}
    let output:[String:Any]=["found":activities.count,"expected":4,"correctCodeAndDuration":matched.count,"missing":max(0,4-matched.count),"duplicates":activities.count-Set(activities.compactMap(\.officialCode)).count,"ocrPages":material.material.ocrPages ?? 0,"originalUnchanged":try DocumentReader.digest(url)==before,"activities":pairs]
    try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
    print(String(data:try JSONSerialization.data(withJSONObject:output,options:.prettyPrinted),encoding:.utf8)!)
    guard matched.count==4,activities.count==4 else {exit(1)}
 }
}
