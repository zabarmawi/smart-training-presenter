import Foundation

import PDFKit
import CryptoKit
import Darwin

struct CommandResult { var status:Int32; var text:String }
func command(_ executable:String,_ arguments:[String],timeout:Double=90) throws -> CommandResult {
    let log=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath:log.path,contents:nil)
    let handle=try FileHandle(forWritingTo:log)
    defer { try? handle.close(); try? FileManager.default.removeItem(at:log) }
    let p=Process(); p.executableURL=URL(fileURLWithPath:executable); p.arguments=arguments
    p.standardOutput=handle; p.standardError=handle
    try p.run()
    let limit=Date().addingTimeInterval(timeout)
    while p.isRunning && Date()<limit {
        Thread.sleep(forTimeInterval:0.05)
        if let size=(try? FileManager.default.attributesOfItem(atPath:log.path)[.size]) as? NSNumber, size.intValue > 50_000_000 {
            p.terminate(); throw PresenterError.message("تجاوز النص المستخرج الحد الآمن")
        }
    }
    if p.isRunning { p.terminate(); let grace=Date().addingTimeInterval(1);while p.isRunning && Date()<grace {Thread.sleep(forTimeInterval:0.05)};if p.isRunning {Darwin.kill(p.processIdentifier,SIGKILL)};p.waitUntilExit();throw PresenterError.message("انتهت مهلة المعالجة. جرّب PDF أو تحقق من محرك التحويل") }
    p.waitUntilExit()
    return CommandResult(status:p.terminationStatus,text:String(data:(try? Data(contentsOf:log)) ?? Data(),encoding:.utf8) ?? "")
}
final class OfficeXML: NSObject, XMLParserDelegate {
    var text=""; var inText=false;var inRow=false
    func parser(_ parser:XMLParser,didStartElement element:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        if element=="w:tr" {inRow=true}
        if element=="a:t" || element=="w:t" { inText=true }
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) { if inText { text += string } }
    func parser(_ parser:XMLParser,didEndElement element:String,namespaceURI:String?,qualifiedName:String?) {
        if element=="a:t" || element=="w:t" { inText=false; text += " " }
        if element=="a:p" || (element=="w:p" && !inRow) {text += "\n"}
        if element=="w:tc" {text += "\t"}
        if element=="w:tr" {text += "\n";inRow=false}
    }
    static func read(_ xml:String) throws -> String {
        let d=OfficeXML(); let parser=XMLParser(data:Data(xml.utf8)); parser.shouldResolveExternalEntities=false; parser.delegate=d
        guard parser.parse() else { throw PresenterError.message("محتوى Office تالف") }; return d.text
    }
}
struct ImportResult { var material:Material; var activities:[Activity] }
struct DocumentReader {
    static var cache:URL {
        if let custom=ProcessInfo.processInfo.environment["PRESENTER_CACHE"] { return URL(fileURLWithPath:custom) }
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SmartTrainingPresenter/Cache")
    }
    static func digest(_ url:URL) throws -> String {
        let h=try FileHandle(forReadingFrom:url); defer { try? h.close() }
        var hash=SHA256()
        while let d=try h.read(upToCount:1024*1024), !d.isEmpty { hash.update(data:d) }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    static func slideEntries(_ url:URL) throws -> [String] {
        let presentation=try ImageDeck.xml(url,"ppt/presentation.xml")
        let relationships=try ImageDeck.xml(url,"ppt/_rels/presentation.xml.rels")
        let rels=try relationships.nodes(forXPath:"//*[local-name()='Relationship']").compactMap{$0 as? XMLElement}
        let ids=try presentation.nodes(forXPath:"//*[local-name()='sldIdLst']/*[local-name()='sldId']").compactMap{$0 as? XMLElement}
        return try ids.map { node in
            guard let id=node.attributes?.first(where:{$0.prefix=="r" && $0.localName=="id"})?.stringValue,
                  let rel=rels.first(where:{$0.attribute(forName:"Id")?.stringValue==id}),
                  rel.attribute(forName:"TargetMode")?.stringValue != "External",
                  let target=rel.attribute(forName:"Target")?.stringValue,
                  target.range(of:"^slides/slide[0-9]+\\.xml$",options:.regularExpression) != nil else {
                throw PresenterError.message("ترتيب شرائح PPTX غير صالح")
            }
            return "ppt/"+target
        }
    }
    static func officePages(_ url:URL) throws -> [String] {
        let listing=try command("/usr/bin/unzip",["-Z1",url.path])
        guard listing.status==0 else { throw PresenterError.message("ملف Office غير صالح") }
        let isPPT=url.pathExtension.lowercased()=="pptx"
        let names = isPPT ? try slideEntries(url) : ["word/document.xml"].filter { listing.text.components(separatedBy:.newlines).contains($0) }
        guard !names.isEmpty,names.count<2001 else { throw PresenterError.message("لا توجد صفحات قابلة للقراءة أو تجاوز الملف 2000 صفحة") }
        return try names.map { name in
            let r=try command("/usr/bin/unzip",["-p",url.path,name]); guard r.status==0 else { throw PresenterError.message("تعذر فك محتوى المستند") }
            return try OfficeXML.read(r.text)
        }
    }
    static func pdfPages(_ url:URL) throws -> [String] {
        guard let doc=PDFDocument(url:url),!doc.isLocked,doc.pageCount>0,doc.pageCount<=2000 else {
            throw PresenterError.message("PDF تالف أو مقفل أو يتجاوز 2000 صفحة")
        }
        return (0..<doc.pageCount).map { doc.page(at:$0)?.string ?? "" }
    }
    static func converterPath() -> String? {
        let candidates=[ProcessInfo.processInfo.environment["PRESENTER_CONVERTER"] ?? "",UserDefaults.standard.string(forKey:"converter") ?? "", "/Applications/LibreOffice.app/Contents/MacOS/soffice", "/Applications/LibreOfficeDev.app/Contents/MacOS/soffice"]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath:$0) }
    }
    static func convert(_ url:URL,hash:String) throws -> URL {
        let folder=cache.appendingPathComponent(hash)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let output=folder.appendingPathComponent("slides.pdf")
        if let d=PDFDocument(url:output),d.pageCount>0 { return output }
        // Work only on a copy, never hand an original to an Office editing application.
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("presenter-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temp) }
        let source=temp.appendingPathComponent("presenter-"+UUID().uuidString+"."+url.pathExtension.lowercased())
        try FileManager.default.copyItem(at:url,to:source)
        if let converter=converterPath() {
            let profile=temp.appendingPathComponent("profile").absoluteString
            let r=try command(converter,["-env:UserInstallation="+profile,"--headless","--convert-to","pdf","--outdir",temp.path,source.path],timeout:180)
            let pdf=source.deletingPathExtension().appendingPathExtension("pdf")
            guard r.status==0,FileManager.default.fileExists(atPath:pdf.path) else {
                throw PresenterError.message("تعذر التحويل: "+String(r.text.suffix(600)))
            }
            try FileManager.default.copyItem(at:pdf,to:output)
        } else if FileManager.default.fileExists(atPath:"/Applications/Microsoft PowerPoint.app") {
            try PowerPointConversion.convert(source:source,output:output,folder:temp)
        } else { throw PresenterError.message("يتطلب عرض PPTX/PPT تثبيت PowerPoint أو تحديد LibreOffice في الإعدادات. يمكنك استيراد PDF الآن") }
        guard let d=PDFDocument(url:output),d.pageCount>0 else {
            try? FileManager.default.removeItem(at:output); throw PresenterError.message("لم ينتج المحول PDF صالحًا")
        }
        return output
    }
    static func read(_ url:URL,existing:Material?=nil) throws -> ImportResult {
        let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 512*1024*1024 else { throw PresenterError.message("يتجاوز الملف الحد التجريبي 512 ميغابايت") }
        let hash=try digest(url)
        var m=existing ?? Material(path:url.path,hash:hash)
        if m.hash != hash {m.referenceHash=nil;m.referencePageMap=nil;m.versionNote=nil}
        m.hash=hash
        if m.sourceGroup==nil {m.sourceGroup=url.deletingLastPathComponent().path}
        let ext=url.pathExtension.lowercased(); var pages:[String]=[]
        switch ext {
        case "pdf":
            DocumentRevision.inspect(url,material:&m)
            let text=try DocumentText.readPDF(url,hash:hash,allowOCR:ReferenceCatalog.load()?.fingerprint(m)==nil)
            pages=text.pages;m.ocrPages=text.ocrPages;m.extractedPages=pages.filter{!$0.isEmpty}.count
            m.renderedPath=url.path;m.pages=pages.count
            m.status=pages.joined().trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "PDF مصوّر — لم يُستخرج نص قابل للقراءة":((m.ocrPages ?? 0)>0 ? "PDF أصلي · قراءة محلية للصور \(m.ocrPages ?? 0) صفحة":"PDF أصلي")
        case "pptx","ppt":
            if ext=="pptx" { pages=try officePages(url) }
            do {
                let direct = ext=="pptx" ? try ImageDeck.render(url,hash:hash) : nil
                let output=try direct ?? convert(url,hash:hash); m.renderedPath=output.path
                let native=try pdfPages(output);m.pages=native.count
                DocumentRevision.inspect(output,material:&m)
                if pages.allSatisfy({$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}),ReferenceCatalog.load()?.fingerprint(m)==nil {
                    let read=try DocumentText.readPDF(output,hash:hash)
                    pages=read.pages;m.ocrPages=read.ocrPages;m.extractedPages=pages.filter{!$0.isEmpty}.count
                } else if pages.isEmpty {pages=native}
                m.status=direct != nil ? "شرائح مصوّرة أصلية · عرض ثابت · قراءة محلية \(m.ocrPages ?? 0) صفحة":"عرض ثابت محوّل — بلا حركات أو فيديو؛ راجع الخطوط والتخطيط"
            } catch {
                m.renderedPath=nil; m.status=error.localizedDescription
                if ext=="ppt" { pages=[] }
            }
        case "docx": pages=try officePages(url); m.status="استخراج نصوص وجداول DOCX فقط"
        case "txt","md","csv","tsv":
            pages=[try String(contentsOf:url,encoding:.utf8)]; m.status="قراءة نص UTF-8 فقط"
        default: m.status="مرفق مرتبط فقط؛ لا يتوفر قارئ لهذه الصيغة"
        }
        return ImportResult(material:m,activities:ReferenceCatalog.activities(material:m) ?? TimingExtractor.extract(pages:pages,material:m))
    }
    static func save(_ project:Project,to url:URL,now:Double) throws {
        var p=project
        ReferenceCatalog.bindEvidence(in:&p)
        for id in p.timers.keys { p.timers[id]=p.timers[id]?.checkpoint(now) }
        p.freeTimer=p.freeTimer.checkpoint(now)
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(p).write(to:url,options:.atomic)
    }
    static func load(_ url:URL) throws -> Project {
        if (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true {
            var project=try PortableProject.load(url)
            ReferenceCatalog.bindEvidence(in:&project)
            return project
        }
        let data=try Data(contentsOf:url)
        guard data.count<30_000_000 else { throw PresenterError.message("ملف الحقيبة كبير بصورة غير صالحة") }
        var project=try JSONDecoder().decode(Project.self,from:data).validated()
        ReferenceCatalog.bindEvidence(in:&project)
        return project
    }
}
