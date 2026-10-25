import Foundation

// Source-driven extraction: explicit activity identity + stated timing, with
// separate totals and stable printed codes. Never sum unlabeled durations.
struct TimingExtractor {
    static func normalized(_ text:String)->String {
        var s=text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of:"[\\u200E\\u200F\\u202A-\\u202E\\u2066-\\u2069]",with:"",options:.regularExpression).replacingOccurrences(of:"ی",with:"ي").replacingOccurrences(of:"ک",with:"ك")
        for (i,c) in "٠١٢٣٤٥٦٧٨٩".enumerated() {s=s.replacingOccurrences(of:String(c),with:String(i))}
        for (i,c) in "۰۱۲۳۴۵۶۷۸۹".enumerated() {s=s.replacingOccurrences(of:String(c),with:String(i))}
        return s.replacingOccurrences(of:"[ـًٌٍَُِّْ]",with:"",options:.regularExpression).replacingOccurrences(of:"أ",with:"ا").replacingOccurrences(of:"إ",with:"ا").replacingOccurrences(of:"آ",with:"ا")
    }
    static func has(_ s:String,_ words:[String])->Bool {words.contains{s.localizedCaseInsensitiveContains($0)}}
    static func code(_ text:String)->String? {
        let s=normalized(text)
        guard let range=s.range(of:"(?<![0-9])[0-9]{1,2}\\s*[-–−/]\\s*[0-9]{1,2}\\s*[-–−/]\\s*[0-9]{1,2}(?![0-9])",options:.regularExpression) else {return nil}
        return String(s[range]).replacingOccurrences(of:"[–−/]",with:"-",options:.regularExpression).replacingOccurrences(of:"\\s",with:"",options:.regularExpression)
    }
    static func identityKey(_ text:String)->String {
        normalized(text).lowercased().replacingOccurrences(of:"[0-9]+(?:[.,][0-9]+)?\\s*(دقيقة|دقائق|دقيقه|minutes?|mins?|ساعة|ساعات|hours?)",with:"",options:.regularExpression).replacingOccurrences(of:"[^\\p{L}\\p{N}]",with:"",options:.regularExpression)
    }
    static func hierarchy(_ text:String,label:String)->String {
        let n=normalized(text)
        let words=["الاولى","الاول","الثانية","الثاني","الثالثة","الثالث","الرابعة","الرابع","الخامسة","الخامس","السادسة","السادس"]
        for (i,w) in words.enumerated() where n.contains(w) {return label+" "+String(i/2+1)}
        if let number=n.range(of:"[0-9]+",options:.regularExpression) {return label+" "+n[number]}
        return text
    }
    static func durations(_ raw:String)->[Double] {
        let s=normalized(raw)
        if has(s,["حوالي","تقريبا","نحو ","اقل من","اكثر من","about","approximately","up to","~"]) {return []}
        let rx=try! NSRegularExpression(pattern:"([0-9]+(?:[.,][0-9]+)?)\\s*(دقيقة|دقائق|دقيقه|دقايق|minutes?|mins?|ساعة|ساعات|ساعه|hours?|hrs?)",options:.caseInsensitive)
        let ns=s as NSString
        return rx.matches(in:s,range:NSRange(location:0,length:ns.length)).compactMap {m in
            let before=ns.substring(to:m.range.location)
            if before.range(of:"[0-9]\\s*(?:[-–−]|الى)\\s*$",options:.regularExpression) != nil {return nil}
            guard let v=Double(ns.substring(with:m.range(at:1)).replacingOccurrences(of:",",with:".")),v>0 else {return nil}
            let seconds=v*(has(ns.substring(with:m.range(at:2)),["ساع","hour","hr"]) ? 3600:60)
            return seconds<=86400 ? seconds:nil
        }
    }
    static func title(_ raw:String)->String {
        var s=raw.precomposedStringWithCompatibilityMapping.replacingOccurrences(of:"[\\u200E\\u200F\\u202A-\\u202E\\u2066-\\u2069]",with:"",options:.regularExpression).replacingOccurrences(of:"ی",with:"ي").replacingOccurrences(of:"ک",with:"ك").trimmingCharacters(in:.whitespacesAndNewlines)
        s=s.replacingOccurrences(of:"[\\p{Nd}]{1,2}\\s*[-–−/]\\s*[\\p{Nd}]{1,2}\\s*[-–−/]\\s*[\\p{Nd}]{1,2}",with:"",options:.regularExpression)
        s=s.replacingOccurrences(of:"(?i)([\\p{Nd}]+(?:[.,][\\p{Nd}]+)?\\s*(دقيقة|دقائق|دقيقه|minutes?|mins?|ساعة|ساعات|hours?))",with:"",options:.regularExpression)
        s=s.replacingOccurrences(of:"^(?:النشاط|نشاط|تمرين|activity|exercise)\\s*",with:"",options:[.regularExpression,.caseInsensitive])
        s=s.replacingOccurrences(of:"(?:مدة النشاط|زمن النشاط|المدة|الزمن)\\s*[:：]?\\s*$",with:"",options:.regularExpression)
        return s.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:"-–:：()[]،|\t")))
    }
    static func extract(pages:[String],material:Material)->[Activity] {
        var result:[Activity]=[];var day="";var session=""
        let group=material.sourceGroup ?? URL(fileURLWithPath:material.path).deletingLastPathComponent().path
        let displayable=["pptx","ppt","pdf"].contains(URL(fileURLWithPath:material.path).pathExtension.lowercased())
        let header=try! NSRegularExpression(pattern:"^(?:النشاط|نشاط|تمرين|activity|exercise|استراحة|break|تامل|reflection)(?:\\s|[:(]|[0-9])",options:.caseInsensitive)
        struct Block {var heading:String;var page:Int;var day:String;var session:String;var lines:[String];var kind:String}
        func emit(_ block:Block) {
            let own=durations(block.heading)
            let explicit=block.lines.filter{has(normalized($0),["مدة النشاط","زمن النشاط","المدة:","الزمن:","duration:","time:"])}
            let eligible=own.isEmpty ? (explicit.isEmpty ? Array(block.lines.prefix(12)):explicit):[block.heading]
            let evidence=eligible.flatMap {line in durations(line).map { seconds in
                Evidence(fileID:material.id,filename:material.name,page:block.page,excerpt:block.heading==line ? line:block.heading+"\n"+line,seconds:seconds)
            }}
            guard let first=evidence.first else {return}
            var name=title(block.heading)
            if name.isEmpty {
                name=block.lines.first(where:{durations($0).isEmpty && !has(normalized($0),["المدة","الزمن"])}) ?? block.heading
            }
            guard !["رقم النشاط","النشاط","الانشطة",""].contains(normalized(name)) else {return}
            var a=Activity(title:String(name.prefix(180)),kind:block.kind,officialCode:code(block.heading) ?? block.lines.compactMap{code($0)}.first,sourceGroup:group,day:block.day,session:block.session,original:first.seconds,duration:first.seconds,evidence:evidence)
            if Set(evidence.map(\.seconds)).count>1 {a.mappingNote="وُجد أكثر من زمن صريح للنشاط. لم تُجمع القيم؛ اختر الزمن الصحيح بعد مراجعة المصادر"}
            if displayable {a.presentationID=material.id;a.startPage=block.page;a.endPage=block.page}
            merge([a],into:&result,materials:[material])
        }
        for (index,text) in pages.enumerated() {
            let lines=text.components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
            var block:Block?
            var table:DelimitedTiming?
            for line in lines {
                if let header=DelimitedTiming(line) {if let b=block {emit(b);block=nil};table=header;continue}
                if let tabular=table?.activity(line,material:material,page:index+1) {merge([tabular],into:&result,materials:[material]);continue}
                let n=normalized(line)
                let isDay=n.range(of:"^(?:اليوم|day)\\s",options:[.regularExpression,.caseInsensitive]) != nil
                let isSession=n.range(of:"^(?:الجلسة|الجلسه|session)\\s",options:[.regularExpression,.caseInsensitive]) != nil
                if isDay || isSession {
                    if let b=block {emit(b);block=nil}
                    if isDay {day=hierarchy(line,label:"اليوم");session=""} else {session=hierarchy(line,label:"الجلسة")}
                    if !durations(line).isEmpty {emit(Block(heading:line,page:index+1,day:day,session:session,lines:[],kind:isDay ? "يوم":"جلسة"))}
                    continue
                }
                let matches=header.firstMatch(in:n,range:NSRange(n.startIndex...,in:n)) != nil
                let table=code(line) != nil && !durations(line).isEmpty
                if matches || table {
                    if let b=block {emit(b)}
                    let kind=has(n,["استراحة","break"]) ? "استراحة":(has(n,["تامل","reflection"]) ? "تأمل":"نشاط")
                    block=Block(heading:line,page:index+1,day:day,session:session,lines:[],kind:kind)
                } else if block != nil {block!.lines.append(line)}
            }
            if let b=block {emit(b)}
        }
        return result
    }
    static func sameIdentity(_ a:Activity,_ b:Activity)->Bool {
        guard a.kind==b.kind,(a.sourceGroup==nil || b.sourceGroup==nil || a.sourceGroup==b.sourceGroup) else {return false}
        if let ac=a.officialCode,let bc=b.officialCode {return ac==bc && (a.day.isEmpty || b.day.isEmpty || a.day==b.day) && (a.session.isEmpty || b.session.isEmpty || a.session==b.session)}
        return identityKey(a.title)==identityKey(b.title) && a.day==b.day && a.session==b.session
    }
    static func merge(_ incoming:[Activity],into existing:inout [Activity],materials:[Material]=[]) {
        for a in incoming {
            if a.catalogID != nil {ReferenceCatalog.reconcile([a],existing:&existing);continue}
            if let i=existing.firstIndex(where:{$0.catalogID==nil && sameIdentity($0,a)}) {
                let new=a.evidence.filter{e in !existing[i].evidence.contains(where:{$0.fileID==e.fileID && $0.page==e.page && $0.excerpt==e.excerpt && $0.seconds==e.seconds})}
                if !new.isEmpty {existing[i].evidence+=new}
                if existing[i].approved {continue}
                if existing[i].day.isEmpty {existing[i].day=a.day};if existing[i].session.isEmpty {existing[i].session=a.session}
                if existing[i].presentationID==nil,a.presentationID != nil {existing[i].presentationID=a.presentationID;existing[i].startPage=a.startPage;existing[i].endPage=a.endPage;existing[i].approved=false}
                else if existing[i].presentationID==a.presentationID,let end=existing[i].endPage,let next=a.startPage,next==end+1 {existing[i].endPage=a.endPage}
                TimeSourcePolicy.propose(&existing[i],materials:materials)
            } else {var proposed=a;TimeSourcePolicy.propose(&proposed,materials:materials);existing.append(proposed)}
        }
    }
}
