import Foundation
import AppKit
import PDFKit

// One export at a time, on the import worker. Originals never reach Office.
enum PowerPointConversion {
    static let lock=NSLock()
    static let identifier="com.microsoft.Powerpoint"
    static func valid(_ url:URL)->Bool {(PDFDocument(url:url)?.pageCount ?? 0)>0}
    static func trace(_ value:String) {
        guard let path=ProcessInfo.processInfo.environment["PRESENTER_CONVERSION_LOG"] else {return}
        let line=Data((ISO8601DateFormatter().string(from:Date())+" "+value+"\n").utf8)
        if !FileManager.default.fileExists(atPath:path) {FileManager.default.createFile(atPath:path,contents:line);return}
        if let handle=FileHandle(forWritingAtPath:path) {defer{try? handle.close()};_=try? handle.seekToEnd();try? handle.write(contentsOf:line)}
    }
    static func script(_ text:String,args:[String],folder:URL,timeout:Double)throws->CommandResult {
        let url=folder.appendingPathComponent(UUID().uuidString+".applescript")
        try text.write(to:url,atomically:true,encoding:.utf8)
        defer {try? FileManager.default.removeItem(at:url)}
        return try command("/usr/bin/osascript",[url.path]+args,timeout:timeout)
    }
    static func ready(folder:URL,attempts:Int=6)throws {
        var last=""
        for _ in 0..<attempts {
            do {
                let result=try script("""
                with timeout of 4 seconds
                    tell application id "com.microsoft.Powerpoint" to get count of presentations
                end timeout
                """,args:[],folder:folder,timeout:6)
                if result.status==0 {trace("AppleEvent responsive");return}
                last=result.text
                if last.contains("-1743") {break}
            } catch {last=error.localizedDescription}
            Thread.sleep(forTimeInterval:0.4)
        }
        trace("readiness failed")
        throw PresenterError.message("لم يصبح PowerPoint جاهزًا. أكمل نافذة الترحيب أو إذن التحكم إن ظهر، ثم أعد محاولة العرض. "+String(last.suffix(200)))
    }
    // Use a stable, unique presentation name only after checking its full path.
    // An active-presentation/index reference can change when the user opens a deck.
    static let findOwned="""
    on findOwned(sourceName, sourceFolder)
        tell application id "com.microsoft.Powerpoint"
            repeat with position from (count of presentations) to 1 by -1
                set candidate to presentation position
                set candidateName to get name of candidate
                set candidatePath to get full name of candidate
                if candidateName is sourceName and candidatePath starts with sourceFolder then return presentation sourceName
            end repeat
        end tell
        return missing value
    end findOwned
    """
    static func cleanup(name:String,officeFolder:URL,scriptFolder:URL)throws {
        let result=try script(findOwned+"\n"+"""
        on run argv
            with timeout of 8 seconds
                set owned to my findOwned(item 1 of argv, item 2 of argv)
                if owned is not missing value then
                    tell application id "com.microsoft.Powerpoint" to close owned saving no
                end if
                if my findOwned(item 1 of argv, item 2 of argv) is not missing value then error "Temporary presentation remains open"
            end timeout
            return "OWNED_CLOSED"
        end run
        """,args:[name,officeFolder.path+"/"],folder:scriptFolder,timeout:10)
        guard result.status==0,result.text.contains("OWNED_CLOSED") else {throw PresenterError.message("لم يغلق PowerPoint العرض المؤقت. ملفات الاختبار محفوظة مؤقتًا، والأصل لم يتغير. "+String(result.text.suffix(180)))}
        trace("owned presentation verified closed")
    }
    static func convert(source:URL,output:URL,folder:URL)throws {
        lock.lock();defer {lock.unlock()}
        if valid(output) {trace("cache hit");return}
        let officeFolder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.microsoft.Powerpoint/Data/tmp/SmartTrainingPresenter-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:officeFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let officeSource=officeFolder.appendingPathComponent(source.lastPathComponent),officePDF=officeFolder.appendingPathComponent("slides.pdf")
        try FileManager.default.copyItem(at:source,to:officeSource)
        var closed=false,opened=false
        defer {
            // Never delete a deck out from under Office if its close failed.
            if closed || !opened {try? FileManager.default.removeItem(at:officeFolder)}
        }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier:identifier).isEmpty
        trace(wasRunning ? "warm conversion":"cold conversion")
        do {
            // LaunchServices opens the specific temporary file with the normal UI.
            // Hidden launch + active presentation did not establish document readiness.
            let launch=try command("/usr/bin/open",["-b",identifier,officeSource.path],timeout:10)
            guard launch.status==0 else {throw PresenterError.message("تعذر فتح النسخة المؤقتة في PowerPoint")}
            opened=true;try ready(folder:folder)
            var last=""
            for attempt in 0..<2 {
                trace("export attempt "+String(attempt+1))
                do {
                    let result=try script(findOwned+"\n"+"""
                    on run argv
                        set owned to missing value
                        repeat 30 times
                            with timeout of 4 seconds
                                set owned to my findOwned(item 3 of argv, item 4 of argv)
                            end timeout
                            if owned is not missing value then exit repeat
                            delay 0.3
                        end repeat
                        if owned is missing value then error "Temporary document not ready; complete any PowerPoint dialog" number -1712
                        with timeout of 45 seconds
                            tell application id "com.microsoft.Powerpoint" to save owned in (POSIX file (item 2 of argv)) as save as PDF
                        end timeout
                        return "EXPORT_RETURNED"
                    end run
                    """,args:[officeSource.path,officePDF.path,source.lastPathComponent,officeFolder.path+"/"],folder:folder,timeout:65)
                    last=result.text
                    if valid(officePDF) {break}
                    if result.status==0 || !last.contains("-1712") {break}
                } catch {last=error.localizedDescription;if valid(officePDF) {break}}
                if attempt==0 {try ready(folder:folder,attempts:2)}
            }
            guard valid(officePDF) else {throw PresenterError.message("تعذر تحويل PowerPoint؛ افتحه وأكمل أي تنبيه ثم أعد محاولة العرض. "+String(last.suffix(240)))}
            try cleanup(name:source.lastPathComponent,officeFolder:officeFolder,scriptFolder:folder);closed=true
            if FileManager.default.fileExists(atPath:output.path) {try FileManager.default.removeItem(at:output)}
            try FileManager.default.copyItem(at:officePDF,to:output)
            trace("PDF verified and committed after close")
        } catch {
            if opened {do {try cleanup(name:source.lastPathComponent,officeFolder:officeFolder,scriptFolder:folder);closed=true} catch {trace("cleanup incomplete; owned directory retained")}}
            // Quit only an app we started and only after confirming no presentations.
            if !wasRunning,closed {
                _=try? script("""
                with timeout of 5 seconds
                    tell application id "com.microsoft.Powerpoint"
                        if count of presentations is 0 then quit
                    end tell
                end timeout
                """,args:[],folder:folder,timeout:7)
            }
            throw error
        }
    }
}
