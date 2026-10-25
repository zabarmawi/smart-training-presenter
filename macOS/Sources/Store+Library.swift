import Foundation
import AppKit

extension PresenterStore {
    func chooseLibraryFolder() {
        guard !busy else {return}
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false;panel.message="اختر مجلد البرنامج أو المسار؛ تبقى ملفاتك الأصلية في مكانها"
        if panel.runModal() == .OK,let url=panel.url {scanLibrary(url)}
    }
    func scanLibrary(_ url:URL) {
        guard !busy else {return};busy=true;libraryProgress="فحص المجلدات وتحديد ملفات الحقائب…"
        let previous=library;let epoch=projectEpoch
        Task {
            let result=await Task.detached {Result{try TrainingLibrary.scan(url,previous:previous)}}.value
            guard epoch==projectEpoch else {return};busy=false;libraryProgress=""
            switch result {
            case .success(let value):library=value;do {try library.save()} catch {self.error=error.localizedDescription}
            case .failure(let e):error=e.localizedDescription
            }
        }
    }
    func prepareLibraryBag(_ id:String) {
        guard !busy,let bag=library.bags.first(where:{$0.id==id}),preserveBeforeReplacing() else {return}
        checkpoint();busy=true;libraryProgress="قراءة دليل المدرب ومطابقة بطاقات الأنشطة بالجدول والشرائح…"
        let snapshot=library,epoch=projectEpoch
        Task {
            let result=await Task.detached {Result { () -> PreparedBag in
                let previous=try? DocumentReader.load(TrainingLibrary.projectURL(id))
                let prepared=try LibraryPreparation.prepare(bag,in:snapshot,previous:previous)
                try FileManager.default.createDirectory(at:TrainingLibrary.projectURL(id).deletingLastPathComponent(),withIntermediateDirectories:true)
                try DocumentReader.save(prepared.project,to:TrainingLibrary.projectURL(id),now:continuousSeconds())
                return prepared
            }}.value
            guard epoch==projectEpoch else {return};busy=false;libraryProgress=""
            switch result {
            case .success(let prepared):
                guard let i=library.bags.firstIndex(where:{$0.id==id}) else {return}
                library.bags[i].issues=prepared.report.issues;library.bags[i].notesReviewed=false
                library.bags[i].preparedHashes=Dictionary(uniqueKeysWithValues:bag.files.map{($0.role,$0.hash)})
                do {try library.save()} catch {self.error=error.localizedDescription}
                projectEpoch=UUID();privatePreview=false;project=prepared.project;projectURL=TrainingLibrary.projectURL(id);freeMode=false;proposed=0;notice=nil;dirty=false;loadDisplay();libraryVisible=false
                updateLibraryCounts();checkpoint();checkChanges()
                selectedReview=project.currentActivity ?? project.activities.first?.id
                DispatchQueue.main.asyncAfter(deadline:.now()+0.35) {self.review=true}
            case .failure(let e):error=e.localizedDescription
            }
        }
    }
    func openLibraryBag(_ id:String,review:Bool=false,start:Bool=false) {
        guard !busy,let bag=library.bags.first(where:{$0.id==id}) else {return}
        if bag.changed {error="تغيّرت مصادر الحقيبة؛ أعد تحليلها وراجع التغييرات أولًا";return}
        do {
            for file in bag.files {
                guard try DocumentReader.digest(library.url(file))==file.hash else {error="تغيّر أحد المصادر؛ حدّث الفهرس وأعد التحليل قبل التدريب";return}
            }
            guard preserveBeforeReplacing() else {return};checkpoint()
            var p=try DocumentReader.load(TrainingLibrary.projectURL(id))
            for index in p.materials.indices {
                guard let file=bag.files.first(where:{$0.role==p.materials[index].libraryRole}) else {continue}
                let path=library.url(file).path;p.materials[index].path=path;p.materials[index].renderedPath=path
            }
            projectEpoch=UUID();privatePreview=false;project=p;projectURL=TrainingLibrary.projectURL(id);freeMode=false;proposed=0;notice=nil;dirty=false;loadDisplay();checkChanges();libraryVisible=false
            updateLibraryCounts();checkpoint()
            if review {selectedReview=project.currentActivity ?? project.activities.first?.id;DispatchQueue.main.asyncAfter(deadline:.now()+0.35) {self.review=true}}
            if start,let activity=timedActivities.first(where:{$0.id==project.currentActivity && $0.approved}) ?? timedActivities.first(where:{$0.approved}) {beginActivity(activity.id)}
        } catch {self.error="تعذر فتح الحقيبة؛ جهّزها أولًا. "+error.localizedDescription}
    }
    func updateLibraryCounts() {
        guard let id=project.libraryBagID,let i=library.bags.firstIndex(where:{$0.id==id}) else {return}
        let activities=timedActivities
        library.bags[i].activityCount=activities.count;library.bags[i].approvedCount=activities.filter(\.approved).count;library.bags[i].linkedCount=activities.filter{$0.presentationID != nil}.count
    }
    func saveLibraryCheckpoint(flush:Bool=false) throws {
        guard let id=project.libraryBagID,library.bags.contains(where:{$0.id==id}) else {return}
        updateLibraryCounts();try library.save()
        let url=TrainingLibrary.projectURL(id)
        if flush {try libraryRecoveryWriter.flush(project,to:url,now:now)}
        else {libraryRecoveryWriter.schedule(project,to:url,now:now) {[weak self] in self?.error="تعذر حفظ الحقيبة في المكتبة: "+$0}}
    }
}
