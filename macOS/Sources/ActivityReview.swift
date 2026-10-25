import SwiftUI

struct ReviewGroup:Identifiable {var id:String;var title:String;var items:[Activity]}
struct ReviewView:View {
    @ObservedObject private var appearance=UIAppearance.shared
    @ObservedObject var store:PresenterStore
    @Environment(\.dismiss) var dismiss
    @State private var search=""
    @State private var onlyReview=false
    var filtered:[Activity] {
        store.project.activities.filter {a in
            (!onlyReview || a.needsReview) && (search.isEmpty || TimingExtractor.normalized(a.displayTitle+" "+a.day+" "+a.session).localizedCaseInsensitiveContains(TimingExtractor.normalized(search)))
        }
    }
    var groups:[ReviewGroup] {
        var groups:[ReviewGroup]=[]
        for a in filtered {
            let title=(a.day.isEmpty ? "اليوم غير محدد":a.day)+" · "+(a.session.isEmpty ? "الجلسة غير محددة":a.session)
            let key=(a.sourceGroup ?? a.catalogID?.components(separatedBy:"-d").first ?? "")+title
            if let i=groups.firstIndex(where:{$0.id==key}) {groups[i].items.append(a)}
            else {groups.append(ReviewGroup(id:key,title:title,items:[a]))}
        }
        return groups
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("مراجعة الأنشطة وبدء التدريب").font(.title2.bold());Spacer()
                Text("المعتمد \(store.project.activities.filter{!$0.needsReview}.count) / \(store.project.activities.count)").font(.caption)
                Button("تم") {dismiss()}.keyboardShortcut(.defaultAction)
            }
            TrainerHelpBar()
            HStack {
                Button("تعارضات المكتبة"){store.loadTimeConflicts();store.timeConflictsVisible=true}.accessibilityIdentifier("openTimeConflicts").trainerHelp("عرض الحالات غير المحسومة في جميع الحقائب")
                Text("المدد والاعتمادات لا تتغير عند عرض الحالات").font(.caption).foregroundColor(.secondary)
            }
            if store.timeConflictsVisible {TimeConflictBrowser(store:store)} else {
            HStack(spacing:12) {
                TextField("بحث بالرقم أو الاسم أو الجلسة",text:$search).textFieldStyle(.roundedBorder).accessibilityIdentifier("reviewSearch")
                Toggle("بحاجة للمراجعة فقط",isOn:$onlyReview).fixedSize().accessibilityIdentifier("reviewOnly")
                Button("اعتماد القيم غير المتعارضة") {store.approveMap()}
                Button("إضافة نشاط",action:store.addActivity)
                Menu("مصادر وتحليل") {
                    Button("مزامنة المؤقت السابق",action:store.synchronizeReference).disabled(store.busy)
                }.fixedSize()
            }
            Text("النتائج مقترحة حتى اعتمادك. إجماليات الجلسات منفصلة؛ الحالات المتعارضة وملاحظات الربط تحتاج مراجعة فردية. اختر الصف، وراجع المصدر، ثم اعتمد وابدأ من هنا.").font(.caption).foregroundColor(.secondary)
            if let note=store.material?.versionNote {Text(note).font(.caption).foregroundColor(.orange)}
            HStack(alignment:.top,spacing:0) {
                VStack(spacing:0) {
                    rowHeading
                    ScrollViewReader {proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:3) {
                            ForEach(groups) {group in
                                Text(group.title).font(.system(size:12,weight:.semibold)).padding(.vertical,9).padding(.horizontal,8).frame(maxWidth:.infinity,alignment:.leading).background(appearance.theme.accent.opacity(0.08))
                                ForEach(group.items) {a in
                                    Button {store.selectedReview=a.id} label:{
                                        HStack(spacing:6) {
                                            Text(a.officialCode ?? "—").frame(width:60).environment(\.layoutDirection,.leftToRight)
                                            Text(a.title).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                            Text(String(format:"%.1f",a.duration/60)).frame(width:48).monospacedDigit()
                                            Text(a.startPage.map{String($0)+"–"+String(a.endPage ?? $0)} ?? "يدوي").frame(width:58).font(.caption)
                                            Text(a.approved ? "معتمد":(TimeSourcePolicy.assess(a,materials:store.project.materials).requiresReview ? "راجع":"مقترح")).frame(width:54).foregroundColor(a.approved ? appearance.theme.accent:.orange)
                                        }.font(.system(size:12)).padding(.horizontal,6).padding(.vertical,8).frame(maxWidth:.infinity,alignment:.leading)
                                            .background(store.selectedReview==a.id ? appearance.theme.accent.opacity(0.15):Color.primary.opacity(0.025)).cornerRadius(5)
                                    }.buttonStyle(.plain).id(a.id).accessibilityIdentifier("reviewRow:"+a.id)
                                }
                            }
                            if groups.isEmpty {Text("لا توجد أنشطة مطابقة للمرشح").foregroundColor(.secondary).padding()}
                        }
                    }
                    .onChange(of:store.selectedReview){id in if let id=id {proxy.scrollTo(id,anchor:.center)}}
                    .onAppear {if let id=store.selectedReview {DispatchQueue.main.async {proxy.scrollTo(id,anchor:.center)}}}
                    }
                }.frame(width:550)
                Divider()
                if let id=store.selectedReview,store.project.activities.contains(where:{$0.id==id}) {
                    ActivityEditor(store:store,activityID:id).id(id)
                } else {Text("اختر صفًا لمراجعة الزمن والمصدر والربط").foregroundColor(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}
            }
            }
        }.onChange(of:store.timeConflictsVisible){visible in if !visible {search="";onlyReview=false}}
        .padding(20).frame(width:1100,height:720).background(Color(nsColor:appearance.theme.background)).presenterTheme().environment(\.layoutDirection,.rightToLeft)
    }
    var rowHeading:some View {
        HStack(spacing:6) {
            Text("الرقم").frame(width:60)
            Text("النشاط").frame(maxWidth:.infinity,alignment:.leading)
            Text("دقيقة").frame(width:48)
            Text("الشرائح").frame(width:58)
            Text("الحالة").frame(width:54)
        }.font(.caption.bold()).padding(6)
    }
}

