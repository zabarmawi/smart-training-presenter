import Foundation
import AppKit
import PDFKit
import Vision

struct TextReadResult:Codable {var pages:[String];var ocrPages:Int;var failedOCRPages:Int}
struct DocumentText {
    static func orderedText(_ page:PDFPage)->String {
        guard let selection=page.selection(for:page.bounds(for:.cropBox)) else {return page.string ?? ""}
        let lines=selection.selectionsByLine().compactMap {s -> (CGRect,String)? in
            guard let text=s.string?.trimmingCharacters(in:.whitespacesAndNewlines),!text.isEmpty else {return nil}
            return (s.bounds(for:page),text)
        }.sorted {abs($0.0.midY-$1.0.midY)>3 ? $0.0.midY>$1.0.midY:$0.0.minX>$1.0.minX}
        var rows:[[(CGRect,String)]]=[]
        for line in lines {
            if let last=rows.last,let anchor=last.first,abs(anchor.0.midY-line.0.midY)<max(3,min(anchor.0.height,line.0.height)*0.4) {rows[rows.count-1].append(line)}
            else {rows.append([line])}
        }
        let rebuilt=rows.map{$0.sorted{$0.0.minX>$1.0.minX}.map(\.1).joined(separator:"\t")}.joined(separator:"\n")
        return rebuilt.isEmpty ? page.string ?? "":rebuilt
    }
    static func recognize(_ page:PDFPage) throws -> String {
        let image=page.thumbnail(of:NSSize(width:1800,height:1400),for:.cropBox)
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else {throw PresenterError.message("تعذر تجهيز الصفحة للقراءة")}
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
        let supported=try request.supportedRecognitionLanguages()
        request.recognitionLanguages=["ar-SA","en-US"].filter{supported.contains($0)}
        request.usesLanguageCorrection=true
        try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request])
        return (request.results ?? []).sorted {a,b in
            abs(a.boundingBox.midY-b.boundingBox.midY)>0.012 ? a.boundingBox.midY>b.boundingBox.midY:a.boundingBox.midX>b.boundingBox.midX
        }.compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
    }
    static func readPDF(_ url:URL,hash:String,allowOCR:Bool=true) throws -> TextReadResult {
        guard let pdf=PDFDocument(url:url),!pdf.isLocked,pdf.pageCount>0,pdf.pageCount<=2000 else {throw PresenterError.message("PDF غير صالح أو مقفل أو يتجاوز 2000 صفحة")}
        let cache=DocumentReader.cache.appendingPathComponent("Text-v3-"+hash+".json")
        if allowOCR,let data=try? Data(contentsOf:cache),let cached=try? JSONDecoder().decode(TextReadResult.self,from:data),cached.pages.count==pdf.pageCount,cached.failedOCRPages==0 {return cached}
        var pages:[String]=[];var ocr=0;var failed=0
        for i in 0..<pdf.pageCount {
            let page=pdf.page(at:i)!
            var text=orderedText(page)
            if text.trimmingCharacters(in:.whitespacesAndNewlines).count<5 && allowOCR && ProcessInfo.processInfo.environment["PRESENTER_DISABLE_OCR"] != "1" {
                do {text=try recognize(page);ocr+=1} catch {failed+=1}
            }
            pages.append(text)
        }
        let result=TextReadResult(pages:pages,ocrPages:ocr,failedOCRPages:failed)
        if allowOCR,failed==0,ProcessInfo.processInfo.environment["PRESENTER_DISABLE_OCR"] != "1" {
            try FileManager.default.createDirectory(at:DocumentReader.cache,withIntermediateDirectories:true)
            try JSONEncoder().encode(result).write(to:cache,options:.atomic)
        }
        return result
    }
}
