import Foundation
import PDFKit

struct PreparedBag {var project:Project;var report:GuideResult}
struct LibraryPreparation {
    static func prepare(_ bag:LibraryBag,in library:TrainingLibrary,previous:Project?=nil) throws -> PreparedBag {
        guard bag.complete else {throw PresenterError.message("تحتاج الحقيبة عرضًا واحدًا ودليل مدرب ودليل متدرب")}
        var materials:[Material]=[]
        for file in bag.files {
            let url=library.url(file)
            let hash=try DocumentReader.digest(url)
            guard hash==file.hash,let pdf=PDFDocument(url:url),!pdf.isLocked,pdf.pageCount>0 else {throw PresenterError.message("تغيّر أو تعذر فتح "+url.lastPathComponent+"؛ حدّث المكتبة")}
            var m=Material(id:"library:"+bag.id+":"+file.role,path:url.path,hash:hash,renderedPath:url.path,pages:pdf.pageCount,status:file.role=="slides" ? "عرض الحقيبة":"دليل مرجعي",sourceGroup:bag.id)
            m.libraryRole=file.role;materials.append(m)
        }
        let trainer=materials.first{$0.libraryRole=="trainer"}!,slides=materials.first{$0.libraryRole=="slides"}!,learner=materials.first{$0.libraryRole=="learner"}!
        let report=GuideReader.read(trainer:trainer,slides:slides,learner:learner)
        var project=Project();project.name=bag.displayTitle;project.libraryBagID=bag.id;project.materials=materials;project.currentFile=slides.id
        if let reference=ReferenceCatalog.activities(material:slides) {project.activities=reference}
        else {project.activities=report.activities}
        ReferenceCatalog.bindEvidence(in:&project)
        if let old=previous {
            project.preferences=old.preferences;project.currentPage=min(old.currentPage,max(0,slides.pages-1));project.currentActivity=old.currentActivity;project.freeTimer=old.freeTimer;project.freeTimer.pause(continuousSeconds());project.timers=old.timers
            let unchanged=old.materials.allSatisfy{m in materials.contains{$0.id==m.id && $0.hash==m.hash}}
            for i in project.activities.indices {
                guard let prior=old.activities.first(where:{$0.id==project.activities[i].id}) else {continue}
                let retained=TimeSourcePolicy.retaining(prior,adding:project.activities[i].evidence)
                if unchanged && prior.approved {project.activities[i]=retained;continue}
                project.activities[i].evidence=retained.evidence
                if prior.duration != prior.original {project.activities[i].duration=prior.duration}
                project.activities[i].approved=unchanged && prior.approved
                if prior.startPage != project.activities[i].startPage || prior.endPage != project.activities[i].endPage {
                    project.activities[i].proposedStartPage=project.activities[i].startPage;project.activities[i].proposedEndPage=project.activities[i].endPage
                    project.activities[i].startPage=prior.startPage;project.activities[i].endPage=prior.endPage;project.activities[i].approved=false
                    project.activities[i].mappingNote="تغيّر الربط المقترح؛ احتُفظ بالربط السابق حتى مراجعتك"
                }
            }
            for prior in old.activities where !project.activities.contains(where:{$0.id==prior.id}) {
                var retained=prior
                if !(unchanged && prior.approved) {retained.approved=false}
                retained.mappingNote=(prior.mappingNote.map{$0+"؛ "} ?? "")+"لم يظهر النشاط في القراءة الجديدة؛ احتُفظ بالقيمة والربط والمصادر السابقة للمراجعة"
                project.activities.append(retained)
            }
            for id in project.timers.keys {project.timers[id]?.pause(continuousSeconds())}
        }
        ReferenceCatalog.bindEvidence(in:&project)
        return PreparedBag(project:try project.validated(),report:report)
    }
}
