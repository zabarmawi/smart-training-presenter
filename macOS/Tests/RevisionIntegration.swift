import Foundation
import AppKit
import PDFKit
@main struct RevisionIntegration {
 static func main() throws {
    let root=URL(fileURLWithPath:CommandLine.arguments[1]),hash="44a57c424ad9e88a769cc959962f3f0ac054ff1a492da0588b1daf273dacc15c"
    let source=root.appendingPathComponent("test-cache/"+hash+"/images.pdf")
    let original=try DocumentReader.digest(source)
    let document=PDFDocument(url:source)!
    document.documentAttributes=[PDFDocumentAttribute.titleAttribute:"Changed metadata verification"]
    let revised=root.appendingPathComponent("revised-metadata.pdf");document.write(to:revised)
    let imported=try DocumentReader.read(revised)
    var rows:[String]=[]
    func check(_ ok:Bool,_ name:String) {rows.append((ok ? "PASS: ":"FAIL: ")+name)}
    check(imported.material.hash != hash && imported.material.referenceHash==hash,"metadata change recognized against actual known slides")
    check(imported.activities.filter{$0.kind=="نشاط"}.count==33 && imported.activities.allSatisfy{!$0.approved},"revised bag proposes all 33 activities without approval")
    let inserted=PDFPage(image:NSImage(size:NSSize(width:1440,height:810),flipped:false,drawingHandler:{rect in NSColor.red.setFill();rect.fill();return true}))!
    document.insert(inserted,at:5)
    let changed=root.appendingPathComponent("revised-inserted.pdf");document.write(to:changed)
    let next=try DocumentReader.read(changed)
    check(next.material.referenceHash==hash && next.material.referencePageMap?["6"]==7,"actual inserted slide shifts proposed links")
    var existing=imported.activities
    for i in existing.indices {existing[i].approved=true}
    var incoming=next.activities
    for i in incoming.indices {incoming[i].presentationID=imported.material.id}
    let old=Dictionary(uniqueKeysWithValues:existing.map{($0.id,$0.startPage ?? 0)})
    ReferenceCatalog.reconcile(incoming,existing:&existing)
    check(existing.allSatisfy{($0.startPage ?? 0)==old[$0.id]},"reanalysis preserves existing ranges until user accepts proposal")
    check(existing.contains{$0.proposedStartPage != nil && !$0.approved},"shifted links appear as review proposals")
    check(try DocumentReader.digest(source)==original,"reference preview unchanged")
    try rows.joined(separator:"\n").write(to:root.appendingPathComponent("revision-results.txt"),atomically:true,encoding:.utf8)
    print(rows.joined(separator:"\n"));if rows.contains(where:{$0.hasPrefix("FAIL")}) {exit(1)}
 }
}
