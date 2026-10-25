import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers

extension PresenterStore {
    func preserveBeforeReplacing() -> Bool {
        if project.libraryBagID != nil {checkpoint();dirty=false;return true}
        guard dirty else { return true }
        let dialog=NSAlert();dialog.messageText="حفظ الحقيبة الحالية قبل المتابعة؟";dialog.informativeText="ستُستبدل الحقيبة المفتوحة. الملفات الأصلية تبقى في مكانها."
        dialog.addButton(withTitle:"حفظ");dialog.addButton(withTitle:"متابعة دون حفظ");dialog.addButton(withTitle:"إلغاء")
        switch dialog.runModal() {
        case .alertFirstButtonReturn: save();return !dirty
        case .alertSecondButtonReturn:return true
        default:return false
        }
    }
    func newProject() {
        guard preserveBeforeReplacing() else {return}
        checkpoint();projectEpoch=UUID();privatePreview=false;busy=false;project=Project(); projectURL=nil; freeMode=false; proposed=0; document=nil; notice=nil; changed()
    }
    func openPanel() {
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.allowedContentTypes=[UTType(filenameExtension:"stpresenter") ?? .json,UTType(filenameExtension:"stbag") ?? .package]; panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let u=panel.url { open(u) }
    }
    func open(_ url:URL) {
        do {
            let p=try DocumentReader.load(url)
            guard preserveBeforeReplacing() else {return}
            checkpoint();projectEpoch=UUID();privatePreview=false;busy=false;project=p; projectURL=url; freeMode=false; proposed=0; notice=nil; loadDisplay(); dirty=false
            applyReference()
            checkChanges(); checkpoint()
        } catch { self.error=error.localizedDescription }
    }
    func checkChanges() {
        let files=project.materials;let epoch=projectEpoch
        Task {
            let changes=await Task.detached { files.compactMap { m -> String? in
                guard let hash=try? DocumentReader.digest(URL(fileURLWithPath:m.path)) else { return m.id }
                return hash==m.hash ? nil:m.id
            }}.value
            guard projectEpoch==epoch else {return}
            if !changes.isEmpty {
                for i in project.activities.indices where project.activities[i].evidence.contains(where:{changes.contains($0.fileID)}) || ReferenceCatalog.affected(project.activities[i],by:files.filter{changes.contains($0.id)}) {
                    project.activities[i].approved=false
                    project.timers[project.activities[i].id]?.pause(now)
                }
                for i in project.materials.indices where changes.contains(project.materials[i].id) {
                    project.materials[i].status="المصدر مفقود أو تغيّر؛ أعد التحليل وراجع القيم قبل الاعتماد"
                }
                error="تغيّر أو فُقد \(changes.count) ملف. احتُفظ بالقيم اليدوية، وأُلغي اعتماد الأنشطة المتأثرة حتى المراجعة. استخدم إعادة التحليل لتحديث الأدلة"; changed()
            }
        }
    }
    func save(asNew:Bool=false) {
        var url=asNew ? nil:projectURL
        if url==nil {
            let p=NSSavePanel(); p.allowedContentTypes=[UTType(filenameExtension:"stpresenter") ?? .json]; p.nameFieldStringValue=project.name+".stpresenter"
            if p.runModal() == .OK { url=p.url }
        }
        guard let u=url else { return }
        do {
            if u.pathExtension=="stbag" {project=try PortableProject.save(project,to:u,now:now);loadDisplay()}
            else {try DocumentReader.save(project,to:u,now:now)}
            projectURL=u;dirty=false;checkpoint()
        }
        catch { self.error=error.localizedDescription }
    }
    func exportPortable() {
        let panel=NSSavePanel();panel.allowedContentTypes=[UTType(filenameExtension:"stbag") ?? .package];panel.nameFieldStringValue=project.name+".stbag"
        guard panel.runModal() == .OK,let url=panel.url else {return}
        let snapshot=project;let epoch=projectEpoch;let timestamp=now;busy=true
        Task {
            let result=await Task.detached {Result {try PortableProject.save(snapshot,to:url,now:timestamp)}}.value
            guard projectEpoch==epoch else {return}
            busy=false
            switch result {
            case .success:notice=Notice(text:"حُفظت حقيبة مستقلة قابلة للنقل بجميع ملفاتها: "+url.lastPathComponent,until:continuousSeconds()+8)
            case .failure(let e):error=e.localizedDescription
            }
        }
    }
    func importPanel() {
        let p=NSOpenPanel(); p.allowsMultipleSelection=true; p.canChooseDirectories=false
        if p.runModal() == .OK { importURLs(p.urls) }
    }
    func importURLs(_ urls:[URL],refresh:Bool=false) {
        guard !busy else { return }; busy=true
        let existing=project.materials;let epoch=projectEpoch
        Task {
            let results=await Task.detached { urls.map { url -> Result<ImportResult,Error> in
                Result { try DocumentReader.read(url,existing:existing.first(where:{$0.path==url.path})) }
            }}.value
            guard projectEpoch==epoch else {return}
            var failures:[String]=[]
            for (index,result) in results.enumerated() {
                switch result {
                case .success(let r):
                    if ["pptx","ppt"].contains(URL(fileURLWithPath:r.material.path).pathExtension.lowercased()),r.material.renderedPath==nil {
                        failures.append(r.material.name+": "+r.material.status+" — اختر الملف ثم أعد محاولة العرض دون استيراده مجددًا")
                    }
                    if let i=project.materials.firstIndex(where:{$0.id==r.material.id}) {
                        let previous=project.materials[i]
                        project.materials[i]=r.material
                        if previous.hash != r.material.hash {
                            for j in project.activities.indices where project.activities[j].evidence.contains(where:{$0.fileID==previous.id}) || ReferenceCatalog.affected(project.activities[j],by:[previous]) {
                                project.activities[j].approved=false;project.timers[project.activities[j].id]?.pause(now)
                                if let note=r.material.versionNote {project.activities[j].mappingNote=note}
                            }
                        }
                        if refresh {
                            // Replace evidence from this file without discarding approved/manual durations.
                            for j in project.activities.indices {
                                let had=project.activities[j].evidence.contains {$0.fileID==r.material.id}
                                project.activities[j].evidence.removeAll {$0.fileID==r.material.id}
                                if had { project.activities[j].approved=false }
                            }
                        }
                    } else { project.materials.append(r.material) }
                    TimingExtractor.merge(r.activities,into:&project.activities,materials:project.materials)
                case .failure(let e): failures.append(urls[index].lastPathComponent+": "+e.localizedDescription)
                }
            }
            if project.currentFile==nil,let first=project.materials.first(where:{$0.renderedPath != nil}) { selectFile(first.id) }
            else { loadDisplay() }
            if project.materials.contains(where:{ReferenceCatalog.load()?.fingerprint($0) != nil}) {synchronizeReference()}
            busy=false; changed()
            if !failures.isEmpty { error=failures.joined(separator:"\n") }
        }
    }
}
