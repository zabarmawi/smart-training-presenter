import AppKit
import SwiftUI
import PDFKit
import QuartzCore

// Own a durable raster for the selected PDF page. WindowServer can retain these
// layer contents even while AppKit skips draw callbacks for an occluded window.
// It does not prove that a third-party capture client captures the window.
final class SharedSlideView:NSView {
    var sourceDocument:PDFDocument? {didSet {if sourceDocument !== oldValue {renderer.setSource(sourceDocument);lastInstalledPage=nil}}}
    private let renderer=PageRasterService()
    var onRaster:((CGImage,Int,PDFDocument)->Void)?
    private(set) var lastInstalledPage:Int?
    private(set) var renderSamples:[[String:Any]]=[]
    private(set) var installCount=0
    private(set) var refreshCount=0
    private(set) var drawCount=0
    private(set) var retainedImage:CGImage?
    private let pageLayer=CALayer()
    var surround:NSColor=PresenterTheme.light.surround {didSet {layer?.backgroundColor=surround.cgColor;needsDisplay=true}}
    var page:PDFPage? {didSet {if page !== oldValue {renderPage()}}}
    override var isOpaque:Bool {true}
    override init(frame:NSRect) {
        super.init(frame:frame);wantsLayer=true
        layer?.backgroundColor=surround.cgColor
        pageLayer.contentsGravity = .resizeAspect;pageLayer.isOpaque=false
        layer?.addSublayer(pageLayer)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    private func renderPage() {
        guard let page=page,let document=sourceDocument else {retainedImage=nil;pageLayer.contents=nil;lastInstalledPage=nil;needsDisplay=true;return}
        let index=document.index(for:page),start=ProcessInfo.processInfo.systemUptime
        guard index != NSNotFound else {return}
        renderer.render(index) {[weak self,weak document,weak page] result in
            guard let self=self,self.sourceDocument === document,self.page === page else {return}
            self.retainedImage=result.image;self.lastInstalledPage=index;self.installCount+=1
            self.refreshBacking();self.needsDisplay=true
            if let document=document {self.onRaster?(result.image,index,document)}
            self.renderSamples.append(["page":index+1,"cached":result.cached,"raster_ms":result.rasterMS,"request_to_layer_ms":(ProcessInfo.processInfo.systemUptime-start)*1000])
            if self.renderSamples.count>100 {self.renderSamples.removeFirst()}
        }
    }
    func refreshBacking() {
        let sameImage=(pageLayer.contents as AnyObject?) === retainedImage
        guard pageLayer.frame != bounds || !sameImage || layer?.backgroundColor != surround.cgColor else {return}
        refreshCount+=1
        CATransaction.begin();CATransaction.setDisableActions(true)
        pageLayer.contents=retainedImage;pageLayer.frame=bounds;layer?.backgroundColor=surround.cgColor
        CATransaction.commit()
    }
    override func layout() {super.layout();refreshBacking()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow();refreshBacking()}
    override func setFrameSize(_ size:NSSize) {let changed=frame.size != size;super.setFrameSize(size);refreshBacking();if changed {needsDisplay=true}}
    override func draw(_ dirtyRect:NSRect) {
        drawCount+=1
        surround.setFill();bounds.fill()
        guard let image=retainedImage,let context=NSGraphicsContext.current?.cgContext else {return}
        let scale=min(bounds.width/CGFloat(image.width),bounds.height/CGFloat(image.height))
        let size=NSSize(width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
        context.draw(image,in:NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height))
    }
}
struct SharedSlideCanvas:NSViewRepresentable {
    let document:PDFDocument
    let page:Int
    var surround:NSColor=PresenterTheme.light.surround
    var onRaster:((CGImage,Int,PDFDocument)->Void)? = nil
    func makeNSView(context:Context)->SharedSlideView {SharedSlideView(frame:.zero)}
    func updateNSView(_ view:SharedSlideView,context:Context) {
        view.onRaster=onRaster
        view.sourceDocument=document
        let target=document.page(at:page)
        if view.page !== target {view.page=target}
        if view.surround != surround {view.surround=surround}
    }
}
