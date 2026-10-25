import Foundation

struct DelimitedTiming {
    var headers:[String]
    var duration:Int
    var factor:Double
    var title:Int
    var code:Int?
    var day:Int?
    var session:Int?
    static func cells(_ line:String)->[String] {
        let delimiter:Character=line.contains("\t") ? "\t":(line.contains(";") ? ";":",")
        var quoted=false;var result:[String]=[];var cell=""
        for char in line {
            if char=="\"" {quoted.toggle()}
            else if char==delimiter && !quoted {result.append(cell.trimmingCharacters(in:.whitespaces));cell=""}
            else {cell.append(char)}
        }
        result.append(cell.trimmingCharacters(in:.whitespaces));return result
    }
    init?(_ line:String) {
        let raw=Self.cells(line);let h=raw.map{TimingExtractor.normalized($0)}
        guard h.count>=2,let duration=h.firstIndex(where:{TimingExtractor.has($0,["المدة","الزمن","duration"])}),
              let title=h.firstIndex(where:{TimingExtractor.has($0,["اسم النشاط","عنوان النشاط","الموضوع","activity name","title"]) || $0=="النشاط"}) else {return nil}
        let unit=h[duration]
        guard TimingExtractor.has(unit,["دقيق","دقائق","minute","ساع","hour"]) else {return nil}
        self.headers=raw;self.duration=duration;self.factor=TimingExtractor.has(unit,["ساع","hour"]) ? 3600:60;self.title=title
        self.code=h.firstIndex(where:{TimingExtractor.has($0,["رقم النشاط","رمز النشاط","code"])})
        self.day=h.firstIndex(where:{TimingExtractor.has($0,["اليوم","day"])})
        self.session=h.firstIndex(where:{TimingExtractor.has($0,["الجلسة","session"])})
    }
    func activity(_ line:String,material:Material,page:Int)->Activity? {
        let c=Self.cells(line)
        guard c.count==headers.count,c.indices.contains(duration),c.indices.contains(title),!c[title].isEmpty else {return nil}
        let seconds:Double
        if let stated=TimingExtractor.durations(c[duration]).first {seconds=stated}
        else if let value=Double(TimingExtractor.normalized(c[duration]).replacingOccurrences(of:",",with:".")),value>0 {seconds=value*factor}
        else {return nil}
        guard seconds<=86400 else {return nil}
        let e=Evidence(fileID:material.id,filename:material.name,page:page,excerpt:headers.joined(separator:" | ")+"\n"+line,seconds:seconds)
        return Activity(title:c[title],kind:"نشاط",officialCode:code.flatMap{TimingExtractor.code(c[$0])},sourceGroup:material.sourceGroup ?? URL(fileURLWithPath:material.path).deletingLastPathComponent().path,day:day.map{TimingExtractor.hierarchy(c[$0],label:"اليوم")} ?? "",session:session.map{TimingExtractor.hierarchy(c[$0],label:"الجلسة")} ?? "",original:seconds,duration:seconds,evidence:[e])
    }
}
