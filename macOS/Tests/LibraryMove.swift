import Foundation
@main struct LibraryMove {
 static func main() throws {
    let fm=FileManager.default,root=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("move-proof-"+UUID().uuidString)
    let domain=root.appendingPathComponent("مسار تجريبي/قيادة المنظمة")
    try fm.createDirectory(at:domain,withIntermediateDirectories:true)
    for number in 1...2 {
        for name in ["العرض التقديمي (2.\(number)).pdf","حقيبة المدرب (\(number)).pdf","حقيبة المتدرب (\(number)).pdf"] {try Data(name.utf8).write(to:domain.appendingPathComponent(name))}
    }
    var before=try TrainingLibrary.scan(root)
    for i in before.bags.indices {before.bags[i].preparedHashes=Dictionary(uniqueKeysWithValues:before.bags[i].files.map{($0.role,$0.hash)});before.bags[i].activityCount=3;before.bags[i].approvedCount=1}
    for number in 1...2 {
        let folder=domain.appendingPathComponent(number==1 ? "الحقيبة الأولى":"الحقيبة الثانية")
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        for file in try fm.contentsOfDirectory(at:domain,includingPropertiesForKeys:nil) where file.pathExtension=="pdf" && (file.lastPathComponent.contains("(\(number))") || file.lastPathComponent.contains("2.\(number)")) {try fm.moveItem(at:file,to:folder.appendingPathComponent(file.lastPathComponent))}
    }
    let split=try TrainingLibrary.scan(root,previous:before)
    guard Set(split.bags.map(\.id))==Set(before.bags.map(\.id)),split.bags.allSatisfy({!$0.changed && $0.approvedCount==1}) else {throw PresenterError.message("split lost stable identity or review")}
    print("PASS: splitting folders preserves identities approvals and prepared hashes")
    let relocated=root.deletingLastPathComponent().appendingPathComponent("relocated-"+UUID().uuidString);try fm.moveItem(at:root,to:relocated)
    let moved=try TrainingLibrary.scan(relocated,previous:split)
    guard moved.bags.map(\.id)==split.bags.map(\.id),moved.bags.flatMap(\.files).allSatisfy({fm.fileExists(atPath:moved.url($0).path)}) else {throw PresenterError.message("root relocation lost source resolution")}
    print("PASS: moving library root preserves review and resolves new source paths")
    let first=moved.bags[0],trainer=moved.url(first.files.first{$0.role=="trainer"}!)
    try Data("extra".utf8).write(to:trainer.deletingLastPathComponent().appendingPathComponent("المدرب الإضافي.pdf"))
    let duplicate=try TrainingLibrary.scan(relocated,previous:moved)
    guard duplicate.bags.contains(where:{!$0.complete && $0.changed && $0.status=="ملفات تحتاج تحديدًا"}) else {throw PresenterError.message("duplicate roles not detected")}
    print("PASS: duplicate roles require review without crashing")
    try fm.removeItem(at:relocated)
 }
}
