import AppKit
import SwiftUI

// Each scene owns its window. Never route a trainer action through NSApp.keyWindow:
// the key window may be the audience, a source sheet, or another trainer scene.
@MainActor final class PresenterWindowState:ObservableObject {
    private(set) weak var window:NSWindow?
    @Published private(set) var fullscreen=false
    @Published private(set) var transitioning=false
    @Published private(set) var error:String?
    private var observers:[NSObjectProtocol]=[]
    private var transition=UUID()
    func attach(_ candidate:NSWindow?) {
        guard let candidate=candidate,window !== candidate else {return}
        for item in observers {NotificationCenter.default.removeObserver(item)}
        observers=[];window=candidate
        if candidate.title != SharingSession.audienceTitle {candidate.title=SharingSession.trainerTitle;candidate.sharingType = .none}
        if candidate.title != SharingSession.audienceTitle {
            candidate.collectionBehavior.remove(.fullScreenAuxiliary)
            candidate.collectionBehavior.insert(.fullScreenPrimary)
        }
        fullscreen=candidate.styleMask.contains(.fullScreen)
        for name in [NSWindow.willEnterFullScreenNotification,NSWindow.didEnterFullScreenNotification,NSWindow.willExitFullScreenNotification,NSWindow.didExitFullScreenNotification,NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:candidate,queue:.main){[weak self] notification in
                MainActor.assumeIsolated {
                    guard let self=self else {return}
                    switch notification.name {
                    case NSWindow.willEnterFullScreenNotification,NSWindow.willExitFullScreenNotification:self.beginTransition()
                    case NSWindow.didEnterFullScreenNotification:self.finish(true)
                    case NSWindow.didExitFullScreenNotification:self.finish(false)
                    default:self.finish(false);self.window=nil
                    }
                }
            })
        }
    }
    private func finish(_ value:Bool) {transition=UUID();fullscreen=value;transitioning=false}
    private func beginTransition() {
        transitioning=true;let token=UUID();transition=token
        Task { [weak self] in
            try? await Task.sleep(nanoseconds:12_000_000_000)
            guard let self=self,self.transition==token,self.transitioning else {return}
            self.fullscreen=self.window?.styleMask.contains(.fullScreen)==true;self.transitioning=false
            self.error="لم يكتمل انتقال ملء الشاشة. أغلق أي نافذة حوار مفتوحة ثم أعد المحاولة؛ المؤقت مستمر"
        }
    }
    func toggle() {
        guard let window=window,!transitioning else {return}
        guard !window.collectionBehavior.contains(.fullScreenNone) else {error="استخدم تكبير النافذة في وضع الشاشة الواحدة";return}
        guard window.attachedSheet==nil,NSApp.modalWindow==nil else {error="أغلق نافذة الحوار قبل الانتقال إلى ملء الشاشة";return}
        error=nil
        window.makeKeyAndOrderFront(nil);if window.canBecomeMain {window.makeMain()};NSApp.activate(ignoringOtherApps:true)
        beginTransition();window.toggleFullScreen(nil)
    }
    deinit {for item in observers {NotificationCenter.default.removeObserver(item)}}
}
struct PresenterWindowBinder:NSViewRepresentable {
    let state:PresenterWindowState
    final class Probe:NSView {
        var moved:((NSWindow?)->Void)?
        override func viewDidMoveToWindow() {super.viewDidMoveToWindow();moved?(window)}
    }
    func makeNSView(context:Context)->Probe {
        let view=Probe();view.moved={ [weak state] window in DispatchQueue.main.async {state?.attach(window)}};return view
    }
    func updateNSView(_ view:Probe,context:Context) {DispatchQueue.main.async {state.attach(view.window)}}
}
