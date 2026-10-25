import Foundation
import PDFKit

struct GuideRow {
    var text:String;var rect:CGRect;let normalized:String
    init(text:String,rect:CGRect) {self.text=text;self.rect=rect;self.normalized=TimingExtractor.normalized(text)}
}
struct GuideAgenda {var code:String;var seconds:Double;var title:String;var page:Int;var location:String="جدول الجلسة · صف النشاط"}
struct GuideResult {var activities:[Activity];var agendaCount:Int;var cardCount:Int;var issues:[String]}
struct GuideReader {
    static func rows(_ page:PDFPage)->[GuideRow] {
        (page.selection(for:page.bounds(for:.cropBox))?.selectionsByLine() ?? []).compactMap {selection in
            guard let t=selection.string,!t.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return nil}
            return GuideRow(text:t.precomposedStringWithCompatibilityMapping,rect:selection.bounds(for:page))
        }.sorted {abs($0.rect.midY-$1.rect.midY)>4 ? $0.rect.midY>$1.rect.midY:$0.rect.minX>$1.rect.minX}
    }
    static func agenda(_ rows:[GuideRow],page:Int)->[GuideAgenda] {
        guard let codeLabel=rows.first(where:{$0.normalized.contains("رقم النشاط")}),let timeLabel=rows.first(where:{$0.normalized.contains("المدة الزمنية")}) else {return []}
        let codes=rows.filter{TimingExtractor.code($0.text) != nil && abs($0.rect.midX-codeLabel.rect.midX)<65 && $0.rect.midY<codeLabel.rect.minY}
        return codes.compactMap {row in
            let others=codes.filter{$0.rect != row.rect}
            let above=others.filter{$0.rect.midY>row.rect.midY}.map(\.rect.midY).min() ?? codeLabel.rect.minY
            let below=others.filter{$0.rect.midY<row.rect.midY}.map(\.rect.midY).max() ?? (row.rect.midY-65)
            let cell=rows.filter{abs($0.rect.midX-timeLabel.rect.midX)<70 && $0.rect.midY<(above+row.rect.midY)/2 && $0.rect.midY>(below+row.rect.midY)/2}
            let durations=TimingExtractor.durations(cell.map(\.text).joined(separator:" "))
            guard let seconds=durations.first,Set(durations).count==1 else {return nil}
            let names=rows.filter{$0.rect.midX>timeLabel.rect.maxX+40 && $0.rect.midX<codeLabel.rect.minX-20 && abs($0.rect.midY-row.rect.midY)<16}
            let title=names.max(by:{$0.rect.midX<$1.rect.midX})?.text ?? ""
            return GuideAgenda(code:TimingExtractor.code(row.text)!,seconds:seconds,title:title,page:page)
        }
    }
    static func printedPages(_ pdf:PDFDocument)->[Int:Int] {
        var candidates:[Int:[Int]]=[:]
        for i in 0..<pdf.pageCount {
            let page=pdf.page(at:i)!,box=page.bounds(for:.cropBox)
            let area=CGRect(x:box.minX,y:box.minY,width:box.width*0.13,height:box.height*0.12)
            let text=TimingExtractor.normalized(page.selection(for:area)?.string ?? "")
            let rx=try! NSRegularExpression(pattern:"(?<![0-9])[0-9]{1,3}(?![0-9])")
            let ns=text as NSString;let numbers=rx.matches(in:text,range:NSRange(location:0,length:ns.length)).compactMap{Int(ns.substring(with:$0.range))}
            let distinct=Array(Set(numbers))
            if distinct.count==1 {candidates[distinct[0],default:[]].append(i+1)}
        }
        return candidates.compactMapValues{$0.count==1 ? $0.first:nil}
    }
    static func slideRange(_ rows:[GuideRow])->ClosedRange<Int>? {
        for row in rows where row.normalized.contains("شرائح") || row.normalized.contains("شريح") {
            let n=row.normalized
            let rx=try! NSRegularExpression(pattern:"[0-9]{1,3}")
            let ns=n as NSString;let nums=rx.matches(in:n,range:NSRange(location:0,length:ns.length)).compactMap{Int(ns.substring(with:$0.range))}
            if nums.count==1,nums[0]>0 {return nums[0]...nums[0]}
            if nums.count==2,let lo=nums.min(),let hi=nums.max(),lo>0,hi-lo<100 {return lo...hi}
        }
        return nil
    }
    static func cardTimes(_ rows:[GuideRow],page:Int,agenda:[GuideAgenda])->[GuideAgenda] {
        guard rows.contains(where:{$0.normalized.contains("نوع النشاط")}),let heading=rows.first(where:{TimingExtractor.code($0.text) != nil && ($0.normalized.hasPrefix("النشاط") || $0.normalized.hasPrefix("ارشادات النشاط"))}),let raw=TimingExtractor.code(heading.text),let label=rows.first(where:{$0.normalized.contains("المدة الزمنية") && $0.rect.midY<heading.rect.midY}) else {return []}
        let reverse=raw.split(separator:"-").reversed().joined(separator:"-")
        let exact=agenda.contains{$0.code==raw},flipped=agenda.contains{$0.code==reverse}
        // Ambiguous orientation is not assigned to a different activity.
        if exact && flipped && raw != reverse {return []}
        let code=flipped && !exact ? reverse:raw
        let seconds=rows.filter{$0.rect.midY<label.rect.minY && $0.rect.midY>label.rect.minY-145 && abs($0.rect.midX-label.rect.midX)<85}.flatMap{TimingExtractor.durations($0.text)}
        return Array(Set(seconds)).sorted().map{GuideAgenda(code:code,seconds:$0,title:TimingExtractor.title(heading.text),page:page,location:"بطاقة النشاط · حقل المدة")}
    }
    static func sessionTotal(_ rows:[GuideRow])->Double? {
        guard let label=rows.first(where:{$0.normalized.contains("اجمالي المدة الزمنية")}) else {return nil}
        let values=rows.filter{abs($0.rect.midY-label.rect.midY)<17 && $0.rect.midX<200}.flatMap{TimingExtractor.durations($0.text)}
        return Set(values).count==1 ? values.first:nil
    }
    static func sessionKey(_ rows:[GuideAgenda])->String {Set(rows.map(\.code)).sorted().joined(separator:"/")}
    static func read(trainer:Material,slides:Material,learner:Material?=nil)->GuideResult {
        guard let guide=PDFDocument(url:URL(fileURLWithPath:trainer.path)),let deck=PDFDocument(url:URL(fileURLWithPath:slides.path)) else {return GuideResult(activities:[],agendaCount:0,cardCount:0,issues:["تعذر فتح العرض أو دليل المدرب"])}
        let pageRows=(0..<guide.pageCount).map{rows(guide.page(at:$0)!)}
        let printed=printedPages(deck)
        var expectations:[GuideAgenda]=[];var active:[GuideAgenda]=[];var activities:[Activity]=[];var issues:[String]=[];var cards=0;var reverseHeadings:Bool?=nil
        var sessionSources:[String:[Evidence]]=[:]
        var learnerAgenda:[GuideAgenda]=[]
        var sessionAgendas:[String:[GuideAgenda]]=[:]
        for (index,rows) in pageRows.enumerated() {
            let agenda=Self.agenda(rows,page:index+1)
            if !agenda.isEmpty {
                active=agenda;expectations += agenda
                if let seconds=sessionTotal(rows) {
                    let key=sessionKey(agenda);sessionAgendas[key]=agenda
                    sessionSources[key,default:[]].append(Evidence(fileID:trainer.id,filename:trainer.name,page:index+1,excerpt:"إجمالي المدة الزمنية الصريح في دليل المدرب",seconds:seconds,timeKind:"جلسة",location:"جدول الجلسة · خانة الإجمالي"))
                }
                if let total=rows.first(where:{$0.normalized.contains("اجمالي المدة الزمنية")}) {
                    let values=rows.filter{abs($0.rect.midY-total.rect.midY)<17 && $0.rect.midX<200}.flatMap{TimingExtractor.durations($0.text)}
                    if let stated=values.first,Set(values).count==1,abs(agenda.reduce(0){$0+$1.seconds}-stated)>1 {
                        issues.append("صفحة \(index+1): مجموع مدد صفوف الجلسة المقروءة \(Int(agenda.reduce(0){$0+$1.seconds}/60)) دقيقة، والإجمالي المطبوع \(Int(stated/60)) دقيقة؛ راجع الجدول")
                    }
                }
            }
            let height=guide.page(at:index)!.bounds(for:.cropBox).height
            guard let heading=rows.first(where:{row in
                row.rect.midY>height*0.6 && TimingExtractor.code(row.text) != nil && (row.normalized.hasPrefix("النشاط") || row.normalized.hasPrefix("ارشادات النشاط"))
            }),let rawCode=TimingExtractor.code(heading.text) else {continue}
            let fieldCard=rows.contains{$0.normalized.contains("نوع النشاط")} && rows.contains{$0.normalized.contains("المدة الزمنية")}
            let evaluation=rows.contains{$0.normalized.contains("نموذج التقييم")} && rows.filter{TimingExtractor.code($0.text) != nil}.count==1
            guard fieldCard || evaluation else {continue}
            cards += 1
            let reverse=rawCode.split(separator:"-").reversed().joined(separator:"-")
            let exact=active.first(where:{$0.code==rawCode}),reversed=active.first(where:{$0.code==reverse})
            if reverseHeadings==nil,rawCode != reverse {
                if exact==nil && reversed != nil {reverseHeadings=true}
                else if exact != nil && reversed==nil {reverseHeadings=false}
            }
            let expected=reverseHeadings==true ? (reversed ?? exact):(exact ?? reversed)
            let code=expected?.code ?? (reverseHeadings==true ? reverse:rawCode)
            let label=rows.first(where:{$0.normalized.contains("المدة الزمنية") && $0.rect.midY<heading.rect.midY})
            let labelY=label?.rect.minY ?? heading.rect.minY-150
            let labelX=label?.rect.midX ?? 120
            let values=rows.filter{$0.rect.midY<labelY && $0.rect.midY>labelY-145 && abs($0.rect.midX-labelX)<85}
            let durationValues=label==nil ? []:values.flatMap{TimingExtractor.durations($0.text)}
            guard let seconds=durationValues.first ?? expected?.seconds else {issues.append("صفحة \(index+1): مدة غير مؤكدة للنشاط \(code)");continue}
            let titleRows=rows.filter{$0.rect.midY<heading.rect.minY && $0.rect.midY>(label?.rect.maxY ?? labelY)+5 && $0.rect.midX>height*0.25 && !$0.normalized.contains("سجل التامل") && !$0.normalized.contains("كيف ")}
            var title=TimingExtractor.title(heading.text.replacingOccurrences(of:"^(?:إرشادات|ارشادات)\\s*",with:"",options:.regularExpression))
            let continuation=titleRows.filter{label != nil || $0.rect.height>heading.rect.height*0.65}.prefix(label==nil ? 1:Int.max).map(\.text).joined(separator:" ")
            title=([title,continuation].filter{!$0.isEmpty}).joined(separator:" ")
            if title.isEmpty {title=expected?.title ?? "نشاط "+code}
            let components=code.split(separator:"-")
            let day=components.count==3 ? "اليوم "+components[2]:"",session=components.count==3 ? "الجلسة "+components[1]:""
            let evidence=Evidence(fileID:trainer.id,filename:trainer.name,page:index+1,excerpt:heading.text+"\n"+title+"\nالمدة الزمنية: "+values.map(\.text).joined(separator:" "),seconds:seconds,timeKind:"نشاط",location:"بطاقة النشاط · حقل المدة")
            var a=Activity(id:"guide:"+TrainingLibrary.key((trainer.sourceGroup ?? trainer.path)+"/"+code),title:title,kind:"نشاط",officialCode:code,sourceGroup:trainer.sourceGroup,day:day,session:session,original:seconds,duration:seconds,evidence:Array(Set(durationValues)).sorted().map {value in var e=evidence;e.id=UUID().uuidString;e.seconds=value;return e})
            if Set(durationValues).count>1 {a.mappingNote="تعارض داخل بطاقة النشاط؛ جميع القيم محفوظة للمراجعة"}
            if durationValues.isEmpty {a.mappingNote="المدة من جدول الجلسة؛ بطاقة النشاط في صفحة \(index+1) لا تتضمن حقل مدة مقروءًا"}
            if let expected=expected {
                a.evidence.append(Evidence(fileID:trainer.id,filename:trainer.name,page:expected.page,excerpt:"جدول الجلسة · "+expected.code+" · "+expected.title+" · \(expected.seconds/60) دقيقة",seconds:expected.seconds,timeKind:"نشاط",location:"جدول الجلسة · صف النشاط"))
                if expected.seconds != seconds {a.mappingNote="مدة بطاقة النشاط تختلف عن جدول الجلسة؛ راجع المصدرين"}
            } else {a.mappingNote="لم تُطابق البطاقة بصف مستقل في جدول الجلسة"}
            if let range=slideRange(rows),let start=printed[range.lowerBound],let end=printed[range.upperBound],start<=end {
                a.presentationID=slides.id;a.startPage=start;a.endPage=end
            } else {a.mappingNote=(a.mappingNote.map{$0+"؛ "} ?? "")+"ربط الشرائح يحتاج مراجعة؛ لم يُفترض ترتيب صفحات الملف"}
            if let i=activities.firstIndex(where:{$0.officialCode==code}) {
                activities[i].evidence += a.evidence;activities[i].mappingNote="تكرر رقم النشاط في بطاقات متعددة؛ راجع المدة والنطاق قبل الاعتماد"
            } else {activities.append(a)}
        }
        if let learner=learner,let document=PDFDocument(url:URL(fileURLWithPath:learner.path)) {
            var comparison:[GuideAgenda]=[]
            for page in 0..<document.pageCount {
                let rows=Self.rows(document.page(at:page)!),agenda=Self.agenda(rows,page:page+1)
                comparison += agenda
                comparison += cardTimes(rows,page:page+1,agenda:comparison)
                if !agenda.isEmpty,let seconds=sessionTotal(rows) {
                    let key=sessionKey(agenda)
                    sessionAgendas[key]=sessionAgendas[key] ?? agenda
                    sessionSources[key,default:[]].append(Evidence(fileID:learner.id,filename:learner.name,page:page+1,excerpt:"إجمالي المدة الزمنية الصريح في دليل المتدرب",seconds:seconds,timeKind:"جلسة",location:"جدول الجلسة · خانة الإجمالي"))
                }
            }
            learnerAgenda=comparison
        }
        let expectedCodes=Set(expectations.map(\.code));let found=Set(activities.compactMap(\.officialCode))
        for code in expectedCodes.subtracting(found).sorted() {
            guard let row=expectations.first(where:{$0.code==code}) else {continue}
            let parts=code.split(separator:"-")
            let evidence=Evidence(fileID:trainer.id,filename:trainer.name,page:row.page,excerpt:"جدول الجلسة · "+row.code+" · "+row.title+" · \(row.seconds/60) دقيقة",seconds:row.seconds,timeKind:"نشاط",location:"جدول الجلسة · صف النشاط")
            activities.append(Activity(id:"guide:"+TrainingLibrary.key((trainer.sourceGroup ?? trainer.path)+"/"+code),title:row.title.isEmpty ? "نشاط "+code:row.title,kind:"نشاط",officialCode:code,mappingNote:"ورد النشاط في جدول الجلسة، ولم تُقرأ بطاقة مستقلة مطابقة؛ راجع الاسم والمدة والربط",sourceGroup:trainer.sourceGroup,day:parts.count==3 ? "اليوم "+parts[2]:"",session:parts.count==3 ? "الجلسة "+parts[1]:"",original:row.seconds,duration:row.seconds,evidence:[evidence]))
            issues.append("نشاط أُدرج من الجدول ويحتاج مراجعة بطاقته: "+code)
        }
        for row in learnerAgenda where !activities.contains(where:{$0.officialCode==row.code}) {
            let parts=row.code.split(separator:"-")
            activities.append(Activity(id:"guide:"+TrainingLibrary.key((trainer.sourceGroup ?? trainer.path)+"/"+row.code),title:row.title.isEmpty ? "نشاط "+row.code:row.title,kind:"نشاط",officialCode:row.code,mappingNote:"ورد الزمن في دليل المتدرب فقط؛ راجع البطاقة والربط",sourceGroup:trainer.sourceGroup,day:parts.count==3 ? "اليوم "+parts[2]:"",session:parts.count==3 ? "الجلسة "+parts[1]:"",original:row.seconds,duration:row.seconds))
        }
        for i in activities.indices {
            for row in learnerAgenda where row.code==activities[i].officialCode {
                activities[i].evidence.append(Evidence(fileID:learner!.id,filename:learner!.name,page:row.page,excerpt:"دليل المتدرب · "+row.location+" · "+row.code+" · \(row.seconds/60) دقيقة",seconds:row.seconds,timeKind:"نشاط",location:row.location))
            }
        }
        activities.sort {a,b in
            let ad=Int(a.day.components(separatedBy:" ").last ?? "") ?? 0,bd=Int(b.day.components(separatedBy:" ").last ?? "") ?? 0
            let asn=Int(a.session.components(separatedBy:" ").last ?? "") ?? 0,bsn=Int(b.session.components(separatedBy:" ").last ?? "") ?? 0
            let ac=Int(a.officialCode?.components(separatedBy:"-").first ?? "") ?? 0,bc=Int(b.officialCode?.components(separatedBy:"-").first ?? "") ?? 0
            return (ad,asn,ac)<(bd,bsn,bc)
        }
        if expectedCodes.isEmpty {issues.append("لم تُقرأ جداول الأنشطة؛ تحتاج الحقيبة مراجعة بنيوية")}
        // Secondary anchors are explicit proposals, never automatic approvals.
        let slideRows=(0..<deck.pageCount).map{rows(deck.page(at:$0)!)}
        for i in activities.indices where activities[i].presentationID==nil {
            let activity=activities[i],code=activity.officialCode ?? "",reverse=code.split(separator:"-").reversed().joined(separator:"-")
            let titleKey=TimingExtractor.identityKey(activity.title)
            let ambiguousCode=code != reverse && activities.contains{$0.id != activity.id && $0.officialCode==reverse}
            let byCode=slideRows.enumerated().filter {page in
                page.element.contains{row in
                    guard row.rect.midY>deck.page(at:page.offset)!.bounds(for:.cropBox).height*0.55,row.normalized.contains("نشاط"),let found=TimingExtractor.code(row.text),[code,reverse].contains(found) else {return false}
                    return !ambiguousCode || (titleKey.count>=10 && TimingExtractor.identityKey(page.element.map(\.text).joined(separator:" ")).contains(titleKey))
                }
            }.map{$0.offset+1}
            var match:Int?=byCode.count==1 ? byCode.first:nil
            var basis="رقم النشاط"
            if match==nil,titleKey.count>=10,!activities.contains(where:{$0.id != activity.id && TimingExtractor.identityKey($0.title)==titleKey}) {
                let byTitle=slideRows.enumerated().filter {page in
                    let height=deck.page(at:page.offset)!.bounds(for:.cropBox).height
                    let top=page.element.filter{$0.rect.midY>height*0.6 && !$0.normalized.contains("المعهد") && !$0.normalized.contains("سجل التامل")}
                    let maxHeight=top.map(\.rect.height).max() ?? 0
                    let heading=top.filter{$0.rect.height>=maxHeight*0.8}.map(\.text).joined(separator:" ")
                    return TimingExtractor.identityKey(TimingExtractor.title(heading))==titleKey
                }.map{$0.offset+1}
                if byTitle.count==1 {match=byTitle.first;basis="العنوان المطابق والفريد"}
            }
            if let page=match {
                activities[i].presentationID=slides.id;activities[i].startPage=page;activities[i].endPage=page
                let note="ربط مقترح بمطابقة "+basis+" في صفحة العرض \(page)؛ راجع نقطة البداية وحدّد نهاية النطاق قبل الاعتماد"
                activities[i].mappingNote=(activities[i].mappingNote.map{$0+"؛ "} ?? "")+note
            }
        }
        for i in activities.indices {
            let a=activities[i]
            if let s=a.startPage,let e=a.endPage,activities.contains(where:{$0.id != a.id && $0.startPage != nil && $0.endPage != nil && s<=$0.endPage! && e >= $0.startPage!}) {
                activities[i].mappingNote=(activities[i].mappingNote.map{$0+"؛ "} ?? "")+"يتداخل نطاق الشرائح مع نشاط آخر؛ حدّد نقطة الانتقال يدويًا"
            }
        }
        var breaks:[Activity]=[]
        for (index,rows) in pageRows.enumerated() {
            guard rows.contains(where:{$0.normalized.contains("رقم الجلسة")}),let dayRow=rows.first(where:{$0.normalized.hasPrefix("اليوم التدريبي")}) else {continue}
            let day=TimingExtractor.hierarchy(dayRow.text,label:"اليوم")
            let width=guide.page(at:index)!.bounds(for:.cropBox).width
            let sessions=rows.filter{$0.rect.midX>width*0.7 && $0.rect.midY>80 && ["1","2","3","4"].contains($0.normalized.trimmingCharacters(in:.whitespaces))}
            guard sessions.count==4 else {continue}
            for row in rows where row.normalized.contains("استراحة") {
                guard let seconds=TimingExtractor.durations(row.text).first,let before=sessions.filter({$0.rect.midY>row.rect.midY}).min(by:{$0.rect.midY<$1.rect.midY}) else {continue}
                let session="الجلسة "+before.normalized.trimmingCharacters(in:.whitespaces)
                let id="break:"+TrainingLibrary.key((trainer.sourceGroup ?? trainer.path)+day+session)
                guard !breaks.contains(where:{$0.id==id}) else {continue}
                let evidence=Evidence(fileID:trainer.id,filename:trainer.name,page:index+1,excerpt:day+" · بعد "+session+" · "+row.text,seconds:seconds,timeKind:"استراحة",location:"الجدول اليومي · استراحة")
                breaks.append(Activity(id:id,title:"استراحة",kind:"استراحة",mappingNote:"موضع الاستراحة من الجدول اليومي؛ راجعه قبل الاعتماد",sourceGroup:trainer.sourceGroup,day:day,session:session,original:seconds,duration:seconds,evidence:[evidence]))
            }
        }
        for rest in breaks {
            if let position=activities.lastIndex(where:{$0.day==rest.day && $0.session==rest.session}) {activities.insert(rest,at:position+1)}
            else {activities.append(rest)}
        }
        // Compare only agendas with the exact same activity-code set. A sum is
        // auxiliary session evidence, never a replacement for any activity card.
        for (index,rows) in slideRows.enumerated() {
            let agenda=Self.agenda(rows,page:index+1),key=sessionKey(agenda)
            if !agenda.isEmpty,sessionSources[key] != nil {
                sessionSources[key,default:[]].append(Evidence(fileID:slides.id,filename:slides.name,page:index+1,excerpt:"مجموع صفوف جلسة العرض المطابقة بأرقام الأنشطة؛ قيمة مساعدة",seconds:agenda.reduce(0){$0+$1.seconds},timeKind:"جلسة",location:"جدول العرض · مجموع صفوف الأنشطة"))
            }
        }
        for key in sessionSources.keys.sorted() {
            let evidence=sessionSources[key]!,parts=(sessionAgendas[key]?.first?.code ?? "").split(separator:"-")
            let day=parts.count==3 ? "اليوم "+parts[2]:"",session=parts.count==3 ? "الجلسة "+parts[1]:""
            var total=Activity(id:"session:"+TrainingLibrary.key((trainer.sourceGroup ?? trainer.path)+"/"+key),title:"إجمالي الجلسة — منفصل عن الأنشطة",kind:"جلسة",sourceGroup:trainer.sourceGroup,day:day,session:session,original:evidence[0].seconds,duration:evidence[0].seconds,evidence:evidence)
            let assessment=TimeSourcePolicy.assess(total,materials:[trainer,slides]+(learner.map{[$0]} ?? []))
            if assessment.requiresReview {total.mappingNote=assessment.status+"؛ لم توزّع الفروق على الأنشطة";issues.append(day+" · "+session+" · "+assessment.status)}
            activities.append(total)
        }
        for i in activities.indices {TimeSourcePolicy.propose(&activities[i],materials:[trainer,slides]+(learner.map{[$0]} ?? []))}
        return GuideResult(activities:activities,agendaCount:expectedCodes.count,cardCount:cards,issues:issues)
    }
}
