import AppKit
import SwiftUI
import PDFKit

// This is the entire input available to the audience view. No project, store,
// library, evidence, editing actions, or trainer sheets can enter its view tree.
@MainActor final class SharedPresentation:ObservableObject {
    @Published fileprivate(set) var document:PDFDocument?
    @Published fileprivate(set) var page=0
    @Published fileprivate(set) var timer:String?
    @Published private(set) var preparedImage:CGImage?
    @Published private(set) var preparedPage:Int?
    func accept(_ image:CGImage,page:Int,document:PDFDocument) {
        guard self.document === document,self.page==page else {return}
        preparedPage=page;preparedImage=image
    }
    func clearPrepared() {preparedImage=nil;preparedPage=nil}
}
final class AudienceWindow:NSWindow {
    // Keep SwiftUI's trainer scene as the main window, including when the
    // audience is key. Standard window buttons and native fullscreen still work.
    override var canBecomeMain:Bool {false}
}
@MainActor final class SharingSession:NSObject,ObservableObject,NSWindowDelegate {
    static let audienceTitle="Smart Training Presenter — Shared Presentation"
    static let trainerTitle="Smart Training Presenter — Trainer"
    @Published private(set) var isOpen=false
    @Published var preferences=SharePreferences.load()
    let presentation=SharedPresentation()
    weak var store:PresenterStore?
    private(set) var window:NSWindow?
    let windowState=PresenterWindowState()
    private var selectedMaterialID:String?
    private var epoch:UUID?
    private var displayObserver:NSObjectProtocol?
    private var activityToken:NSObjectProtocol?
    private var placed=false
    private var zoomRestoreFrame:NSRect?
    private var lastAudienceFrame:NSRect?
    #if !TESTING
    let controls=SharingControlPanel()
    #endif
    func showControls() {
        #if !TESTING
        if let store=store {controls.show(store)}
        #endif
    }
    private func hideControls() {
        #if !TESTING
        controls.close()
        #endif
    }
    @objc func zoomAudience(_ sender:Any?) {toggleMaximize()}
    func toggleMaximize() {
        guard let window=window,!window.styleMask.contains(.fullScreen) else {return}
        if let frame=zoomRestoreFrame {zoomRestoreFrame=nil;window.setFrame(frame,display:true);window.orderFront(nil)}
        else {zoomRestoreFrame=window.frame;maximize()}
    }
    @Published private(set) var screenCount=NSScreen.screens.count
    var effectiveMode:SharingMode {preferences.mode == .single || screenCount<2 ? .single:.dual}
    func setMode(_ mode:SharingMode) {preferences.mode=mode;configureDisplay(place:true);save()}
    func configureDisplay(place:Bool) {
        screenCount=NSScreen.screens.count
        guard let window=window else {return}
        let single=effectiveMode == .single
        if single && window.styleMask.contains(.fullScreen) {window.toggleFullScreen(nil);return}
        window.collectionBehavior=single ? [.managed,.fullScreenNone]:[.managed,.fullScreenPrimary]
        window.standardWindowButton(.miniaturizeButton)?.isEnabled=false
        // Keep the capture surface alive; hiding the app can still hide windows.
        window.hidesOnDeactivate=false;window.canHide=false
        guard place,!window.styleMask.contains(.fullScreen),let primary=NSScreen.screens.first else {return}
        if !single,let trainer=NSApp.windows.first(where:{$0.title==Self.trainerTitle}),!trainer.styleMask.contains(.fullScreen),!primary.frame.contains(NSPoint(x:trainer.frame.midX,y:trainer.frame.midY)) {
            var frame=trainer.frame;frame.size.width=min(frame.width,primary.visibleFrame.width);frame.size.height=min(frame.height,primary.visibleFrame.height);frame.origin=primary.visibleFrame.origin
            trainer.setFrame(frame,display:true)
        }
        let target=single ? primary:(NSScreen.screens.dropFirst().first ?? primary)
        let area=target.visibleFrame
        // Keep this window's geometry. Trainer layout, timer ticks and focus
        // changes never set the audience frame. Relocate only when necessary.
        if !placed,let saved=lastAudienceFrame {window.setFrame(saved,display:false)}
        let needsPlacement = !placed || window.screen !== target || !area.intersects(window.frame)
        if needsPlacement {
            let size=NSSize(width:min(window.frame.width,area.width),height:min(window.frame.height,area.height))
            window.setFrame(NSRect(x:area.midX-size.width/2,y:area.midY-size.height/2,width:size.width,height:size.height),display:true)
        }
        placed=true
        if single {showControls()} else {hideControls()}

    }
    func windowDidExitFullScreen(_ notification:Notification) {configureDisplay(place:true);refreshSurface()}
    func maximize() {
        guard let window=window,!window.styleMask.contains(.fullScreen),let area=window.screen?.visibleFrame else {return}
        if window.isMiniaturized {window.deminiaturize(nil)}
        window.setFrame(area,display:true);window.orderFront(nil)
    }
    func showTrainer() {
        guard let trainer=NSApp.windows.first(where:{$0.title==Self.trainerTitle}) else {return}
        if trainer.isMiniaturized {trainer.deminiaturize(nil)}
        trainer.makeKeyAndOrderFront(nil)
    }
    func windowDidChangeOcclusionState(_ notification:Notification) {refreshSurface()}
    func windowDidDeminiaturize(_ notification:Notification) {refreshSurface()}
    func windowDidMiniaturize(_ notification:Notification) {
        // A minimized window has no reliable capture surface. Restore our own
        // audience window rather than allowing a silently frozen/black share.
        DispatchQueue.main.async {[weak self] in self?.window?.deminiaturize(nil);self?.refreshSurface()}
    }
    private func refreshSurface() {
        func refresh(_ view:NSView) {if let canvas=view as? SharedSlideView {canvas.refreshBacking()};view.subviews.forEach(refresh)}
        if let view=window?.contentView {refresh(view);view.displayIfNeeded()}
    }
    func attach(_ store:PresenterStore) {self.store=store}
    func save() {
        do {
            try FileManager.default.createDirectory(at:SharePreferences.url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(preferences).write(to:SharePreferences.url,options:.atomic)
        } catch {store?.error="تعذر حفظ تفضيلات المشاركة: "+error.localizedDescription}
    }
    private func reset() {presentation.clearPrepared();presentation.document=nil;presentation.page=0;presentation.timer=nil;selectedMaterialID=nil}
    func open() {
        if let window=window {
            windowState.attach(window);window.makeKeyAndOrderFront(nil);isOpen=true;tick(continuousSeconds());return
        }
        guard let store=store else {return}
        epoch=store.projectEpoch;reset()
        // Opening the sharing window is the explicit consent for an otherwise
        // unclassified presentation. A private source preview never grants it.
        if !store.privatePreview,let m=store.material,Self.role(m)==nil {selectedMaterialID=m.id}
        let newWindow=AudienceWindow(contentRect:NSRect(x:0,y:0,width:960,height:700),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        newWindow.title=Self.audienceTitle;newWindow.isReleasedWhenClosed=false;newWindow.delegate=self
        newWindow.collectionBehavior=[.managed,.fullScreenNone];newWindow.minSize=NSSize(width:420,height:360)
        newWindow.sharingType = .readOnly
        #if TESTING
        newWindow.contentView=NSView()
        #else
        newWindow.contentView=NSHostingView(rootView:SharedPresentationView(presentation:presentation))
        #endif
        newWindow.standardWindowButton(.zoomButton)?.target=self
        newWindow.standardWindowButton(.zoomButton)?.action=#selector(zoomAudience(_:))
        newWindow.standardWindowButton(.zoomButton)?.isEnabled=true
        window=newWindow;placed=false;zoomRestoreFrame=nil;isOpen=true;tick(continuousSeconds());windowState.attach(newWindow);configureDisplay(place:true)
        activityToken=ProcessInfo.processInfo.beginActivity(options:[.userInitiatedAllowingIdleSystemSleep],reason:"عرض حقيبة تدريبية في نافذة المشاركة")
        displayObserver=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {self?.configureDisplay(place:true);self?.refreshSurface()}
        }
        newWindow.makeKeyAndOrderFront(nil)
    }
    func close() {window?.close()}
    func windowWillClose(_ notification:Notification) {
        if let observer=displayObserver {NotificationCenter.default.removeObserver(observer);displayObserver=nil}
        if let token=activityToken {ProcessInfo.processInfo.endActivity(token);activityToken=nil}
        lastAudienceFrame=window?.frame;hideControls();placed=false;zoomRestoreFrame=nil
        isOpen=false;reset();window=nil;save()
    }
    static func role(_ material:Material)->String? {
        // A known private filename is private even if stale metadata says slides.
        let nameRole=TrainingLibrary.role(material.name)
        if ["trainer","learner"].contains(nameRole ?? "") {return nameRole}
        return material.libraryRole ?? nameRole
    }
    func tick(_ now:Double) {
        guard isOpen,let store=store else {return}
        if epoch != store.projectEpoch {reset();epoch=store.projectEpoch}
        if let selected=selectedMaterialID,!store.project.materials.contains(where:{$0.id==selected}) {reset()}
        if !store.privatePreview,let material=store.material,let document=store.document {
            let role=Self.role(material)
            if role=="slides" || (role==nil && material.id==selectedMaterialID) {
                if presentation.document !== document {presentation.document=document}
                let page=max(0,min(store.project.currentPage,document.pageCount-1))
                if presentation.page != page {presentation.page=page}
                selectedMaterialID=material.id
            }
        }
        // Sharing the activity clock is opt-in. The private free timer and
        // unapproved activities never become audience content.
        let visible=preferences.showTimer && !store.freeMode && store.current?.approved==true && store.current?.kind=="نشاط"
        let remaining=store.timer.remaining(now)
        let value=visible ? timeText(preferences.showOvertime ? remaining:max(0,remaining)):nil
        if presentation.timer != value {presentation.timer=value}
    }
}
