import SwiftUI
import AppKit

enum ApplicationBuildInfo {
    static var version:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "غير متاح"}
    static var build:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "غير متاح"}
    static let author="إعداد: فهد عبدالله زبرماوي"
    static var architecture:String {
        #if arch(arm64)
        return "ARM64 — Apple Silicon"
        #elseif arch(x86_64)
        return "x86_64 — Mac Intel"
        #else
        return "غير متاح"
        #endif
    }
}
struct AboutApplicationView:View {
    var body:some View {
        GroupBox("حول التطبيق") {
            VStack(alignment:.leading,spacing:6) {
                Text("مشغّل الحقائب التدريبية الذكي").font(.headline)
                Text("الإصدار \(ApplicationBuildInfo.version) · البناء \(ApplicationBuildInfo.build)").accessibilityIdentifier("aboutVersionBuild")
                Text(ApplicationBuildInfo.architecture).font(.caption).accessibilityIdentifier("aboutArchitecture")
                Text(ApplicationBuildInfo.author).accessibilityIdentifier("aboutAuthor")
            }.frame(maxWidth:.infinity,alignment:.leading).padding(6).textSelection(.enabled)
        }.accessibilityIdentifier("aboutApplication")
    }
}
@MainActor enum IdentityAcceptance {
    static var started=false
    static func run(_ store:PresenterStore,args:[String])->Bool {
        guard let i=args.firstIndex(of:"--identity-acceptance"),args.count>i+1 else {return false}
        guard !started else {return true};started=true
        NSApp.accessibilitySetValue(NSNumber(value:true),forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        let output=URL(fileURLWithPath:args[i+1]);try? FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        Task {
            await AcceptanceSmoke.wait(1);store.settings=true;await AcceptanceSmoke.wait(1)
            var results:[String:Bool]=[:]
            results["version read from bundle"] = ApplicationBuildInfo.version == (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            results["build read from bundle"] = ApplicationBuildInfo.build == (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            results["new build"] = ApplicationBuildInfo.build == "13"
            if let window=NSApp.windows.first(where:{$0.title==SharingSession.trainerTitle}),let sheet=window.attachedSheet {
                let nodes=UISmoke.nodes(sheet)
                let text=nodes.flatMap{node in ["accessibilityValue","accessibilityLabel","accessibilityTitle"].compactMap{UISmoke.value(node,$0) as? String}}.joined(separator:" ")
                results["actual Settings About label"] = text.contains("حول التطبيق")
                results["actual Arabic author visible"] = text.contains(ApplicationBuildInfo.author)
                results["actual version visible"] = text.contains(ApplicationBuildInfo.version)
                results["actual build visible"] = text.contains("13")
                results["actual architecture visible"] = text.contains(ApplicationBuildInfo.architecture)
                UISmoke.capture(sheet,output.appendingPathComponent("about-application.png").path)
            } else {results["actual settings sheet"] = false}
            let result:[String:Any] = ["checks":results,"failed":results.filter{!$0.value}.map(\.key),"version":ApplicationBuildInfo.version,"build":ApplicationBuildInfo.build,"architecture":ApplicationBuildInfo.architecture,"method":"Intel validation of shared About code; ARM64 runtime NOT TESTED"]
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("identity-results.json"))}
            store.settings=false;store.checkpoint();NSApp.terminate(nil)
        }
        return true
    }
}
