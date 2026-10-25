import SwiftUI
import PDFKit

struct LibraryTimeConflict:Identifiable {
    var id:String {bag.id+"/"+activity.id}
    let bag:LibraryBag
    let activity:Activity
    let materials:[Material]
    var assessment:TimeAssessment {TimeSourcePolicy.assess(activity,materials:materials)}
    var context:String {bag.track+" › "+bag.domain+" › "+bag.title}
}
@MainActor extension PresenterStore {
    func loadTimeConflicts() {
        var result:[LibraryTimeConflict]=[],failures:[String]=[]
        for bag in library.bags {
            do {
                let value=project.libraryBagID==bag.id ? project:try DocumentReader.load(TrainingLibrary.projectURL(bag.id))
                for activity in value.activities {
                    let assessment=TimeSourcePolicy.assess(activity,materials:value.materials)
                    if assessment.requiresReview {result.append(LibraryTimeConflict(bag:bag,activity:activity,materials:value.materials))}
                }
            } catch {failures.append(bag.displayTitle)}
        }
        timeConflicts=result;timeConflictReadError=failures.isEmpty ? nil:"تعذر قراءة الحقائب: "+failures.joined(separator:"، ")
    }
    func openTimeConflict(_ item:LibraryTimeConflict) {
        if project.libraryBagID != item.bag.id {
            // Opening a bag is explicit. Merely listing conflicts or previewing
            // a source never replaces the current bag or touches its timers.
            guard preserveBeforeReplacing() else {return}
            do {
                var target=try DocumentReader.load(TrainingLibrary.projectURL(item.bag.id))
                guard target.activities.contains(where:{$0.id==item.activity.id}) else {error="تغيّرت قائمة الأنشطة؛ أعد تحديث الحالات";return}
                for i in target.materials.indices {
                    if let file=item.bag.files.first(where:{$0.role==target.materials[i].libraryRole}) {
                        let path=library.url(file).path;target.materials[i].path=path;target.materials[i].renderedPath=path
                    }
                }
                checkpoint();projectEpoch=UUID();privatePreview=false;project=target;projectURL=TrainingLibrary.projectURL(item.bag.id)
                freeMode=false;proposed=0;notice=nil;loadDisplay();dirty=false
            } catch {self.error="تعذر فتح موضع المراجعة: "+error.localizedDescription;return}
        }
        selectedReview=item.activity.id;timeConflictsVisible=false;review=true
    }
}
struct ConflictSource:Identifiable {
    var id:String {evidence.id}
    let evidence:Evidence
    let material:Material?
}
struct ConflictSourcePreview:View {
    let source:ConflictSource
    @Environment(\.dismiss) var dismiss
    @State private var page=0
    @State private var document:PDFDocument?
    var body:some View {
        VStack {
            HStack {Text(source.evidence.filename).lineLimit(2);Spacer();Button("إغلاق"){dismiss()}.accessibilityIdentifier("closeConflictSource")}
            HStack {
                Button("السابقة"){page=max(0,page-1)}
                Text("\(page+1) / \(document?.pageCount ?? 0)").monospacedDigit()
                Button("التالية"){page=min(max(0,(document?.pageCount ?? 1)-1),page+1)}
                Spacer();Text("معاينة خاصة — الحقيبة والمؤقت والعرض المشترك ثابتة").font(.caption)
            }
            if let document=document {PDFCanvas(document:document,page:page){page=$0}}
            else {Text("المصدر مفقود أو تالف أو غير قابل للعرض").frame(maxWidth:.infinity,maxHeight:.infinity)}
        }.padding(16).frame(width:850,height:650).presenterTheme().environment(\.layoutDirection,.rightToLeft)
            .onAppear {
                if let path=source.material?.renderedPath ?? source.material?.path {document=PDFDocument(url:URL(fileURLWithPath:path))}
                page=max(0,min(source.evidence.page-1,max(0,(document?.pageCount ?? 1)-1)))
            }
    }
}
struct TimeConflictBrowser:View {
    @ObservedObject var store:PresenterStore
    @State private var source:ConflictSource?
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("الحالات غير المحسومة في المكتبة: \(store.timeConflicts.count)").font(.headline)
                Spacer();Button("تحديث الحالات",action:store.loadTimeConflicts).accessibilityIdentifier("refreshTimeConflicts")
                Button("أنشطة الحقيبة الحالية"){store.timeConflictsVisible=false}
            }
            Text("هذه القائمة لا تعدّل مدة أو اعتمادًا. فتح المصدر معاينة خاصة؛ «مراجعة هذا العنصر» تفتح حقيبته وتحدد صفه مباشرة.").font(.caption).foregroundColor(.secondary)
            if let error=store.timeConflictReadError {Text(error).foregroundColor(.orange)}
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    ForEach(store.timeConflicts) {item in
                        TimeConflictCard(store:store,item:item){e in source=ConflictSource(evidence:e,material:item.materials.first{$0.id==e.fileID})}
                    }
                    if store.timeConflicts.isEmpty {Text("لا توجد حالات غير محسومة في المشاريع المقروءة").padding()}
                }
            }
        }.sheet(item:$source){ConflictSourcePreview(source:$0)}
    }
}
struct TimeConflictCard:View {
    @ObservedObject var store:PresenterStore
    let item:LibraryTimeConflict
    let preview:(Evidence)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(item.context).font(.caption.bold()).textSelection(.enabled)
            Text(item.activity.day+" · "+item.activity.session+" · "+item.activity.kind+" · "+item.activity.displayTitle).font(.headline)
            HStack {
                Text(item.assessment.status).foregroundColor(.orange)
                Text(item.activity.approved ? "معتمد — القيمة السابقة محفوظة":"غير معتمد — يحتاج قرارك")
                Spacer()
                Button("مراجعة هذا العنصر"){store.openTimeConflict(item)}.accessibilityIdentifier("openTimeConflict:"+item.id)
            }.font(.callout)
            Text(item.activity.kind=="جلسة" ? "إجمالي جلسة مستقل؛ لا يُوزّع على الأنشطة":"القيم التالية تخص زمن "+item.activity.kind+"؛ إجماليات الجلسة منفصلة").font(.caption).foregroundColor(.secondary)
            sourceGroup("trainer",label:"دليل المدرب")
            sourceGroup("learner",label:"دليل المتدرب")
            if !item.assessment.auxiliary.isEmpty {
                ForEach(item.assessment.auxiliary) {e in sourceLine(e,label:"مصدر مساعد")}
            }
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.045)).cornerRadius(8)
    }
    func sourceGroup(_ role:String,label:String)->some View {
        let values=item.assessment.primary.filter{TimeSourcePolicy.role($0,materials:item.materials)==role}
        return VStack(alignment:.leading,spacing:4) {
            if values.isEmpty {Text(label+": لا توجد قيمة موثقة لهذا العنصر").font(.caption).foregroundColor(.secondary)}
            ForEach(values) {e in sourceLine(e,label:label)}
        }
    }
    func sourceLine(_ e:Evidence,label:String)->some View {
        let minutes=String(format:"%.1f",e.seconds/60)
        let detail="\(label) · \(minutes) د · \(e.filename) · ص \(e.page) · \(e.location ?? e.excerpt)"
        return HStack(alignment:.top) {
            Text(detail).font(.caption).textSelection(.enabled)
            Spacer(minLength:8)
            Button("فتح المصدر"){preview(e)}.trainerHelp("فتح الصفحة الداعمة دون تغيير الحقيبة الحالية").accessibilityIdentifier("conflictSource:"+item.id+":"+e.id)
        }
    }
}
