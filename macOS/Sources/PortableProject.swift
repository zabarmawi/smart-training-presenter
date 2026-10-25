import Foundation

struct PortableProject {
    static let manifest="project.json"
    static func resolve(_ relative:String,inside root:URL) throws -> String {
        guard !relative.hasPrefix("/"),!relative.contains("\\"),!relative.split(separator:"/").contains("..") else {throw PresenterError.message("مسار غير آمن داخل الحقيبة")}
        var component=root.standardizedFileURL.resolvingSymlinksInPath()
        for piece in relative.split(separator:"/") {
            component.appendPathComponent(String(piece))
            if let attributes=try? FileManager.default.attributesOfItem(atPath:component.path),attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw PresenterError.message("الحقيبة تتضمن رابطًا رمزيًا غير مسموح")
            }
        }
        let path=component.standardizedFileURL.resolvingSymlinksInPath()
        let prefix=root.standardizedFileURL.resolvingSymlinksInPath().path+"/"
        guard path.path.hasPrefix(prefix) else {throw PresenterError.message("يشير مسار الحقيبة إلى ملف خارجها")}
        return path.path
    }
    static func load(_ folder:URL) throws -> Project {
        let url=folder.appendingPathComponent(manifest)
        let data=try Data(contentsOf:url)
        guard data.count<30_000_000 else {throw PresenterError.message("ملف الحقيبة كبير بصورة غير صالحة")}
        var p=try JSONDecoder().decode(Project.self,from:data).validated()
        for i in p.materials.indices {
            p.materials[i].path=try resolve(p.materials[i].path,inside:folder)
            if let rendered=p.materials[i].renderedPath {p.materials[i].renderedPath=try resolve(rendered,inside:folder)}
        }
        return p
    }
    @discardableResult static func save(_ project:Project,to destination:URL,now:Double) throws -> Project {
        let fm=FileManager.default
        let parent=destination.deletingLastPathComponent()
        let staging=parent.appendingPathComponent(".presenter-export-"+UUID().uuidString,isDirectory:true)
        let backup=parent.appendingPathComponent(".presenter-previous-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:staging,withIntermediateDirectories:true)
        defer {try? fm.removeItem(at:staging)}
        var p=project;p.libraryBagID=nil
        for i in p.materials.indices {
            let old=p.materials[i]
            let relative="Materials/\(i)/"+URL(fileURLWithPath:old.path).lastPathComponent
            let output=staging.appendingPathComponent(relative)
            try fm.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
            guard fm.fileExists(atPath:old.path) else {throw PresenterError.message("تعذر تضمين المصدر: "+old.name+". أعد ربطه أولًا")}
            // Freeze the source version and compare the copy. Originals stay untouched.
            let before=try DocumentReader.digest(URL(fileURLWithPath:old.path))
            try fm.copyItem(at:URL(fileURLWithPath:old.path),to:output)
            guard try DocumentReader.digest(output)==before else {throw PresenterError.message("تغير المصدر أثناء التصدير؛ أعد المحاولة")}
            guard before==old.hash else {throw PresenterError.message("تغير المصدر: "+old.name+". راجع التغييرات قبل تصديره")}
            p.materials[i].path=relative
            if let rendered=old.renderedPath {
                if rendered==old.path {p.materials[i].renderedPath=relative}
                else {
                    guard fm.fileExists(atPath:rendered) else {throw PresenterError.message("نسخة العرض مفقودة: "+old.name+". أعد معالجة الملف قبل التصدير")}
                    let preview="Previews/\(i).pdf"
                    try fm.createDirectory(at:staging.appendingPathComponent("Previews"),withIntermediateDirectories:true)
                    try fm.copyItem(at:URL(fileURLWithPath:rendered),to:staging.appendingPathComponent(preview))
                    p.materials[i].renderedPath=preview
                }
            }
        }
        try DocumentReader.save(p,to:staging.appendingPathComponent(manifest),now:now)
        let exists=fm.fileExists(atPath:destination.path)
        if exists {try fm.moveItem(at:destination,to:backup)}
        do {try fm.moveItem(at:staging,to:destination)}
        catch {if exists {try? fm.moveItem(at:backup,to:destination)};throw error}
        if exists {try? fm.removeItem(at:backup)}
        return try load(destination)
    }
}
