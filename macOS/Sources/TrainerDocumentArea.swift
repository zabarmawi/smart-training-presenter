import SwiftUI
import AppKit
import PDFKit

// During public presentation both windows reuse the exact same prepared pixels.
// Private guides/source previews keep PDFView and never enter this branch.
struct TrainerDocumentArea:View {
    @ObservedObject var store:PresenterStore
    @ObservedObject var sharing:SharingSession
    let fillViewport:Bool
    var body:some View {
        Group {
            if sharing.isOpen,!store.privatePreview,sharing.presentation.document === store.document {
                PreparedTrainerPreview(presentation:sharing.presentation,fillViewport:fillViewport)
            } else {
                PDFCanvas(document:store.document,page:store.project.currentPage,fillViewport:fillViewport){i in
                    if i != store.project.currentPage {store.navigate(i)}
                }
            }
        }
    }
}
struct PreparedTrainerPreview:View {
    @ObservedObject var presentation:SharedPresentation
    @ObservedObject var appearance=UIAppearance.shared
    let fillViewport:Bool
    var body:some View {
        ZStack {
            PreparedFrameCanvas(image:presentation.preparedImage,surround:appearance.theme.surround,fill:fillViewport)
            if presentation.preparedImage==nil {Text("تجهيز الشريحة…").foregroundColor(.white)}
        }
    }
}
struct PreparedFrameCanvas:NSViewRepresentable {
    let image:CGImage?
    let surround:NSColor
    let fill:Bool
    final class Canvas:NSView {
        var image:CGImage? {didSet {if image !== oldValue {needsDisplay=true}}}
        var surround:NSColor = .darkGray {didSet {if surround != oldValue {needsDisplay=true}}}
        var fill=false {didSet {if fill != oldValue {needsDisplay=true}}}
        override var isOpaque:Bool {true}
        override func setFrameSize(_ size:NSSize) {let changed=frame.size != size;super.setFrameSize(size);if changed {needsDisplay=true}}
        override func draw(_ dirtyRect:NSRect) {
            surround.setFill();bounds.fill()
            guard let image=image,let context=NSGraphicsContext.current?.cgContext else {return}
            let x=bounds.width/CGFloat(image.width),y=bounds.height/CGFloat(image.height),scale=fill ? max(x,y):min(x,y)
            let w=CGFloat(image.width)*scale,h=CGFloat(image.height)*scale
            context.draw(image,in:NSRect(x:(bounds.width-w)/2,y:(bounds.height-h)/2,width:w,height:h))
        }
    }
    func makeNSView(context:Context)->Canvas {Canvas(frame:.zero)}
    func updateNSView(_ view:Canvas,context:Context) {view.image=image;view.surround=surround;view.fill=fill}
}
