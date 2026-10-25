import SwiftUI

struct LibraryView:View {
    @ObservedObject private var appearance=UIAppearance.shared
    @ObservedObject var store:PresenterStore
    @Environment(\.dismiss) var dismiss
    @State private var track="الكل"
    @State private var search=""
    @State private var selected:String?
    var bags:[LibraryBag] {store.library.bags.filter{(track=="الكل" || $0.track==track) && (search.isEmpty || TimingExtractor.normalized($0.displayTitle).contains(TimingExtractor.normalized(search)))}}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("مكتبة الحقائب التدريبية").font(.title2.bold());Spacer()
                Text("\(store.library.bags.count) حقيبة").foregroundColor(.secondary)
                Button("تم") {dismiss()}.keyboardShortcut(.defaultAction).disabled(store.busy)
            }
            HStack {
                Button("تحديد مجلد البرنامج",action:store.chooseLibraryFolder).accessibilityIdentifier("chooseLibrary")
                Button("تحديث الفهرس") {store.scanLibrary(URL(fileURLWithPath:store.library.root))}.disabled(store.library.root.isEmpty)
                Spacer();if store.busy {ProgressView().controlSize(.small);Text(store.libraryProgress).font(.caption)}
            }.disabled(store.busy)
            HStack {
                Picker("المسار",selection:$track) {
                    Text("جميع المسارات").tag("الكل")
                    ForEach(Array(Set(store.library.bags.map(\.track))).sorted(),id:\.self){Text($0).tag($0)}
                }.frame(maxWidth:440).accessibilityIdentifier("libraryTrack")
                TextField("بحث باسم المجال أو الحقيبة",text:$search).textFieldStyle(.roundedBorder).accessibilityIdentifier("librarySearch")
            }
            Divider()
            HStack(alignment:.top,spacing:18) {
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:10) {
                        ForEach(bags) {bag in
                            Button {selected=bag.id} label:{
                                VStack(alignment:.leading,spacing:7) {
                                    Text(bag.domain+" — "+bag.title).font(.headline)
                                    Text(bag.track).font(.caption).foregroundColor(.secondary)
                                    HStack {Text(bag.status).foregroundColor(bag.status=="جاهزة للتدريب" ? appearance.theme.accent:.orange);Spacer();Text("\(bag.approvedCount) معتمد من \(bag.activityCount)")}.font(.caption)
                                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(selected==bag.id ? appearance.theme.accent.opacity(0.12):Color.primary.opacity(0.035)).cornerRadius(9)
                            }.buttonStyle(.plain).accessibilityIdentifier("libraryBag:"+bag.id)
                        }
                        if bags.isEmpty {Text(store.library.bags.isEmpty ? "اختر مجلد البرنامج لفهرسة الحقائب دون تغيير ملفاتها":"لا توجد حقائب مطابقة").foregroundColor(.secondary).padding()}
                    }
                }.frame(width:440)
                Divider()
                if let bag=store.library.bags.first(where:{$0.id==selected}) {details(bag)}
                else {Text("اختر حقيبة للاطلاع على ملفاتها وحالة تجهيزها").foregroundColor(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}
            }
            Text("كل حقيبة مستقلة بأنشطتها وتعديلاتها. تبقى المصادر الأصلية في مكانها، وتُحفظ المراجعة وحالة التدريب محليًا.").font(.caption).foregroundColor(.secondary)
        }.padding(22).frame(width:1080,height:730).background(Color(nsColor:appearance.theme.background)).tint(appearance.theme.accent).presenterTheme().environment(\.layoutDirection,.rightToLeft)
        .interactiveDismissDisabled(store.busy)
        .onAppear {if selected==nil {selected=bags.first?.id}}
    }
    func details(_ bag:LibraryBag)->some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text(bag.domain).font(.title2.bold());Text(bag.title).font(.headline);Text(bag.track).foregroundColor(.secondary)
                ForEach(bag.files,id:\.relativePath) {file in
                    VStack(alignment:.leading,spacing:3) {
                        Text(file.role=="slides" ? "العرض التقديمي":(file.role=="trainer" ? "دليل المدرب":"دليل المتدرب")).font(.headline)
                        Text(URL(fileURLWithPath:file.relativePath).lastPathComponent).font(.caption).textSelection(.enabled)
                    }
                }
                Divider()
                Text(bag.status).font(.headline).foregroundColor(bag.status=="جاهزة للتدريب" ? appearance.theme.accent:.orange)
                Text("الأنشطة: \(bag.activityCount) · المعتمد: \(bag.approvedCount) · المرتبط بالعرض: \(bag.linkedCount)").font(.caption)
                HStack {
                    if bag.preparedHashes==nil || bag.changed {
                        Button("تجهيز ومراجعة") {store.prepareLibraryBag(bag.id)}.buttonStyle(.borderedProminent).disabled(!bag.complete).accessibilityIdentifier("prepareLibraryBag")
                    } else {
                        Button("مراجعة الأنشطة") {store.openLibraryBag(bag.id,review:true)}.buttonStyle(.borderedProminent).accessibilityIdentifier("reviewLibraryBag")
                        Button("فتح العرض") {store.openLibraryBag(bag.id)}.accessibilityIdentifier("openLibraryBag")
                    }
                    Button("بدء التدريب") {store.openLibraryBag(bag.id,start:true)}.disabled(bag.status != "جاهزة للتدريب").accessibilityIdentifier("startLibraryBag")
                }.disabled(store.busy)
                if bag.preparedHashes != nil {Button("إعادة التحليل مع الاحتفاظ بتعديلاتي") {store.prepareLibraryBag(bag.id)}.disabled(store.busy)}
                if !bag.issues.isEmpty {
                    Text("ملاحظات التجهيز").font(.headline)
                    ForEach(Array(bag.issues.enumerated()),id:\.offset){item in Text("• "+item.element).font(.caption).foregroundColor(.orange)}
                    Text("راجع هذه الملاحظات مع الدليل قبل اعتماد الحقيبة").font(.caption)
                    Button(bag.notesReviewed==true ? "تم تأكيد مراجعة الملاحظات":"تأكيد معالجة ملاحظات الحقيبة") {
                        if let index=store.library.bags.firstIndex(where:{$0.id==bag.id}) {store.library.bags[index].notesReviewed=true;do {try store.library.save()} catch {store.error=error.localizedDescription}}
                    }.disabled(store.busy || bag.approvedCount<bag.activityCount || bag.activityCount==0)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
