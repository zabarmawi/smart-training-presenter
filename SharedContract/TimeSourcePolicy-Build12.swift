import Foundation

struct TimeAssessment {
    var proposed:Double?
    var primary:[Evidence]
    var auxiliary:[Evidence]
    var unrelated:[Evidence]
    var status:String
    var sourceLabel:String
    var requiresReview:Bool
    var deltas:[Double] {guard let proposed=proposed else {return []};return auxiliary.map{$0.seconds-proposed}}
}
// Pure policy: reading an assessment never writes to the project, grants approval,
// redistributes a session total, or replaces a previously approved duration.
enum TimeSourcePolicy {
    static func role(_ e:Evidence,materials:[Material])->String? {
        if let m=materials.first(where:{$0.id==e.fileID}) {
            let name=TrainingLibrary.role(m.name)
            if ["trainer","learner"].contains(name ?? "") {return name}
            return m.libraryRole ?? name
        }
        return materials.isEmpty ? TrainingLibrary.role(e.filename):nil
    }
    static func kind(_ e:Evidence,activity:Activity)->String {
        if let kind=e.timeKind {return kind}
        let n=TimingExtractor.normalized(e.excerpt)
        if n.contains("اجمالي الجلسة") || n.contains("اجمالي المدة الزمنية") {return "جلسة"}
        return activity.kind
    }
    static func assess(_ activity:Activity,materials:[Material])->TimeAssessment {
        let relevant=activity.evidence.filter{kind($0,activity:activity)==activity.kind && $0.seconds>0 && $0.seconds.isFinite}
        let primary=relevant.filter{["trainer","learner"].contains(role($0,materials:materials) ?? "")}
        let auxiliary=relevant.filter{!["trainer","learner"].contains(role($0,materials:materials) ?? "")}
        let byFile=Dictionary(grouping:primary,by:{$0.fileID})
        let inside=byFile.values.contains{Set($0.map(\.seconds)).count>1}
        let values=Set(primary.map(\.seconds))
        let roles=Set(primary.compactMap{role($0,materials:materials)})
        let proposal=values.count==1 ? values.first:nil
        let differs=proposal.map{p in auxiliary.contains{abs($0.seconds-p)>0.01}} ?? false
        let approvedDifference=activity.approved && (proposal.map{abs($0-activity.duration)>0.01} ?? false)
        let state=inside ? "تعارض داخل الدليل":(values.count>1 ? "تعارض بين الدليلين":(proposal==nil ? "يحتاج مراجعة يدوية":(differs ? "اختلاف العرض عن الدليل":(approvedDifference ? "اختلاف عن القيمة المعتمدة":"مقترح"))))
        let source=roles.count==2 ? "دليل المدرب ودليل المتدرب":(roles.contains("trainer") ? "دليل المدرب":(roles.contains("learner") ? "دليل المتدرب":"لا توجد مدة موثوقة في الدليلين"))
        return TimeAssessment(proposed:proposal,primary:primary,auxiliary:auxiliary,unrelated:activity.evidence.filter{kind($0,activity:activity) != activity.kind},status:state,sourceLabel:source,requiresReview:inside || values.count != 1 || differs || approvedDifference)
    }
    static func retaining(_ previous:Activity,adding incoming:[Evidence])->Activity {
        var result=previous
        for var source in incoming {
            if result.evidence.contains(where:{$0.fileID==source.fileID && $0.page==source.page && $0.excerpt==source.excerpt && $0.seconds==source.seconds && $0.timeKind==source.timeKind}) {continue}
            if result.evidence.contains(where:{$0.id==source.id}) {source.id=UUID().uuidString}
            result.evidence.append(source)
        }
        return result
    }
    static func propose(_ activity:inout Activity,materials:[Material]) {
        guard !activity.approved,let value=assess(activity,materials:materials).proposed else {return}
        activity.duration=value
    }
}
