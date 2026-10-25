import AppKit
import PDFKit

@MainActor enum PowerPointSmoke {
    static var folder=""
    static var lines:[String]=[]
    static func record(_ value:Bool,_ name:String) {lines.append((value ? "PASS: ":"FAIL: ")+name);try? lines.joined(separator:"\n").write(toFile:folder+"/powerpoint-results.txt",atomically:true,encoding:.utf8)}
    static func note(_ text:String) {lines.append(text);try? lines.joined(separator:"\n").write(toFile:folder+"/powerpoint-results.txt",atomically:true,encoding:.utf8)}
    static func wait(_ seconds:Double)async {try? await Task.sleep(nanoseconds:UInt64(seconds*1e9))}
    static func conversion(_ store:PresenterStore,fixture:URL) async throws {
        let before=try DocumentReader.digest(fixture)
        let count=try await Task.detached {try command("/usr/bin/osascript",["-e","with timeout of 5 seconds","-e","tell application id \"com.microsoft.Powerpoint\" to count presentations","-e","end timeout"],timeout:7)}.value
        var cold=false
        if count.status==0 && count.text.trimmingCharacters(in:.whitespacesAndNewlines)=="0" {
            _=try await Task.detached {try command("/usr/bin/osascript",["-e","with timeout of 5 seconds","-e","tell application id \"com.microsoft.Powerpoint\" to quit","-e","end timeout"],timeout:7)}.value
            for _ in 0..<20 {if NSRunningApplication.runningApplications(withBundleIdentifier:PowerPointConversion.identifier).isEmpty {cold=true;break};await wait(0.25)}
        }
        if cold {record(true,"PowerPoint confirmed closed before first conversion")} else {note("NOT TESTED: cold close skipped because readiness/documents did not permit safe quit")}
        let activity=Activity(id:"conversion-test",title:"اختبار استمرار المؤقت أثناء التحويل",kind:"نشاط",original:600,duration:600,approved:true)
        store.project=Project();store.project.activities=[activity];store.project.currentActivity=activity.id;store.project.preferences.sound=false;store.toggle();let anchor=store.timer.anchor,used=store.timer.used(store.now)
        let first=try await Task.detached {try DocumentReader.read(fixture)}.value
        record(first.material.renderedPath != nil && first.material.pages==2,"PPTX conversion succeeds after bounded PowerPoint readiness")
        record(store.timer.running && store.timer.anchor==anchor && store.timer.used(store.now)>used,"main timer and UI continue while conversion worker waits")
        if let path=first.material.renderedPath {
            let url=URL(fileURLWithPath:path),date=try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
            let second=try await Task.detached {try DocumentReader.read(fixture)}.value
            let dateAfter=try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
            record(second.material.renderedPath==path && dateAfter==date,"successful conversion cache prevents duplicate export")
            store.project.materials=[first.material];store.selectFile(first.material.id);await wait(2)
            if let window=NSApp.windows.first(where:{$0.contentView != nil}) {UISmoke.capture(window,folder+"/arabic-conversion.png")}
            // Retry path preserves activities, approvals and timing rather than reimporting.
            let oldIDs=store.project.activities.map(\.id),oldOriginal=store.project.activities.map(\.original)
            store.retryPresentation(first.material.id)
            for _ in 0..<40 {if !store.busy {break};await wait(0.2)}
            record(!store.busy && store.project.activities.map(\.id)==oldIDs && store.project.activities.map(\.original)==oldOriginal && store.project.activities[0].approved,"retry display does not recreate activities or approvals")
        } else {note("DETAIL: "+first.material.status)}
        record(try DocumentReader.digest(fixture)==before,"original Arabic PPTX unchanged")
        if let path=first.material.renderedPath {
            try FileManager.default.removeItem(atPath:path)
            let warm=try await Task.detached {try DocumentReader.read(fixture)}.value
            record(warm.material.renderedPath != nil && warm.material.pages==2,"uncached PowerPoint conversion succeeds while already running")
        }
        let bad=URL(fileURLWithPath:folder).appendingPathComponent("invalid.pptx");try Data("invalid".utf8).write(to:bad)
        let invalid=await Task.detached {try? DocumentReader.read(bad)}.value
        record(invalid==nil,"invalid PPTX rejected without starting export")
        let after=try await Task.detached {try command("/usr/bin/osascript",["-e","with timeout of 5 seconds","-e","tell application id \"com.microsoft.Powerpoint\" to count presentations","-e","end timeout"],timeout:7)}.value
        record(after.status==0 && after.text.trimmingCharacters(in:.whitespacesAndNewlines)=="0","temporary presentation closed after conversion")
    }
}
