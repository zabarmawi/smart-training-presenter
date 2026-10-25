import Foundation
import AppKit
import PDFKit

struct RevisionProposal {
    var referenceHash:String
    var pageMap:[String:Int]
    var changedPages:[Int]
    var message:String
}
struct DocumentRevision {
    static func signature(_ page:PDFPage)->[UInt8] {
        let image=page.thumbnail(of:NSSize(width:160,height:120),for:.cropBox)
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),let context=CGContext(data:nil,width:24,height:16,bitsPerComponent:8,bytesPerRow:24,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) else {return []}
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:24,height:16));context.draw(cg,in:CGRect(x:0,y:0,width:24,height:16))
        return Array(UnsafeBufferPointer(start:context.data!.assumingMemoryBound(to:UInt8.self),count:384))
    }
    static func suggest(_ current:[[UInt8]],references:[String:[[UInt8]]])->RevisionProposal? {
        var proposals:[(Double,RevisionProposal)]=[]
        for (hash,pages) in references where pages.count>=3 && abs(pages.count-current.count)<=5 {
            var map:[String:Int]=[:];var last = -1
            for (index,reference) in pages.enumerated() where !reference.isEmpty {
                var best:(Double,Int)?
                for j in max(last+1,max(0,index-5))..<min(current.count,index+6+max(0,current.count-pages.count)) {
                    guard current[j].count==reference.count else {continue}
                    let distance=zip(current[j],reference).reduce(0.0){$0+abs(Double($1.0)-Double($1.1))}/Double(reference.count)
                    if best==nil || distance<best!.0 {best=(distance,j)}
                }
                if let best=best,best.0<=1.2 {map[String(index+1)]=best.1+1;last=best.1}
            }
            let ratio=Double(map.count)/Double(max(pages.count,current.count))
            guard ratio>=0.90 else {continue}
            let matched=Set(map.values)
            let changed=(1...current.count).filter{!matched.contains($0)}
            let message=changed.isEmpty ? "تغيّر الملف، وتطابقت صفحات العرض بصريًا مع نسخة معروفة. الأزمنة والروابط مقترحة للمراجعة؛ لم تُعتمد تلقائيًا":"نسخة معدلة: الصفحات غير المطابقة هي "+changed.map(String.init).joined(separator:"، ")+". راجع نطاقات الأنشطة قبل الاعتماد"
            proposals.append((ratio,RevisionProposal(referenceHash:hash,pageMap:map,changedPages:changed,message:message)))
        }
        let sorted=proposals.sorted{$0.0>$1.0}
        // Ambiguous matches to different reference versions stay unrecognized.
        if sorted.count>1,abs(sorted[0].0-sorted[1].0)<0.02 {return nil}
        return sorted.first?.1
    }
    static func inspect(_ url:URL,material:inout Material) {
        guard material.referenceHash==nil,let c=ReferenceCatalog.load(),c.fingerprints[material.hash]==nil,let reference=c.visualSignatures,!reference.isEmpty,
              let d=PDFDocument(url:url),d.pageCount>=3,d.pageCount<=2000 else {return}
        if let proposal=suggest((0..<d.pageCount).map{signature(d.page(at:$0)!)},references:reference) {
            material.referenceHash=proposal.referenceHash;material.referencePageMap=proposal.pageMap;material.versionNote=proposal.message
        }
    }
}
