import SwiftUI
import AppKit

// A visible hint in private chrome, not an OS tooltip whose display may be
// suppressed by frequent SwiftUI updates. No hint view enters the audience tree.
@MainActor final class TrainerHoverHelp:ObservableObject {
    @Published private(set) var text=""
    private var owner:UUID?
    func enter(_ text:String,owner:UUID) {self.owner=owner;self.text=text}
    func exit(owner:UUID) {if self.owner==owner {self.owner=nil;text=""}}
}
final class HelpTrackingView:NSView {
    let token=UUID()
    var helpText=""
    var hub:TrainerHoverHelp?
    private var area:NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area=area {removeTrackingArea(area)}
        let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(next);area=next
    }
    override func mouseEntered(with event:NSEvent) {hub?.enter(helpText,owner:token)}
    override func mouseExited(with event:NSEvent) {hub?.exit(owner:token)}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow();window?.acceptsMouseMovedEvents=true}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    override func viewWillMove(toWindow newWindow:NSWindow?) {if newWindow==nil {hub?.exit(owner:token)};super.viewWillMove(toWindow:newWindow)}
}
struct HelpTrackingProbe:NSViewRepresentable {
    let text:String
    let hub:TrainerHoverHelp
    func makeNSView(context:Context)->HelpTrackingView {let v=HelpTrackingView();v.helpText=text;v.hub=hub;return v}
    func updateNSView(_ view:HelpTrackingView,context:Context) {view.helpText=text;view.hub=hub}
}
struct TrainerHelpModifier:ViewModifier {
    @EnvironmentObject var hub:TrainerHoverHelp
    let text:String
    @State private var token=UUID()
    func body(content:Content)->some View {
        content.help(text).accessibilityLabel(text)
            .onHover {inside in if inside {hub.enter(text,owner:token)} else {hub.exit(owner:token)}}
            .background(HelpTrackingProbe(text:text,hub:hub))
    }
}
extension View {func trainerHelp(_ text:String)->some View {modifier(TrainerHelpModifier(text:text))}}
struct TrainerHelpBar:View {
    @EnvironmentObject var hub:TrainerHoverHelp
    var body:some View {
        Text(hub.text.isEmpty ? "مرّر المؤشر على أيقونة لعرض تلميحها هنا":hub.text)
            .font(.system(size:12,weight:hub.text.isEmpty ? .regular:.semibold))
            .foregroundColor(hub.text.isEmpty ? .secondary:.primary)
            .frame(maxWidth:.infinity,alignment:.leading).frame(height:24)
            .padding(.horizontal,12).background(Color.primary.opacity(0.045))
            .accessibilityIdentifier("visibleTrainerTooltip")
    }
}
