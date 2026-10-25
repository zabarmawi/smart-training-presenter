import Foundation
import CryptoKit

struct LibraryFile:Codable,Equatable {var role:String;var relativePath:String;var hash:String}
struct LibraryBag:Codable,Identifiable {
    var id:String;var track:String;var domain:String;var title:String;var files:[LibraryFile]
    var activityCount:Int=0;var approvedCount:Int=0;var linkedCount:Int=0
    var issues:[String]=[];var notesReviewed:Bool?=nil;var preparedHashes:[String:String]?=nil
    var complete:Bool {Set(files.map(\.role))==Set(["slides","trainer","learner"]) && files.count==3}
    var changed:Bool {guard complete else {return preparedHashes != nil};return preparedHashes.map{$0 != Dictionary(uniqueKeysWithValues:files.map{($0.role,$0.hash)})} ?? false}
    var status:String {
        if !complete {return "ملفات تحتاج تحديدًا"};if changed {return "المصادر تغيّرت"}
        if preparedHashes==nil {return "لم تُحلّل"}
        return activityCount>0 && approvedCount==activityCount && (issues.isEmpty || notesReviewed==true) ? "جاهزة للتدريب":"تحتاج مراجعة"
    }
    var displayTitle:String {track+" · "+domain+" · "+title}
}
struct TrainingLibrary:Codable {
    var root:String="";var bags:[LibraryBag]=[]
    static var indexURL:URL {DocumentReader.cache.deletingLastPathComponent().appendingPathComponent("Library/index.json")}
    static func projectURL(_ id:String)->URL {indexURL.deletingLastPathComponent().appendingPathComponent("Projects/"+id+".stpresenter")}
    static func load()->TrainingLibrary {(try? JSONDecoder().decode(Self.self,from:Data(contentsOf:indexURL))) ?? Self()}
    func save() throws {
        try FileManager.default.createDirectory(at:Self.indexURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(self).write(to:Self.indexURL,options:.atomic)
    }
    func url(_ file:LibraryFile)->URL {URL(fileURLWithPath:root).appendingPathComponent(file.relativePath)}
    static func key(_ string:String)->String {SHA256.hash(data:Data(string.utf8)).map{String(format:"%02x",$0)}.joined()}
    static func role(_ name:String)->String? {
        let s=TimingExtractor.normalized(name)
        if s.contains("العرض") {return "slides"};if s.contains("المدرب") {return "trainer"};if s.contains("المتدرب") {return "learner"};return nil
    }
    static func scan(_ root:URL,previous:TrainingLibrary=Self()) throws -> Self {
        let root=root.standardizedFileURL.resolvingSymlinksInPath()
        let fm=FileManager.default
        guard let enumerator=fm.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles]) else {throw PresenterError.message("تعذر قراءة مجلد المكتبة")}
        var grouped:[String:[URL]]=[:]
        for case let url as URL in enumerator where url.pathExtension.lowercased()=="pdf" {
            let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard values.isRegularFile==true,values.isSymbolicLink != true,role(url.lastPathComponent) != nil else {continue}
            grouped[url.deletingLastPathComponent().path,default:[]].append(url)
        }
        var bags:[LibraryBag]=[]
        for (folder,files) in grouped {
            let relative=String(folder.dropFirst(root.path.count)).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
            let parts=relative.split(separator:"/").map(String.init)
            let track=parts.first(where:{TimingExtractor.normalized($0).hasPrefix("مسار ")}) ?? root.lastPathComponent
            let trackIndex=parts.firstIndex(of:track)
            let domain=trackIndex.flatMap{parts.indices.contains($0+1) ? parts[$0+1]:nil} ?? parts.first ?? root.lastPathComponent
            let split=files.filter{role($0.lastPathComponent)=="slides"}.count>1
            var sets:[String:[URL]]=[:]
            for file in files {
                let name=TimingExtractor.normalized(file.lastPathComponent)
                var group="single"
                if split {
                    if name.contains("2.1") || name.contains("(1)") {group="1"}
                    else if name.contains("2.2") || name.contains("(2)") {group="2"}
                    else {group="unassigned"}
                }
                sets[group,default:[]].append(file)
            }
            for (group,urls) in sets {
                let title=split ? (group=="1" ? "الحقيبة الأولى":(group=="2" ? "الحقيبة الثانية":"ملفات غير محددة")):(parts.last.map{TimingExtractor.normalized($0).contains("الحقيبة") ? $0.trimmingCharacters(in:.whitespaces):"الحقيبة التدريبية"} ?? "الحقيبة التدريبية")
                let identity=TimingExtractor.normalized(track+"/"+domain+"/"+title)
                let items=try urls.map{LibraryFile(role:role($0.lastPathComponent)!,relativePath:String($0.path.dropFirst(root.path.count+1)),hash:try DocumentReader.digest($0))}.sorted{$0.role<$1.role}
                var bag=LibraryBag(id:key(identity),track:track,domain:domain,title:title,files:items)
                if Set(items.map(\.role)).count != items.count {bag.issues=["تكرر دور أحد الملفات؛ راجع تجميع الحقيبة"]}
                if let old=previous.bags.first(where:{$0.id==bag.id}) ?? previous.bags.first(where:{TimingExtractor.normalized($0.track)==TimingExtractor.normalized(bag.track) && TimingExtractor.normalized($0.domain)==TimingExtractor.normalized(bag.domain) && TimingExtractor.normalized($0.title)==TimingExtractor.normalized(bag.title)}) {
                    bag.id=old.id
                    bag.activityCount=old.activityCount;bag.approvedCount=old.approvedCount;bag.linkedCount=old.linkedCount;bag.preparedHashes=old.preparedHashes;bag.issues += old.issues;bag.notesReviewed=old.notesReviewed
                }
                bags.append(bag)
            }
        }
        return Self(root:root.path,bags:bags.sorted{($0.track,$0.domain,$0.title)<($1.track,$1.domain,$1.title)})
    }
}
