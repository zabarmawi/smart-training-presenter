import SwiftUI
import AppKit

// Interface colors only. PDF pixels are never tinted or transformed.
enum PresenterTheme:String,Codable,CaseIterable {
    case light="فاتح", dark="داكن", sand="رملي"
    var darkMode:Bool {self == .dark}
    var background:NSColor {
        switch self {
        case .light:return NSColor(srgbRed:0.95,green:0.96,blue:0.97,alpha:1)
        case .dark:return NSColor(srgbRed:0.12,green:0.13,blue:0.15,alpha:1)
        case .sand:return NSColor(srgbRed:0.94,green:0.90,blue:0.81,alpha:1)
        }
    }
    var panel:NSColor {
        switch self {
        case .light:return .white
        case .dark:return NSColor(srgbRed:0.18,green:0.19,blue:0.21,alpha:1)
        case .sand:return NSColor(srgbRed:0.98,green:0.95,blue:0.88,alpha:1)
        }
    }
    var surround:NSColor {
        switch self {
        case .light:return NSColor(srgbRed:0.28,green:0.31,blue:0.34,alpha:1)
        case .dark:return NSColor(srgbRed:0.09,green:0.10,blue:0.12,alpha:1)
        case .sand:return NSColor(srgbRed:0.39,green:0.35,blue:0.28,alpha:1)
        }
    }
    var text:Color {darkMode ? .white:Color(red:0.10,green:0.11,blue:0.12)}
    var accent:Color {darkMode ? Color(red:0.25,green:0.82,blue:0.80):Color(red:0.0,green:0.40,blue:0.42)}
}
@MainActor final class UIAppearance:ObservableObject {
    static let shared=UIAppearance()
    static var url:URL {DocumentReader.cache.deletingLastPathComponent().appendingPathComponent("UIAppearance.json")}
    @Published var theme:PresenterTheme {didSet {apply();save()}}
    init() {theme=Self.load();apply()}
    private func apply() {NSApp.appearance=NSAppearance(named:theme.darkMode ? .darkAqua:.aqua)}
    static func load()->PresenterTheme {
        guard let data=try? Data(contentsOf:url),data.count<1000,let value=try? JSONDecoder().decode(PresenterTheme.self,from:data) else {return .light}
        return value
    }
    func save() {
        do {try FileManager.default.createDirectory(at:Self.url.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(theme).write(to:Self.url,options:.atomic)}
        catch {NSLog("تعذر حفظ مظهر الواجهة: %@", error.localizedDescription)}
    }
}
struct PresenterThemeModifier:ViewModifier {
    @ObservedObject var appearance=UIAppearance.shared
    func body(content:Content)->some View {
        content.preferredColorScheme(appearance.theme.darkMode ? .dark:.light)
            .foregroundColor(appearance.theme.text).tint(appearance.theme.accent).background(Color(nsColor:appearance.theme.background))
    }
}
extension View {func presenterTheme()->some View {modifier(PresenterThemeModifier())}}
