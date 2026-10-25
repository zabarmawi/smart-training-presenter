import Foundation
import AppKit
import CoreGraphics
import ImageIO
import PDFKit

// Lossless source-image path for image-only PPTX decks. Reject any unsupported
// shape, crop, rotation or effect rather than silently changing presentation design.
struct ImageDeck {
    static func xml(_ url:URL,_ entry:String) throws -> XMLDocument {
        let r=try command("/usr/bin/unzip",["-p",url.path,entry])
        guard r.status==0 else {throw PresenterError.message("محتوى PPTX غير صالح")}
        return try XMLDocument(xmlString:r.text,options:.nodeLoadExternalEntitiesNever)
    }
    static func first(_ node:XMLNode,_ path:String)->XMLElement? { (try? node.nodes(forXPath:path).first) as? XMLElement }
    static func attr(_ node:XMLElement?,_ name:String)->String? {node?.attribute(forName:name)?.stringValue}
    static func render(_ url:URL,hash:String) throws -> URL? {
        let cached=DocumentReader.cache.appendingPathComponent(hash).appendingPathComponent("images.pdf")
        if let d=PDFDocument(url:cached),d.pageCount>0 {return cached}
        let doc=try xml(url,"ppt/presentation.xml")
        guard let size=first(doc,"//*[local-name()='sldSz']"),let cx=Double(attr(size,"cx") ?? ""),let cy=Double(attr(size,"cy") ?? ""),cx>0,cy>0 else {print("ImageDeck fallback at line \(#line)");return nil}
        let width=cx/12700,height=cy/12700
        let slides=try DocumentReader.slideEntries(url)
        guard !slides.isEmpty,slides.count<=2000 else {print("ImageDeck fallback at line \(#line)");return nil}
        struct Frame {var data:Data;var rect:CGRect}
        var frames:[Frame]=[];var totalBytes=0
        for slide in slides {
            let x=try xml(url,slide)
            guard let tree=first(x,"//*[local-name()='spTree']") else {print("ImageDeck fallback at line \(#line)");return nil}
            let children=(tree.children ?? []).compactMap{$0 as? XMLElement}
            guard children.filter({$0.localName=="pic"}).count==1,
                  children.allSatisfy({["nvGrpSpPr","grpSpPr","pic"].contains($0.localName ?? "")}),
                  (try x.nodes(forXPath:"//*[local-name()='srcRect' or (local-name()='effectLst' and *) or (local-name()='effectDag' and *) or local-name()='timing']")).isEmpty,
                  let pic=children.first(where:{$0.localName=="pic"}),
                  let transform=first(pic,"./*[local-name()='spPr']/*[local-name()='xfrm']"),
                  attr(transform,"rot")==nil,attr(transform,"flipH")==nil,attr(transform,"flipV")==nil,
                  let off=first(transform,"./*[local-name()='off']"),
                  let ext=first(transform,"./*[local-name()='ext']"),
                  let ox=Double(attr(off,"x") ?? ""),let oy=Double(attr(off,"y") ?? ""),
                  let ex=Double(attr(ext,"cx") ?? ""),let ey=Double(attr(ext,"cy") ?? ""),
                  let blip=first(pic,".//*[local-name()='blip']"),
                  let embed=blip.attributes?.first(where:{$0.localName=="embed"})?.stringValue else {print("ImageDeck fallback at line \(#line)");return nil}
            // Only near-full-bleed pictures are eligible; backgrounds may otherwise matter.
            guard abs(ox)<cx*0.01,abs(oy)<cy*0.01,abs(ex-cx)<cx*0.01,abs(ey-cy)<cy*0.01 else {print("ImageDeck fallback at line \(#line)");return nil}
            let rels=try xml(url,"ppt/slides/_rels/"+URL(fileURLWithPath:slide).lastPathComponent+".rels")
            let relations=try rels.nodes(forXPath:"//*[local-name()='Relationship']").compactMap{$0 as? XMLElement}
            guard let relation=relations.first(where:{attr($0,"Id")==embed}),attr(relation,"TargetMode") != "External",
                  let target=attr(relation,"Target"),target.hasPrefix("../media/"),!target.dropFirst(3).contains("..") else {print("ImageDeck fallback at line \(#line)");return nil}
            let entry="ppt/"+target.dropFirst(3)
            // Binary output is redirected to a file to preserve original image bytes.
            let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath:temp.path,contents:nil)
            let handle=try FileHandle(forWritingTo:temp);let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/unzip");p.arguments=["-p",url.path,String(entry)];p.standardOutput=handle;p.standardError=FileHandle.nullDevice
            try p.run();p.waitUntilExit();try handle.close()
            let data=try Data(contentsOf:temp);try? FileManager.default.removeItem(at:temp)
            guard p.terminationStatus==0,data.count<40_000_000,CGImageSourceCreateWithData(data as CFData,nil) != nil else {print("ImageDeck fallback at line \(#line)");return nil}
            totalBytes += data.count
            guard totalBytes < 256_000_000 else {print("ImageDeck fallback at line \(#line)");return nil}
            frames.append(Frame(data:data,rect:CGRect(x:ox/12700,y:height-(oy+ey)/12700,width:ex/12700,height:ey/12700)))
        }
        let folder=DocumentReader.cache.appendingPathComponent(hash)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let output=folder.appendingPathComponent("images.pdf")
        var box=CGRect(x:0,y:0,width:width,height:height)
        guard let ctx=CGContext(output as CFURL,mediaBox:&box,nil) else {throw PresenterError.message("تعذر إنشاء نسخة العرض")}
        for frame in frames {
            guard let source=CGImageSourceCreateWithData(frame.data as CFData,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {print("ImageDeck fallback at line \(#line)");return nil}
            ctx.beginPDFPage(nil);ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(box)
            ctx.interpolationQuality = .high;ctx.draw(image,in:frame.rect);ctx.endPDFPage()
        }
        ctx.closePDF();return output
    }
}
