import Foundation

@main struct ConversionFailureTests {
    @MainActor static func main() async throws {
        let folder=URL(fileURLWithPath:CommandLine.arguments[1]),source=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let before=try DocumentReader.digest(source)
        let store=PresenterStore(restore:false)
        store.project.preferences.sound=false
        let activity=Activity(id:"failure-preserved",title:"نشاط معتمد محفوظ",kind:"نشاط",original:900,duration:960,approved:true)
        store.project.activities=[activity];store.selectActivity(activity.id);store.toggle()
        let anchor=store.timer.anchor
        store.importURLs([source])
        for _ in 0..<100 {if !store.busy {break};try? await Task.sleep(nanoseconds:100_000_000)}
        var checks:[String]=[]
        func check(_ value:Bool,_ label:String) {checks.append((value ? "PASS: ":"FAIL: ")+label)}
        check(!store.busy && store.error != nil,"failed external conversion produces visible controller error")
        check(store.project.materials.count==1 && store.project.materials[0].renderedPath==nil,"failed deck remains available for retry")
        check(store.project.activities.contains{$0.id==activity.id && $0.approved && $0.duration==960 && $0.original==900},"import failure preserves existing activity approval and manual duration")
        check(store.timer.running && store.timer.anchor==anchor,"conversion failure never stops active countdown")
        store.error=nil
        if let material=store.project.materials.first {
            let ids=store.project.activities.map(\.id)
            store.retryPresentation(material.id)
            for _ in 0..<100 {if !store.busy {break};try? await Task.sleep(nanoseconds:100_000_000)}
            check(!store.busy && store.error != nil && store.project.activities.map(\.id)==ids,"retry failure remains bounded and creates no duplicate activities")
        }
        check(try DocumentReader.digest(source)==before,"failed converter leaves original fixture unchanged")
        try checks.joined(separator:"\n").write(to:folder.appendingPathComponent("results.txt"),atomically:true,encoding:.utf8)
        print(checks.joined(separator:"\n"));if checks.contains(where:{$0.hasPrefix("FAIL")}) {exit(1)}
    }
}
