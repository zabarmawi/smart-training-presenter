import Foundation

struct Evidence: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var fileID: String
    var filename: String
    var page: Int
    var excerpt: String
    var seconds: Double
    var timeKind: String? = nil
    var location: String? = nil
    var sourceDescription:String {[location ?? "",timeKind ?? "",excerpt].filter{!$0.isEmpty}.joined(separator:" · ")}
}
struct Activity: Codable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var kind: String
    var officialCode: String? = nil
    var catalogID: String? = nil
    var mappingNote: String? = nil
    var proposedStartPage: Int? = nil
    var proposedEndPage: Int? = nil
    var sourceGroup: String? = nil
    var displayTitle: String {officialCode.map{$0+" · "+title} ?? title}
    var day: String = ""
    var session: String = ""
    var original: Double
    var duration: Double
    var evidence: [Evidence] = []
    var approved = false
    var presentationID: String? = nil
    var startPage: Int? = nil
    var endPage: Int? = nil
    var needsReview: Bool {!approved}
    var conflict: Bool { Set(evidence.map { $0.seconds }).count > 1 }
}
struct Material: Codable, Identifiable {
    var id = UUID().uuidString
    var path: String
    var hash: String
    var renderedPath: String? = nil
    var pages = 0
    var status = ""
    var sourceGroup: String? = nil
    var libraryRole: String? = nil
    var extractedPages: Int? = nil
    var ocrPages: Int? = nil
    var referenceHash: String? = nil
    var referencePageMap: [String:Int]? = nil
    var versionNote: String? = nil
    var name: String { URL(fileURLWithPath:path).lastPathComponent }
}
struct Preferences: Codable {
    var autoStart = false
    var sound = true
    var visual = true
    var volume = 0.6
    var noticeSeconds = 5.0
    var soundSet = 0
    var barMode = "مصغّر"
    var followSlides: Bool? = nil
    var followsSlides: Bool {followSlides ?? false}
}
struct Project: Codable {
    var version = 1
    var libraryBagID: String? = nil
    var name = "حقيبة جديدة"
    var materials: [Material] = []
    var activities: [Activity] = []
    var preferences = Preferences()
    var timers: [String:Countdown] = [:]
    var freeTimer = Countdown(600)
    var currentActivity: String? = nil
    var currentFile: String? = nil
    var currentPage = 0
    var filePages: [String:Int]? = nil
    var privatePagePreview: Bool? = nil
    func validated() throws -> Project {
        guard version == 1, materials.count < 2000, activities.count < 20000,
              Set(materials.map(\.id)).count == materials.count,
              Set(activities.map(\.id)).count == activities.count,
              activities.allSatisfy({ $0.duration > 0 && $0.duration.isFinite && $0.original > 0 }),
              preferences.noticeSeconds.isFinite && preferences.noticeSeconds >= 1 && preferences.noticeSeconds <= 60,
              preferences.volume.isFinite && (0...1).contains(preferences.volume),
              currentPage >= 0 else { throw PresenterError.message("ملف الحقيبة غير صالح أو إصداره غير مدعوم") }
        for c in Array(timers.values) + [freeTimer] {
            guard c.original > 0, c.adjusted > 0, c.extensions >= 0, c.elapsed >= 0,
                  [c.original,c.adjusted,c.extensions,c.elapsed,c.previous].allSatisfy(\.isFinite) else {
                throw PresenterError.message("حالة المؤقت المحفوظة غير صالحة")
            }
        }
        var safe = self
        // Monotonic anchors cannot survive a reboot. Saved projects always resume paused.
        for id in safe.timers.keys { safe.timers[id]?.running = false; safe.timers[id]?.anchor = nil }
        safe.freeTimer.running = false; safe.freeTimer.anchor = nil
        if safe.preferences.barMode=="عائم" {safe.preferences.barMode="مصغّر"}
        return safe
    }
}
enum PresenterError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
struct Notice {
    var text: String
    var until: Double
    func visible(_ now: Double) -> Bool { now < until }
}

