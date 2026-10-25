import AppKit
import SwiftUI

@MainActor final class SharingControlPanel {
    private(set) var window:NSPanel?
    func show(_ store:PresenterStore) {
        if let window=window {window.orderFrontRegardless();return}
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:650,height:132),styleMask:[.titled,.closable,.utilityWindow,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="Smart Training Presenter — Trainer Controls"
        panel.isReleasedWhenClosed=false;panel.isFloatingPanel=true;panel.level = .floating
        panel.hidesOnDeactivate=false;panel.becomesKeyOnlyIfNeeded=true;panel.sharingType = .none
        panel.collectionBehavior=[.moveToActiveSpace,.fullScreenAuxiliary]
        panel.contentView=NSHostingView(rootView:PrivateShareControls(store:store))
        if let area=NSScreen.screens.first?.visibleFrame {panel.setFrameOrigin(NSPoint(x:area.maxX-panel.frame.width-18,y:area.minY+24))}
        window=panel;panel.orderFrontRegardless()
    }
    func close() {window?.close();window=nil}
}
struct PrivateShareControls:View {
    @ObservedObject var store:PresenterStore
    @StateObject private var hover=TrainerHoverHelp()
    var body:some View {
        VStack(spacing:6) {
            Text(store.freeMode ? "المؤقت الحر":(store.current?.displayTitle ?? "أدوات المدرب الخاصة")).font(.caption).lineLimit(1)
            HStack(spacing:12) {
                Button {store.navigate(store.project.currentPage-1)} label:{Image(systemName:"chevron.right")}.trainerHelp("الشريحة السابقة").accessibilityIdentifier("panelPrevious")
                Button {store.navigate(store.project.currentPage+1)} label:{Image(systemName:"chevron.left")}.trainerHelp("الشريحة التالية").accessibilityIdentifier("panelNext")
                HeaderTimer(store:store)
                Button("+1"){store.proposed=min(1440,store.proposed+1)}.trainerHelp("اقتراح تمديد دقيقة")
                Button("تأكيد",action:store.extend).disabled(store.proposed==0).trainerHelp("تأكيد التمديد المقترح")
                Button("حجم الجمهور",action:store.sharing.toggleMaximize).trainerHelp("تكبير الجمهور أو استعادة حجمه").accessibilityIdentifier("panelZoomAudience")
                Button("المدرب",action:store.sharing.showTrainer).trainerHelp("إظهار نافذة المدرب دون تغيير الجمهور")
            }
            TrainerHelpBar()
        }.padding(10).frame(width:630).environmentObject(hover).presenterTheme().environment(\.layoutDirection,.rightToLeft)
    }
}