struct ActivityEditor:View {
    @ObservedObject private var appearance=UIAppearance.shared
    @ObservedObject var store:PresenterStore
    let activityID:String
    var index:Int? {store.project.activities.firstIndex{$0.id==activityID}}
    var a:Activity {store.project.activities.first{$0.id==activityID} ?? Activity(id:activityID,title:"جاري فتح موضع المراجعة",kind:"نشاط",original:600,duration:600)}
    var assessment:TimeAssessment {TimeSourcePolicy.assess(a,materials:store.project.materials)}
    func update(_ change:(inout Activity)->Void) {
        guard let index=index else {return}
        change(&store.project.activities[index]);store.project.activities[index].approved=false;store.changed()
    }
    func binding<T:Equatable>(_ key:WritableKeyPath<Activity,T>)->Binding<T> {
        Binding(get:{a[keyPath:key]},set:{value in if a[keyPath:key] != value {update{$0[keyPath:key]=value}}})
    }
    var governance:some View {
        VStack(alignment:.leading,spacing:6) {
            Text((a.approved ? "معتمد · ":"")+assessment.status).font(.headline)
            if let seconds=assessment.proposed {
                Text("المرجع المقترح: \(seconds/60,specifier:"%.1f") د · \(assessment.sourceLabel)").font(.callout)
                if !a.approved,abs(a.duration-seconds)>0.01 {Button("استخدام مقترح الدليل"){update{$0.duration=seconds}}.trainerHelp("استخدام المدة المرجعية دون اعتماد تلقائي")}
                if assessment.requiresReview {
                    ForEach(assessment.auxiliary){e in Text("العرض/مصدر مساعد: \(e.seconds/60,specifier:"%.1f") د · الفرق \((e.seconds-seconds)/60,specifier:"%+.1f") د").font(.caption)}
                }
            } else {Text(assessment.sourceLabel+"؛ اختر المدة يدويًا بعد مراجعة المصادر").font(.caption)}
            if a.approved,assessment.requiresReview {Text("القيمة المعتمدة محفوظة؛ هذه الملاحظة لا تعدّلها").font(.caption)}
            if !assessment.unrelated.isEmpty {Text("إحالات لعنصر زمني مختلف محفوظة أدناه؛ لا تدخل في مدة "+a.kind).font(.caption)}
        }.padding(10).background(Color.primary.opacity(0.04)).cornerRadius(8)
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Text("الرقم").font(.caption)
                    TextField("اختياري",text:Binding(get:{a.officialCode ?? ""},set:{value in if value != (a.officialCode ?? "") {update{$0.officialCode=value.isEmpty ? nil:value}}})).frame(width:90)
                    TextField("اليوم",text:binding(\.day))
                }
                TextField("الجلسة",text:binding(\.session))
                TextField("اسم النشاط",text:binding(\.title)).textFieldStyle(.roundedBorder).accessibilityIdentifier("reviewActivityTitle")
                HStack {
                    Picker("النوع",selection:binding(\.kind)) {ForEach(["نشاط","استراحة","تأمل","جلسة","يوم"],id:\.self){Text($0)}}
                    Text("الزمن بالدقائق")
                    TextField("دقائق",value:Binding(get:{a.duration/60},set:{value in if a.duration != value*60 {update{$0.duration=value*60}}}),format:.number).frame(width:65)
                }
                Text("اليوم: \(a.day.isEmpty ? "غير محدد":a.day)\nالجلسة: \(a.session.isEmpty ? "غير محددة":a.session)\nالزمن الأصلي: \(a.original/60,specifier:"%.1f") دقيقة").font(.caption).foregroundColor(.secondary)
                Divider()
                Text("ربط العرض — اختياري وباعتمادك").font(.headline)
                if let note=a.mappingNote {Text(note).font(.callout).foregroundColor(.orange)}
                if let start=a.proposedStartPage,let end=a.proposedEndPage {
                    Button("استخدام الربط المقترح: \(start)–\(end)"){update{$0.startPage=start;$0.endPage=end;$0.proposedStartPage=nil;$0.proposedEndPage=nil}}
                }
                Picker("العرض",selection:Binding(get:{a.presentationID ?? ""},set:{value in if value != (a.presentationID ?? "") {update{$0.presentationID=value.isEmpty ? nil:value}}})) {
                    Text("بلا ربط — تفعيل يدوي").tag("")
                    ForEach(store.project.materials.filter{$0.pages>0}){m in Text(m.name).tag(m.id)}
                }
                if a.presentationID != nil {
                    HStack {
                        Text("من شريحة")
                        TextField("من",value:Binding(get:{a.startPage ?? 1},set:{value in if value != a.startPage {update{$0.startPage=value}}}),format:.number).frame(width:60)
                        Text("إلى")
                        TextField("إلى",value:Binding(get:{a.endPage ?? a.startPage ?? 1},set:{value in if value != a.endPage {update{$0.endPage=value}}}),format:.number).frame(width:60)
                        Button("الحالية"){let page=store.project.currentPage+1;update{$0.startPage=page;$0.endPage=page}}
                    }
                }
                governance
                HStack {
                    Button(a.approved ? "معتمد":"اعتماد القيمة والربط"){store.approve(activityID)}.accessibilityIdentifier("approveActivity").buttonStyle(.borderedProminent).tint(appearance.theme.accent)
                    Button("بدء النشاط"){store.beginActivity(activityID)}.disabled(!a.approved || ["جلسة","يوم"].contains(a.kind)).accessibilityIdentifier("beginReviewedActivity")
                }
                HStack {
                    Button("تحريك لأعلى"){if let i=index,i>0 {store.project.activities.swapAt(i,i-1);store.changed()}}.disabled((index ?? 0)==0)
                    Button("تحريك لأسفل"){if let i=index,i+1<store.project.activities.count {store.project.activities.swapAt(i,i+1);store.changed()}}.disabled((index ?? 0)+1>=store.project.activities.count)
                    Button("حذف") {
                        guard let index=index else {return}
                        if store.project.currentActivity==activityID {store.project.currentActivity=nil}
                        store.project.timers.removeValue(forKey:activityID);store.project.activities.remove(at:index);store.selectedReview=nil;store.changed()
                    }
                }
                Divider()
                Text("مصادر الزمن").font(.headline)
                if a.evidence.isEmpty {Text("إدخال يدوي — لا يوجد مصدر مستخرج").foregroundColor(.secondary)}
                ForEach(a.evidence){e in
                    VStack(alignment:.leading,spacing:7) {
                        Text("\(e.filename) · صفحة/شريحة \(e.page) · \(e.seconds/60,specifier:"%.1f") د").font(.caption.bold())
                        Text(e.sourceDescription).font(.system(size:13)).textSelection(.enabled)
                        Button("عرض المصدر"){store.previewSource(e)}.trainerHelp("فتح ملف مصدر الزمن عند الصفحة المحددة")
                            .disabled(!store.project.materials.contains{$0.id==e.fileID && $0.renderedPath != nil}).accessibilityIdentifier("sourceEvidence:"+e.id)
                    }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04)).cornerRadius(8)
                }
            }.textFieldStyle(.roundedBorder).padding(16).disabled(index==nil)
        }
    }
}
