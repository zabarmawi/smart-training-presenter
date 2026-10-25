import Foundation
import PDFKit

extension PresenterStore {
    func retryPresentation(_ id:String) {
        guard !busy,let material=project.materials.first(where:{$0.id==id}) else {return}
        busy=true;let epoch=projectEpoch
        Task {
            let result=await Task.detached {Result { () -> (String,Int) in
                let source=URL(fileURLWithPath:material.path)
                guard try DocumentReader.digest(source)==material.hash else {throw PresenterError.message("تغيّر المصدر؛ أعد قراءته وراجع التغييرات قبل العرض")}
                let converted=try DocumentReader.convert(source,hash:material.hash)
                return (converted.path,PDFDocument(url:converted)?.pageCount ?? 0)
            }}.value
            guard projectEpoch==epoch else {return};busy=false
            switch result {
            case .success(let output):
                if let index=project.materials.firstIndex(where:{$0.id==id}) {project.materials[index].renderedPath=output.0;project.materials[index].pages=output.1;project.materials[index].status="عرض ثابت محوّل؛ بلا حركات أو فيديو";if project.currentFile==id {loadDisplay()};changed()}
            case .failure(let e):error=e.localizedDescription
            }
        }
    }
}
