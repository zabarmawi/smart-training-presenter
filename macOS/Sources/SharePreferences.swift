import Foundation

enum SharingMode:String,Codable,CaseIterable {case automatic="تلقائي",single="شاشة واحدة",dual="شاشتان"}
struct SharePreferences:Codable {
    var showTimer=false
    var showOvertime=false
    var muteSound=true
    var mode:SharingMode = .automatic
    enum CodingKeys:String,CodingKey {case showTimer,showOvertime,muteSound,mode}
    init() {}
    init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        showTimer=try c.decodeIfPresent(Bool.self,forKey:.showTimer) ?? false
        showOvertime=try c.decodeIfPresent(Bool.self,forKey:.showOvertime) ?? false
        muteSound=try c.decodeIfPresent(Bool.self,forKey:.muteSound) ?? true
        mode=try c.decodeIfPresent(SharingMode.self,forKey:.mode) ?? .automatic
    }
    static var url:URL {DocumentReader.cache.deletingLastPathComponent().appendingPathComponent("SharingPreferences.json")}
    static func load()->Self {
        guard let data=try? Data(contentsOf:url),data.count<10_000,let value=try? JSONDecoder().decode(Self.self,from:data) else {return Self()}
        return value
    }
}
