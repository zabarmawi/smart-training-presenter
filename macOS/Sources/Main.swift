import SwiftUI
import AppKit
import PDFKit

final class FittedPDFView:PDFView {
    var fillViewport=false
    override func layout() {
        super.layout()
        guard let page=currentPage,bounds.width>0,bounds.height>0 else {return}
        let size=page.bounds(for:.cropBox).size
        guard size.width>0,size.height>0 else {return}
        let w=max(1,bounds.width-2)/size.width,h=max(1,bounds.height-2)/size.height
        let target=fillViewport ? max(w,h):min(w,h)
        if abs(scaleFactor-target)>0.002 {scaleFactor=target}
    }
}
struct PDFCanvas:NSViewRepresentable {
    let document:PDFDocument?
    let page:Int
    var fillViewport=false
    let onPage:(Int)->Void
    func makeCoordinator()->Coordinator {Coordinator(onPage)}
    func makeNSView(context:Context)->FittedPDFView {
        let v=FittedPDFView();v.autoScales=false;v.displayMode = .singlePage;v.displayDirection = .horizontal
        v.displaysPageBreaks=false;v.pageBreakMargins = .init(top:0,left:0,bottom:0,right:0)
        v.pageShadowsEnabled=false;v.backgroundColor = .windowBackgroundColor
        NotificationCenter.default.addObserver(context.coordinator,selector:#selector(Coordinator.pageChanged(_:)),name:.PDFViewPageChanged,object:v)
        return v
    }
    func updateNSView(_ v:FittedPDFView,context:Context) {
        v.backgroundColor=UIAppearance.shared.theme.surround
        context.coordinator.onPage=onPage
        guard v.document !== document || context.coordinator.lastPage != page || v.fillViewport != fillViewport else {return}
        context.coordinator.lastPage=page;context.coordinator.updating=true
        if v.document !== document {v.document=document}
        if let p=document?.page(at:page),v.currentPage !== p {v.go(to:p)}
        if v.fillViewport != fillViewport {v.fillViewport=fillViewport}
        v.needsLayout=true;context.coordinator.updating=false
    }
    static func dismantleNSView(_ view:FittedPDFView,coordinator:Coordinator) {NotificationCenter.default.removeObserver(coordinator)}
    final class Coordinator:NSObject {
        var onPage:(Int)->Void;var updating=false;var lastPage:Int?
        init(_ callback:@escaping(Int)->Void) {onPage=callback}
        @objc func pageChanged(_ n:Notification) {
            guard !updating,let v=n.object as? PDFView,let d=v.document,let p=v.currentPage else {return}
            let i=d.index(for:p);DispatchQueue.main.async {[weak self] in self?.onPage(i)}
        }
    }
}
struct RootView:View {
    @ObservedObject var store:PresenterStore
    @ObservedObject private var appearance=UIAppearance.shared
    @StateObject private var hover=TrainerHoverHelp()
    @State private var sidebar=false
    @State private var fillViewport=false
    @State private var focused=false
    @StateObject private var windowState=PresenterWindowState()
    @State private var previousBarMode:String?
    @State private var jump="1"
    var body:some View {
        VStack(spacing:0) {
            header
            presentationHeader
            TrainerHelpBar()
            SharingHint(sharing:store.sharing)
            Divider()
            HStack(spacing:0) {
                if sidebar { files.frame(width:246); Divider() }
                VStack(spacing:0) {
                    ZStack {
                        Color(nsColor:appearance.theme.background)
                        if store.document != nil {
                            TrainerDocumentArea(store:store,sharing:store.sharing,fillViewport:fillViewport)
                                .environment(\.layoutDirection,.leftToRight)
                        } else {
                            VStack(spacing:18) {
                                Image(systemName:"rectangle.stack").font(.system(size:56)).foregroundColor(appearance.theme.accent)
                                Text("مساحة العرض").font(.title)
                                Text(store.displayMessage ?? store.material?.status ?? "استورد عرض PDF أو PowerPoint لبدء حقيبتك")
                                    .foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth:560)
                                Button("استيراد ملفات",action:store.importPanel).disabled(store.busy)
                                if let material=store.material,["pptx","ppt"].contains(URL(fileURLWithPath:material.path).pathExtension.lowercased()) {
                                    Button("إعادة محاولة عرض PowerPoint"){store.retryPresentation(material.id)}.disabled(store.busy).accessibilityIdentifier("retryPresentation")
                                }
                                if store.busy {Text("تجهيز الملف وانتظار جاهزية محرك العرض؛ أدوات المؤقت مستمرة").font(.caption)}
                            }.padding(28)
                        }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    if let notice=store.notice {
                        HStack {
                            Image(systemName:"bell.badge")
                            Text(notice.text).font(.system(size:12)).lineLimit(1)
                            Spacer();Button("إخفاء") {store.notice=nil}
                        }.foregroundColor(.orange).padding(.horizontal,12).frame(height:28)
                    }
                    ControlDock(store:store)
                }
            }
        }
        .background(Color(nsColor:appearance.theme.background)).presenterTheme()
        .environmentObject(hover)
        .background(PresenterWindowBinder(state:windowState))
        .onChange(of:windowState.fullscreen) { value in
            focused=value;sidebar=false
            if value {previousBarMode=store.project.preferences.barMode;store.project.preferences.barMode="مخفي"}
            else if let mode=previousBarMode {store.project.preferences.barMode=mode;previousBarMode=nil}
            store.changed()
        }
        .onChange(of:store.project.currentPage) {jump=String($0+1)}
        .onChange(of:store.project.currentFile) {_ in jump=String(store.project.currentPage+1)}
        .onChange(of:windowState.error) { value in if let value=value {store.error=value} }
        .environment(\.layoutDirection,.rightToLeft)
        .frame(minWidth:1040,minHeight:720)
        .sheet(isPresented:$store.libraryVisible) {LibraryView(store:store).environmentObject(hover)}
        .sheet(isPresented:$store.review,onDismiss:store.scheduleRecovery) { ReviewView(store:store).environmentObject(hover) }
        .sheet(isPresented:$store.settings,onDismiss:store.changed) { SettingsView(store:store).environmentObject(hover) }
        .alert("تنبيه",isPresented:Binding(get:{store.error != nil},set:{if !$0 { store.error=nil }})) {
            Button("حسنًا") { store.error=nil }
        } message: { Text(store.error ?? "") }
    }
    var header:some View {
        VStack(spacing:0) {
        HStack(spacing:8) {
            Button {sidebar.toggle()} label:{Image(systemName:"sidebar.right")}.trainerHelp("ملفات الحقيبة").accessibilityIdentifier("toggleFiles")
            if !focused {
                Button("المكتبة") {store.libraryVisible=true}.trainerHelp("فتح مكتبة الحقائب").accessibilityIdentifier("openLibrary")
                Button("استيراد",action:store.importPanel).disabled(store.busy).keyboardShortcut("i",modifiers:.command)
                Button("الأنشطة") {store.review=true}.trainerHelp("مراجعة الأنشطة والأزمنة").accessibilityIdentifier("openReview")
            }
            ShareControls(sharing:store.sharing)
            Button {store.setFollowing(!store.project.preferences.followsSlides)} label:{
                Label(store.project.preferences.followsSlides ? "اتباع الأنشطة":"معاينة آمنة",systemImage:store.project.preferences.followsSlides ? "link":"lock.shield")
            }.trainerHelp("المعاينة تثبت النشاط والمؤقت أثناء التنقل. الاتباع يفعّل النشاط المرتبط بالشريحة").accessibilityIdentifier("followSlides")
            if store.busy {ProgressView().controlSize(.small)}
            Spacer(minLength:0)
            Button {store.navigate(store.project.currentPage-1)} label:{Image(systemName:"chevron.right")}.trainerHelp("الصفحة السابقة").accessibilityLabel("الصفحة السابقة").accessibilityIdentifier("previousPage")
            Text("\(store.project.currentPage+1) / \(store.document?.pageCount ?? 0)").monospacedDigit().font(.caption)
            Button {store.navigate(store.project.currentPage+1)} label:{Image(systemName:"chevron.left")}.trainerHelp("الصفحة التالية").accessibilityLabel("الصفحة التالية").accessibilityIdentifier("nextPage")
            if !focused {TextField("صفحة",text:$jump).accessibilityIdentifier("jumpPage").trainerHelp("اكتب رقم الصفحة واضغط إدخال").frame(width:38).textFieldStyle(.roundedBorder).onSubmit {if let n=Int(jump) {store.navigate(n-1)}}}
            HeaderTimer(store:store).fixedSize(horizontal:true,vertical:false)
            Button {store.project.preferences.barMode=store.project.preferences.barMode=="مخفي" ? "مصغّر":"مخفي";store.changed()} label:{Image(systemName:store.project.preferences.barMode=="مخفي" ? "eye":"eye.slash")}
                .trainerHelp("إظهار أو إخفاء شريط المؤقت — العد مستمر").accessibilityIdentifier("toggleDock")
            Menu {
                Button("احتواء الشريحة كاملة") {fillViewport=false}
                Button("ملء المساحة مع قص الأطراف") {fillViewport=true}
            } label:{Image(systemName:"aspectratio")}.fixedSize().trainerHelp("حجم الشريحة")
            Button {
                windowState.toggle()
            } label:{Image(systemName:focused ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right")}.trainerHelp("ملء الشاشة الأصلي").disabled(windowState.transitioning).accessibilityIdentifier("presentationFocus")
            Button {store.settings=true} label:{Image(systemName:"slider.horizontal.3")}.trainerHelp("إعدادات الواجهة والمؤقت").accessibilityIdentifier("openSettings")
        }.padding(.horizontal,10).frame(height:48)
        Text(store.freeMode ? "المؤقت الحر":(store.current?.displayTitle ?? "لم يُحدد نشاط"))
            .font(.system(size:12,weight:.medium)).multilineTextAlignment(.leading)
            .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
            .padding(.horizontal,12).padding(.bottom,6).textSelection(.enabled)
            .accessibilityIdentifier("headerActivity")
        }
    }
    var files:some View {
        VStack(alignment:.leading,spacing:12) {
            TextField("اسم الحقيبة",text:$store.project.name).font(.headline).onSubmit(store.changed)
            HStack { Text("ملفات الحقيبة").font(.headline); Spacer(); Text("\(store.project.materials.count)").foregroundColor(.secondary) }
            ScrollView {
                VStack(spacing:8) {
                    ForEach(store.project.materials) { m in
                        Button { store.selectFile(m.id) } label: {
                            HStack(alignment:.top,spacing:8) {
                                Image(systemName:m.renderedPath == nil ? "doc.text":"rectangle.on.rectangle").foregroundColor(appearance.theme.accent)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(m.name).font(.system(size:12,weight:.medium)).lineLimit(3).multilineTextAlignment(.leading)
                                    Text(m.pages>0 ? "\(m.pages) صفحة":"مستند مرتبط").font(.caption2).foregroundColor(.secondary)
                                }; Spacer(minLength:0)
                            }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                            .background(store.project.currentFile==m.id ? appearance.theme.accent.opacity(0.16):Color.primary.opacity(0.035)).cornerRadius(8)
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("تحريك لأعلى") { store.moveFile(m.id,-1) }
                            Button("تحريك لأسفل") { store.moveFile(m.id,1) }
                            Button("إعادة قراءة وتحليل") { store.importURLs([URL(fileURLWithPath:m.path)],refresh:true) }.disabled(store.busy)
                            if ["pptx","ppt"].contains(URL(fileURLWithPath:m.path).pathExtension.lowercased()) {Button("إعادة محاولة العرض فقط"){store.retryPresentation(m.id)}.disabled(store.busy)}
                            Button("تحديد المصدر في Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:m.path)]) }
                            Button("إزالة من الحقيبة") { store.removeFile(m.id) }
                        }
                    }
                }
            }
            Text("PDF · PPTX · PPT عبر محوّل\nDOCX ونصوص لاستخراج الأزمنة\nباقي الصيغ مرفقات مرتبطة فقط")
                .font(.system(size:11)).foregroundColor(.secondary).lineSpacing(5)
            Divider()
            HStack { Text("الأنشطة").font(.headline); Spacer(); Button {store.addActivity()} label:{Image(systemName:"plus")} }
            ScrollView {
                VStack(spacing:6) {
                    ForEach(store.timedActivities) { a in
                        Button { store.selectActivity(a.id) } label: {
                            VStack(alignment:.leading,spacing:5) {
                                Text((a.officialCode.map{"["+$0+"] "} ?? "")+a.title).lineLimit(2).multilineTextAlignment(.leading)
                                Text("\(Int(a.duration/60)) د · "+(a.approved ? "معتمد":(a.conflict ? "تعارض — راجع":"بانتظار الاعتماد")))
                                    .font(.caption2).foregroundColor(a.approved ? appearance.theme.accent:.orange)
                            }.font(.system(size:12)).padding(8).frame(maxWidth:.infinity,alignment:.leading)
                                .background(store.project.currentActivity==a.id ? appearance.theme.accent.opacity(0.13):Color.clear).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight:220)
        }.padding(14)
    }
    var presentationHeader:some View {
        HStack(spacing:10) {
            Text(store.material?.name ?? "مشغّل الحقائب التدريبية").font(.system(size:12,weight:.medium)).lineLimit(2).textSelection(.enabled).accessibilityIdentifier("currentFilename")
            Spacer(minLength:0)
            AudienceSizingControls(sharing:store.sharing)
            Button("دليل المدرب"){store.openGuide("trainer")}.trainerHelp("فتح دليل المدرب للمعاينة الخاصة").accessibilityIdentifier("openTrainerGuide")
            Button("دليل المتدرب"){store.openGuide("learner")}.trainerHelp("فتح دليل المتدرب للمعاينة الخاصة").accessibilityIdentifier("openLearnerGuide")
            Button("العودة للعرض",action:store.returnToPresentation).trainerHelp("العودة إلى موضع العرض السابق").accessibilityIdentifier("returnToPresentation")
        }.padding(.horizontal,12).padding(.bottom,5)
    }

}
struct HeaderTimer:View {
    @ObservedObject private var appearance=UIAppearance.shared
    @ObservedObject var store:PresenterStore
    var body:some View {
        HStack(spacing:7) {
            VStack(alignment:.leading,spacing:1) {
                Text(store.timer.running ? "قيد التشغيل":(store.timer.elapsed>0 ? "متوقف مؤقتًا":"جاهز")).font(.system(size:9)).foregroundColor(.secondary)
            }
            Text(timeText(store.timer.remaining(store.now))).font(.system(size:20,weight:.semibold,design:.monospaced)).foregroundColor(store.timer.remaining(store.now)<0 ? .orange:appearance.theme.accent).environment(\.layoutDirection,.leftToRight)
            Button(action:store.toggle) {Image(systemName:store.timer.running ? "pause.fill":"play.fill")}.disabled(!store.freeMode && store.current?.approved != true).trainerHelp("تشغيل أو إيقاف مؤقت").accessibilityIdentifier("headerToggleTimer")
        }
    }
}
struct ControlDock:View {
    @ObservedObject private var appearance=UIAppearance.shared
    @ObservedObject var store:PresenterStore
    @State private var minutes=10.0
    var compact:Bool {store.project.preferences.barMode != "ثابت"}
    var body:some View {
        if store.project.preferences.barMode != "مخفي" {
            VStack(spacing:8) {
                HStack(spacing:10) {
                    Text(store.freeMode ? "المؤقت الحر":(store.current?.displayTitle ?? "اختر نشاطًا معتمدًا")).font(.system(size:12,weight:.medium)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                    Text(timeText(store.timer.remaining(store.now))).font(.system(size:26,weight:.semibold,design:.monospaced)).foregroundColor(store.timer.remaining(store.now)<0 ? .orange:appearance.theme.accent).environment(\.layoutDirection,.leftToRight).accessibilityIdentifier("timerValue")
                    Button(store.timer.running ? "إيقاف":"تشغيل",action:store.toggle).disabled(!store.freeMode && store.current?.approved != true).accessibilityIdentifier("toggleTimer")
                    Button("ضبط",action:store.reset).trainerHelp("إعادة ضبط المؤقت").accessibilityIdentifier("resetTimer")
                    Menu {
                        Button("مؤقت النشاط") {store.freeMode=false}
                        Button("المؤقت الحر") {store.freeMode=true}
                    } label:{Text(store.freeMode ? "حر":"نشاط").foregroundColor(appearance.theme.text)}.fixedSize()
                    Button("−1") {store.proposed=max(0,store.proposed-1)}.trainerHelp("إنقاص دقيقة من التمديد المقترح").accessibilityIdentifier("extendMinus")
                    Text("+\(store.proposed) د").font(.caption).monospacedDigit()
                    Button("+1") {store.proposed=min(1440,store.proposed+1)}.trainerHelp("اقتراح تمديد دقيقة").accessibilityIdentifier("extendPlus")
                    Button("تأكيد",action:store.extend).disabled(store.proposed==0).trainerHelp("تأكيد التمديد المتراكم").accessibilityIdentifier("confirmExtension")
                    Button("التالي",action:store.next).trainerHelp("النشاط التالي").disabled(store.nextActivity==nil)
                    Button {store.project.preferences.barMode=compact ? "ثابت":"مصغّر";store.changed()} label:{Image(systemName:compact ? "chevron.up":"chevron.down")}.trainerHelp("توسيع أو تصغير الشريط").accessibilityIdentifier("compactDock")
                }.frame(height:36)
                if !compact {
                    HStack(spacing:10) {
                        Text("مدة بالدقائق:").font(.caption)
                        TextField("دقائق",value:$minutes,format:.number).frame(width:50).textFieldStyle(.roundedBorder)
                        Button("تعديل المدة") {if minutes>0 && minutes<=1440 {store.duration(minutes)}}
                        Text("الأصل \(Int(store.timer.original/60)) د · التمديد \(Int(store.timer.extensions/60)) د").font(.caption).foregroundColor(.secondary)
                        Button("إلغاء التمديد") {store.proposed=0}.disabled(store.proposed==0)
                        Spacer()
                        if let next=store.nextActivity {Text("التالي: \(next.displayTitle)").font(.caption).lineLimit(1)}
                    }.frame(height:28)
                }
            }.padding(.horizontal,12).padding(.vertical,4).background(Color(nsColor:appearance.theme.panel))
        }
    }
}
struct SettingsView:View {
    @ObservedObject private var appearance=UIAppearance.shared
    @ObservedObject var store:PresenterStore
    @Environment(\.dismiss) var dismiss
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:18) {
            Text("إعدادات العرض والمؤقت").font(.title2.bold())
            AboutApplicationView()
            Picker("مظهر الواجهة",selection:$appearance.theme) {
                ForEach(PresenterTheme.allCases,id:\.self){Text($0.rawValue).tag($0)}
            }.pickerStyle(.segmented).accessibilityIdentifier("themePicker")
            Text("يُحفظ المظهر تلقائيًا؛ ألوان الشرائح الأصلية ثابتة").font(.caption).foregroundColor(.secondary)
            Toggle("اتباع الأنشطة المرتبطة أثناء التنقل — إلغاء الاختيار يثبت المؤقت للمعاينة",isOn:Binding(get:{store.project.preferences.followsSlides},set:{store.setFollowing($0)}))
            Toggle("بدء النشاط تلقائيًا عند تفعيله أو دخول نطاق شرائحه المعتمد",isOn:$store.project.preferences.autoStart)
            Text("يتوقف مؤقت النشاط السابق عند تفعيل نشاط آخر. التبديل إلى المؤقت الحر يحفظ مؤقت النشاط ويتركه مستمرًا. بعد فتح حقيبة محفوظة تكون المؤقتات متوقفة مؤقتًا للاستئناف.").font(.caption).foregroundColor(.secondary)
            Divider()
            Toggle("التنبيهات الصوتية",isOn:$store.project.preferences.sound)
            HStack {Text("مستوى الصوت");Slider(value:$store.project.preferences.volume,in:0...1);Button("تجربة الصوت"){store.playSound()} }
            Picker("النغمات",selection:$store.project.preferences.soundSet) {
                Text("نغمات المؤقت السابق — ثلاث مراحل").tag(0)
                Text("Glass / Ping / Hero").tag(1)
            }
            Toggle("التنبيهات المرئية",isOn:$store.project.preferences.visual)
            Stepper("مدة الإشعار: \(Int(store.project.preferences.noticeSeconds)) ثوانٍ",value:$store.project.preferences.noticeSeconds,in:1...60)
            Text("تظهر التنبيهات خارج الشريحة. كل حد يُنبه مرة واحدة حتى إعادة الضبط؛ التمديد وتعديل المدة لا يطلقان تنبيهات قديمة.").font(.caption).foregroundColor(.secondary)
            Divider()
            Text("عرض PowerPoint").font(.headline)
            Text("يستخدم محرك LibreOffice المحدد، وإلا PowerPoint المثبت. التحويل على نسخة مؤقتة؛ بلا حركات أو فيديو أو تفاعل. قد تختلف الخطوط، لذا راجع التصميم قبل العرض.").font(.callout)
            HStack {Button("تحديد محرك LibreOffice",action:store.chooseConverter);Button("استخدام PowerPoint"){UserDefaults.standard.removeObject(forKey:"converter");store.objectWillChange.send()} }
            Text(DocumentReader.converterPath() ?? "PowerPoint إذا كان مثبتًا؛ قد يطلب macOS إذن التحكم فيه").font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
            Divider()
            HStack {Spacer();Button("تم"){dismiss()}.keyboardShortcut(.defaultAction)}
        }.textFieldStyle(.roundedBorder).padding(24)}.frame(width:660,height:740).presenterTheme().environment(\.layoutDirection,.rightToLeft)
    }
}
final class AppDelegate:NSObject,NSApplicationDelegate {
    static var store:PresenterStore?
    static var pendingURLs:[URL]=[]
    private var launchWindow:NSWindow?
    private var presenterKeys:PresentationKeys?
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.regular)
        if let store=Self.store {let keys=PresentationKeys();keys.install(store);presenterKeys=keys}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {[weak self] in
            guard let self=self,!NSApp.windows.contains(where:{$0.isVisible}),let store=Self.store else {return}
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title=SharingSession.trainerTitle;window.sharingType = .none;window.contentView=NSHostingView(rootView:RootView(store:store))
            window.center();window.makeKeyAndOrderFront(nil);self.launchWindow=window
            NSApp.activate(ignoringOtherApps:true);UISmoke.run(store)
        }
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        AppDelegate.store?.checkpoint();return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func application(_ application:NSApplication,open urls:[URL]) {
        guard AppDelegate.store != nil else {AppDelegate.pendingURLs += urls;return}
        if let u=urls.first(where:{["stpresenter","stbag"].contains($0.pathExtension)}) {AppDelegate.store?.open(u)}
        else {AppDelegate.store?.importURLs(urls)}
    }
}
@main struct PresenterApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store:PresenterStore
    init() {
        let initial=PresenterStore();_store=StateObject(wrappedValue:initial);AppDelegate.store=initial
    }
    var body:some Scene {
        WindowGroup(SharingSession.trainerTitle,id:"main") {
            RootView(store:store).onAppear {AppDelegate.store=store;NSApp.activate(ignoringOtherApps:true)
                if !AppDelegate.pendingURLs.isEmpty {
                    let urls=AppDelegate.pendingURLs;AppDelegate.pendingURLs=[];delegate.application(NSApp,open:urls)
                }
                UISmoke.run(store)}
        }.defaultSize(width:1280,height:900)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("مكتبة الحقائب") {store.libraryVisible=true}.keyboardShortcut("b",modifiers:[.command,.shift])
                Button("حقيبة جديدة",action:store.newProject).keyboardShortcut("n")
                Button("فتح حقيبة…",action:store.openPanel).keyboardShortcut("o")
            }
            CommandGroup(replacing:.saveItem) {
                Button("حفظ الحقيبة…"){store.save()}.keyboardShortcut("s")
                Button("حفظ باسم…"){store.save(asNew:true)}.keyboardShortcut("s",modifiers:[.command,.shift])
                Button("تصدير حقيبة قابلة للنقل…",action:store.exportPortable).disabled(store.busy)
            }
            CommandMenu("العرض والمؤقت") {
                Button("الشريحة التالية"){store.navigate(store.project.currentPage+1)}.keyboardShortcut(.rightArrow,modifiers:.command)
                Button("الشريحة السابقة"){store.navigate(store.project.currentPage-1)}.keyboardShortcut(.leftArrow,modifiers:.command)
                Button("تشغيل / إيقاف مؤقت",action:store.toggle).keyboardShortcut("t",modifiers:[.command,.shift])
                Button(store.project.preferences.followsSlides ? "تثبيت النشاط للمعاينة":"اتباع الأنشطة أثناء العرض"){store.setFollowing(!store.project.preferences.followsSlides)}.keyboardShortcut("l",modifiers:[.command,.shift])
                Button("تكبير / استعادة الجمهور",action:store.sharing.toggleMaximize).keyboardShortcut("j",modifiers:[.command,.shift])
                Button("أدوات المدرب",action:store.sharing.showTrainer).keyboardShortcut("m",modifiers:[.command,.shift])
                Button("النشاط التالي",action:store.next).keyboardShortcut("n",modifiers:[.command,.shift])
            }
        }
    }
}
