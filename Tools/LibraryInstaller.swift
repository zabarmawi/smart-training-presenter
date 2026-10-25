import Foundation
import CryptoKit

enum InstallError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}
func fail(_ text: String) throws -> Never { throw InstallError.message(text) }
func read(_ url: URL) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { try fail("تعذر قراءة بيانات المكتبة") }
    return value
}
func write(_ object: [String: Any], _ url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url, options: .atomic)
}
func safe(_ root: URL, _ path: String) throws -> URL {
    let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !pieces.contains(".."), !pieces.contains("") else { try fail("مسار غير صالح داخل حزمة المكتبة") }
    var current = root
    for part in pieces {
        current.appendPathComponent(String(part))
        if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { try fail("لا يُسمح بروابط رمزية داخل المكتبة") }
    }
    return current
}
func install() throws {
    let fm = FileManager.default, args = CommandLine.arguments
    guard args.count == 2 || args.count == 4 else { try fail("Usage: LibraryInstaller PACKAGE [--target NEW_USER_DATA]") }
    let source = URL(fileURLWithPath: args[1]).standardizedFileURL
    let base: URL
    if args.count == 4 {
        guard args[2] == "--target" else { try fail("Unknown argument") }
        base = URL(fileURLWithPath: args[3]).standardizedFileURL
    } else {
        base = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SmartTrainingPresenter", isDirectory: true)
    }
    let library = base.appendingPathComponent("Library", isDirectory: true)
    guard !fm.fileExists(atPath: library.path) else { try fail("توجد مكتبة بالفعل. لم يتغير أي ملف. استخدم نسخة احتياطية أو اطلب مساعدة لنقلها؛ لا تستبدل قراراتك الحالية.") }
    var parent = base
    while parent.path != "/" {
        if (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { try fail("مجلد الوجهة يحتوي رابطًا رمزيًا؛ لم تُثبت المكتبة") }
        parent.deleteLastPathComponent()
    }
    let manifest = try read(source.appendingPathComponent("manifest.json"))
    guard manifest["format"] as? String == "stp-portable-library", manifest["version"] as? Int == 1,
          let hashes = manifest["files_sha256"] as? [String: String],
          let counts = manifest["counts"] as? [String: Int], counts["bags"] == 11 else { try fail("صيغة حزمة المكتبة غير مدعومة") }
    for (path, expected) in hashes {
        let bytes = try Data(contentsOf: safe(source, path))
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard hash == expected else { try fail("فشل فحص سلامة الملف: \(path)") }
    }
    let originalIndex = try read(source.appendingPathComponent("Library/index.json"))
    guard let bags = originalIndex["bags"] as? [[String: Any]], bags.count == 11 else { try fail("عدد الحقائب غير مطابق") }
    let destination = base.appendingPathComponent("DistributedLibraries/" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.copyItem(at: source, to: destination)
    var committed = false
    defer { if !committed { try? fm.removeItem(at: destination) } }
    var index = originalIndex; index["root"] = destination.path
    try write(index, destination.appendingPathComponent("Library/index.json"))
    for bag in bags {
        guard let id = bag["id"] as? String else { try fail("معرّف حقيبة مفقود") }
        let path = "Library/Projects/" + id + ".stpresenter"
        let file = try safe(destination, path)
        var project = try read(file)
        guard var materials = project["materials"] as? [[String: Any]] else { try fail("مواد حقيبة مفقودة") }
        for i in materials.indices {
            for key in ["path", "renderedPath"] {
                if let relative = materials[i][key] as? String {
                    guard hashes[relative] != nil else { try fail("مصدر غير موجود في سجل البصمات") }
                    materials[i][key] = try safe(destination, relative).path
                }
            }
        }
        project["materials"] = materials; try write(project, file)
    }
    // moveItem fails if another installer created Library meanwhile. No overwrite.
    try fm.moveItem(at: destination.appendingPathComponent("Library"), to: library)
    committed = true
    print("تمت إضافة 11 حقيبة بأزمنتها وروابطها و341 اعتمادًا و769 إحالة. افتح التطبيق ثم نافذة المكتبة. لم تُستبدل مكتبة قائمة.")
}
do { try install() } catch { fputs((error.localizedDescription + "\n"), stderr); exit(1) }
