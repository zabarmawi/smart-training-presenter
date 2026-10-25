import AppKit
import SwiftUI
import Combine
import PDFKit
import UniformTypeIdentifiers

@MainActor final class PresenterStore: ObservableObject {
    @Published var project=Project()
    @Published var library=TrainingLibrary.load()
    @Published var libraryVisible=false
    @Published var libraryProgress=""
    @Published var freeMode=false
    @Published var now=continuousSeconds()
    @Published var proposed=0
    @Published var notice:Notice?=nil
    @Published var error:String?=nil
    @Published var busy=false
    @Published var review=false
    @Published var settings=false
    @Published var selectedReview:String?=nil
    #if !TESTING
    @Published var timeConflicts:[LibraryTimeConflict]=[]
    @Published var timeConflictsVisible=false
    @Published var timeConflictReadError:String?
    #endif
    @Published var displayMessage:String?=nil
    private var privateReturn:(epoch:UUID,file:String,page:Int)?
    @Published var document:PDFDocument?=nil
    @Published var projectURL:URL?=nil
    @Published var dirty=false
    private var ticker:AnyCancellable?
    private var lastCheckpoint=continuousSeconds()
    private var soundPlayer:NSSound?
    let recoveryWriter=RecoveryWriter()
    let libraryRecoveryWriter=RecoveryWriter()
    let sharing=SharingSession()
    @Published var privatePreview=false {didSet {project.privatePagePreview=privatePreview}}
    var projectEpoch=UUID()
    var recovery:URL { DocumentReader.cache.deletingLastPathComponent().appendingPathComponent("Recovery.stpresenter") }
    var current:Activity? { project.activities.first {$0.id==project.currentActivity} }
    var material:Material? { project.materials.first {$0.id==project.currentFile} }
    var timer:Countdown {
        freeMode ? project.freeTimer : (project.timers[project.currentActivity ?? ""] ?? Countdown(current?.duration ?? 600))
    }
    var timedActivities:[Activity] { project.activities.filter { !["جلسة","يوم"].contains($0.kind) } }
    var nextActivity:Activity? {
        guard let i=timedActivities.firstIndex(where:{$0.id==project.currentActivity}),i+1<timedActivities.count else { return nil }
        return timedActivities[i+1]
    }
    init(restore:Bool=true) {
        sharing.attach(self)
        if restore,let p=try? DocumentReader.load(recovery) {project=p;loadDisplay();dirty=true;applyReference()
            DispatchQueue.main.async {[weak self] in self?.checkChanges()}
        }
        ticker=Timer.publish(every:0.2,on:.main,in:.common).autoconnect().sink { [weak self] _ in self?.tick() }
    }
    func tick() {
        now=continuousSeconds()
        var events:[(String,Int)]=[]
        for id in project.timers.keys {
            for e in project.timers[id]!.poll(now) {
                events.append((project.activities.first(where:{$0.id==id})?.title ?? "النشاط",e))
            }
        }
        for e in project.freeTimer.poll(now) { events.append(("المؤقت الحر",e)) }
        for (name,e) in events { announce(name:name,threshold:e) }
        if let n=notice,!n.visible(now) { notice=nil }
        if now-lastCheckpoint>=10 {scheduleRecovery();lastCheckpoint=now}
        sharing.tick(now)
    }
    func announce(name:String,threshold:Int) {
        let msg=threshold==0 ? "انتهى الوقت — يستمر الزمن الإضافي. يمكنك التمديد أو الانتقال للنشاط التالي" : (threshold==60 ? "تبقّت دقيقة واحدة":"تبقّت خمس دقائق")
        if project.preferences.visual { notice=Notice(text:name+" · "+msg,until:now+project.preferences.noticeSeconds) }
        if project.preferences.sound && (!sharing.isOpen || !sharing.preferences.muteSound) { playSound(threshold) }
    }
    @discardableResult func playSound(_ threshold:Int=0)->Bool {
        let names=project.preferences.soundSet==0 ? ["alert-5m","alert-1m","alert-finish"]:["Glass","Ping","Hero"]
        let i=threshold==300 ? 0:(threshold==60 ? 1:2)
        if let path=Bundle.main.path(forResource:names[i],ofType:project.preferences.soundSet==0 ? "wav":"aiff") {
            soundPlayer=NSSound(contentsOfFile:path,byReference:false)
        } else { soundPlayer=NSSound(named:NSSound.Name(names[i])) }
        soundPlayer?.volume=Float(project.preferences.volume)
        return soundPlayer?.play() ?? false
    }
    func mutateTimer(_ f:(inout Countdown)->Void) {
        var pending:[Int]=[]
        if freeMode {pending=project.freeTimer.poll(now);f(&project.freeTimer)}
        else {
            guard let a=current,a.approved else { error="راجع زمن النشاط واربطه بالعرض عند الحاجة، ثم اضغط اعتماد قبل تشغيله"; return }
            var c=project.timers[a.id] ?? Countdown(a.duration);pending=c.poll(now);f(&c);project.timers[a.id]=c
        }
        for threshold in pending {announce(name:freeMode ? "المؤقت الحر":(current?.title ?? "النشاط"),threshold:threshold)}
        changed()
    }
    func toggle() { let n=now; mutateTimer { $0.toggle(n) } }
    func reset() { mutateTimer { $0.reset() }; proposed=0; notice=nil }
    func extend() { let n=now; let s=Double(proposed*60); mutateTimer {$0.extend(s,now:n)}; proposed=0 }
    func duration(_ minutes:Double) { let n=now; mutateTimer {$0.changeDuration(minutes*60,now:n)} }
    func selectActivity(_ id:String) {
        guard let a=project.activities.first(where:{$0.id==id}),a.approved,!["جلسة","يوم"].contains(a.kind) else {
            selectedReview=id; review=true; return
        }
        if id==project.currentActivity {freeMode=false;changed();return}
        if let old=project.currentActivity { project.timers[old]?.pause(now) }
        project.currentActivity=id; freeMode=false; proposed=0
        if !(material.flatMap{ReferenceCatalog.range(a,on:$0,materials:project.materials)}?.contains(project.currentPage+1) ?? false),let f=a.presentationID,let start=a.startPage,let end=a.endPage,
           project.currentFile != f || project.currentPage+1<start || project.currentPage+1>end {
            privatePreview=false;project.currentFile=f;project.currentPage=start-1;loadDisplay()
        }
        if project.timers[id]==nil { project.timers[id]=Countdown(a.duration) }
        if project.preferences.autoStart,project.timers[id]?.elapsed==0,project.timers[id]?.running==false {
            project.timers[id]?.toggle(now)
        }
        changed()
    }
    func next() { if let a=nextActivity { selectActivity(a.id) } }
    func navigate(_ page:Int,follow:Bool=true) {
        guard let d=document else { return }
        project.currentPage=max(0,min(page,d.pageCount-1))
        rememberPage()
        let links=(follow && !privatePreview && material.map{!["trainer","learner"].contains(SharingSession.role($0) ?? "")}==true && project.preferences.followsSlides) ? timedActivities.filter {a in
            guard a.approved,let material=material,let range=ReferenceCatalog.range(a,on:material,materials:project.materials) else {return false}
            return range.contains(project.currentPage+1)
        }:[]
        if links.count==1,links[0].id != project.currentActivity { selectActivity(links[0].id) }
        sharing.tick(continuousSeconds())
        changed()
    }
    private func rememberPage() {
        guard let m=material,(!privatePreview || ["trainer","learner"].contains(SharingSession.role(m) ?? "")) else {return}
        if project.filePages==nil {project.filePages=[:]}
        project.filePages?[m.id]=project.currentPage
    }
    private func rememberPublicReturn() {
        if !privatePreview,let m=material {privateReturn=(projectEpoch,m.id,project.currentPage)}
    }
    func selectFile(_ id:String) {
        guard let selected=project.materials.first(where:{$0.id==id}) else {return}
        rememberPage()
        let isGuide=["trainer","learner"].contains(SharingSession.role(selected) ?? "")
        if isGuide {rememberPublicReturn()}
        var page=project.filePages?[id] ?? 0
        if !isGuide,let saved=privateReturn,saved.epoch==projectEpoch,saved.file==id {page=saved.page;privateReturn=nil}
        privatePreview=isGuide;project.currentFile=id;project.currentPage=page
        loadDisplay();changed()
    }
    func returnToPresentation() {
        if let saved=privateReturn,saved.epoch==projectEpoch,project.materials.contains(where:{$0.id==saved.file}) {selectFile(saved.file);return}
        if let slides=project.materials.first(where:{SharingSession.role($0)=="slides"}) {selectFile(slides.id)}
    }
    func openGuide(_ role:String) {
        if let guide=project.materials.first(where:{SharingSession.role($0)==role}) {selectFile(guide.id)}
        else {error=role=="trainer" ? "لا يوجد دليل مدرب في الحقيبة":"لا يوجد دليل متدرب في الحقيبة"}
    }
    func loadDisplay() {
        document=nil;displayMessage=nil
        guard let material=material else {return}
        privatePreview=project.privatePagePreview ?? ["trainer","learner"].contains(SharingSession.role(material) ?? "")
        let path=material.renderedPath ?? (URL(fileURLWithPath:material.path).pathExtension.lowercased()=="pdf" ? material.path:nil)
        guard let path=path else {displayMessage=material.status;return}
        guard FileManager.default.fileExists(atPath:path) else {displayMessage="الملف مفقود: "+material.name;return}
        guard let pdf=PDFDocument(url:URL(fileURLWithPath:path)),!pdf.isLocked,pdf.pageCount>0 else {displayMessage="تعذر فتح الملف؛ قد يكون تالفًا أو محميًا: "+material.name;return}
        document=pdf;project.currentPage=max(0,min(project.currentPage,pdf.pageCount-1))
    }
    func changed() {dirty=true;scheduleRecovery()}
    func scheduleRecovery() {
        do {try saveLibraryCheckpoint()} catch {self.error=error.localizedDescription}
        let epoch=projectEpoch
        recoveryWriter.schedule(project,to:recovery,now:now) {[weak self] message in
            guard let self=self,self.projectEpoch==epoch else {return}
            self.error="تعذر حفظ الاسترداد: "+message
        }
    }
    func checkpoint() {
        sharing.save()
        do {try recoveryWriter.flush(project,to:recovery,now:continuousSeconds());try saveLibraryCheckpoint(flush:true)}
        catch {self.error="تعذّر حفظ الاسترداد: "+error.localizedDescription}
    }
    func setFollowing(_ value:Bool) {project.preferences.followSlides=value;changed()}
    func beginActivity(_ id:String) {
        guard let activity=project.activities.first(where:{$0.id==id}),activity.approved,!(["جلسة","يوم"].contains(activity.kind)) else {error="اعتمد النشاط قبل بدئه";return}
        selectActivity(id);freeMode=false
        if !timer.running {toggle()}
        review=false
    }
    func previewSource(_ evidence:Evidence) {
        guard project.materials.contains(where:{$0.id==evidence.fileID}) else {return}
        rememberPage();rememberPublicReturn()
        privatePreview=true;project.currentFile=evidence.fileID;loadDisplay();navigate(evidence.page-1,follow:false)
        review=false
    }
    func removeFile(_ id:String) {
        project.materials.removeAll {$0.id==id}
        for i in project.activities.indices {
            if project.activities[i].presentationID==id { project.activities[i].presentationID=nil; project.activities[i].approved=false }
        }
        if project.currentFile==id { project.currentFile=project.materials.first(where:{$0.renderedPath != nil})?.id; project.currentPage=0; loadDisplay() }
        changed()
    }
    func moveFile(_ id:String,_ delta:Int) {
        guard let i=project.materials.firstIndex(where:{$0.id==id}),project.materials.indices.contains(i+delta) else { return }
        project.materials.swapAt(i,i+delta); changed()
    }
    func addActivity() {
        let a=Activity(title:"نشاط جديد",kind:"نشاط",original:600,duration:600)
        project.activities.append(a); selectedReview=a.id; review=true; changed()
    }
    func approve(_ id:String) {
        guard let i=project.activities.firstIndex(where:{$0.id==id}) else { return }
        let a=project.activities[i]
        guard !a.title.trimmingCharacters(in:.whitespaces).isEmpty,a.duration>0,a.duration<=86400 else { error="أدخل اسمًا وزمنًا صالحًا من ثانية إلى 24 ساعة"; return }
        if let f=a.presentationID {
            guard let m=project.materials.first(where:{$0.id==f}),let s=a.startPage,let e=a.endPage,s>0,e>=s,e<=m.pages else {
                error="حدد نطاق شرائح صالحًا للعرض المختار"; return
            }
            let overlap=project.activities.contains { b in
                b.id != a.id && b.approved && b.presentationID==f && b.startPage != nil && b.endPage != nil && s<=b.endPage! && e>=b.startPage!
            }
            guard !overlap else { error="نطاق الشرائح يتداخل مع نشاط معتمد؛ عدّل الربط قبل الاعتماد"; return }
        }
        project.activities[i].approved=true
        if var c=project.timers[id] { c.changeDuration(a.duration,now:now); project.timers[id]=c }
        changed()
    }
    @discardableResult func applyReference() -> Bool {
        var proposed:[Activity]=[]
        for material in project.materials {
            if let items=ReferenceCatalog.activities(material:material) {ReferenceCatalog.reconcile(items,existing:&proposed)}
        }
        guard !proposed.isEmpty else {return false}
        let matched=Set(project.materials.filter{ReferenceCatalog.load()?.fingerprint($0) != nil}.map(\.id))
        project.activities.removeAll {a in a.catalogID==nil && !a.approved && !a.evidence.isEmpty && a.evidence.allSatisfy{matched.contains($0.fileID)} && project.timers[a.id]==nil}
        ReferenceCatalog.reconcile(proposed,existing:&project.activities)
        ReferenceCatalog.bindEvidence(in:&project)
        return true
    }
    func synchronizeReference() {
        guard applyReference() else {error="لم تطابق الملفات خريطة الحقيبتين في المؤقت السابق. استورد ملفات الحقيبة الأصلية أو استخدم التحليل المحلي";return}
        changed();review=true
    }
    func approveMap() {
        for a in project.activities where !TimeSourcePolicy.assess(a,materials:project.materials).requiresReview && a.catalogID?.contains("unplaced") != true && a.mappingNote==nil {approve(a.id)}
    }
    func moveActivity(_ id:String,_ delta:Int) {
        guard let i=project.activities.firstIndex(where:{$0.id==id}),project.activities.indices.contains(i+delta) else {return}
        project.activities.swapAt(i,i+delta);changed()
    }
    func chooseConverter() {
        let p=NSOpenPanel(); p.message="اختر ملف soffice التنفيذي داخل LibreOffice/Contents/MacOS"; p.canChooseDirectories=false
        if p.runModal() == .OK,let u=p.url {
            guard FileManager.default.isExecutableFile(atPath:u.path),u.lastPathComponent=="soffice" else { error="اختر الملف التنفيذي soffice"; return }
            UserDefaults.standard.set(u.path,forKey:"converter"); objectWillChange.send()
        }
    }
}
