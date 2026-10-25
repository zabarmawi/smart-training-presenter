import AppKit
import PDFKit

// Serial, independent PDFDocument: never render the trainer's live PDFDocument
// from another thread. The cache is bounded and belongs to one audience canvas.
final class PageRasterService {
    struct Result {let image:CGImage;let cached:Bool;let rasterMS:Double}
    private final class Entry {let image:CGImage;init(_ image:CGImage){self.image=image}}
    private let queue=DispatchQueue(label:"presenter.audience.raster",qos:.userInitiated)
    private let lock=NSLock()
    private var epoch=UUID()
    private var request=0
    private var document:PDFDocument?
    private let cache=NSCache<NSString,Entry>()
    init() {cache.totalCostLimit=96*1024*1024;cache.countLimit=5}
    private func valid(_ token:UUID,_ serial:Int?=nil)->Bool {
        lock.lock();defer {lock.unlock()};return epoch==token && (serial==nil || serial==request)
    }
    func setSource(_ source:PDFDocument?) {
        let url=source?.documentURL
        let data=url==nil ? source?.dataRepresentation():nil
        lock.lock();epoch=UUID();request+=1;let token=epoch;lock.unlock()
        queue.async {[self] in
            guard valid(token) else {return}
            cache.removeAllObjects();document=url.flatMap{PDFDocument(url:$0)} ?? data.flatMap{PDFDocument(data:$0)}
        }
    }
    private func raster(_ index:Int,token:UUID)->Result? {
        let key=(token.uuidString+"/"+String(index)) as NSString
        if let value=cache.object(forKey:key) {return Result(image:value.image,cached:true,rasterMS:0)}
        guard let page=document?.page(at:index) else {return nil}
        let start=ProcessInfo.processInfo.systemUptime,box=page.bounds(for:.cropBox)
        let scale=min(2.0,2560/max(1,max(box.width,box.height)))
        let image=page.thumbnail(of:NSSize(width:max(1,box.width*scale),height:max(1,box.height*scale)),for:.cropBox)
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else {return nil}
        cache.setObject(Entry(cg),forKey:key,cost:cg.bytesPerRow*cg.height)
        return Result(image:cg,cached:false,rasterMS:(ProcessInfo.processInfo.systemUptime-start)*1000)
    }
    private func prefetch(_ index:Int,token:UUID,serial:Int) {
        for next in [index+1,index+2] {
            guard valid(token,serial) else {break}
            autoreleasepool {_=raster(next,token:token)}
        }
    }
    func render(_ index:Int,completion:@escaping(Result)->Void) {
        lock.lock();request+=1;let serial=request,token=epoch;lock.unlock()
        let key=(token.uuidString+"/"+String(index)) as NSString
        // NSCache is thread-safe. A ready frame must not wait behind a slow
        // read-ahead job on the PDF worker queue.
        if let entry=cache.object(forKey:key),valid(token,serial) {
            DispatchQueue.main.async {[self] in if valid(token,serial) {completion(Result(image:entry.image,cached:true,rasterMS:0))}}
            queue.async {[self] in prefetch(index,token:token,serial:serial)}
            return
        }
        queue.async {[self] in
            guard valid(token,serial),let result=raster(index,token:token),valid(token,serial) else {return}
            DispatchQueue.main.async {[self] in if valid(token,serial) {completion(result)}}
            prefetch(index,token:token,serial:serial)
        }
    }
}
