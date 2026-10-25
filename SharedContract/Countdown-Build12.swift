import Foundation
import Darwin

// Deadline calculation and independent threshold detection ported from reference-timer.
// Unlike the reference, zero does not stop the clock. Continuous time includes sleep.
func continuousSeconds() -> Double {
    var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
    return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1e9
}
struct Countdown: Codable {
    var original: Double
    var adjusted: Double
    var extensions: Double = 0
    var elapsed: Double = 0
    var running = false
    var anchor: Double? = nil
    var fired: Set<Int> = []
    var previous: Double
    init(_ seconds: Double) { original = seconds; adjusted = seconds; previous = seconds }
    func used(_ now: Double) -> Double { elapsed + (running ? max(0, now - (anchor ?? now)) : 0) }
    func remaining(_ now: Double) -> Double { adjusted + extensions - used(now) }
    mutating func toggle(_ now: Double) {
        if running { elapsed = used(now); anchor = nil; running = false }
        else { anchor = now; running = true }
    }
    mutating func pause(_ now: Double) { if running { toggle(now) } }
    mutating func reset() { elapsed = 0; extensions = 0; running = false; anchor = nil; fired = []; previous = adjusted }
    mutating func extend(_ seconds: Double, now: Double) {
        guard seconds > 0, seconds.isFinite else { return }
        extensions += seconds
        // A threshold fires at most once per reset, even after extending above it.
        previous = remaining(now)
    }
    mutating func changeDuration(_ seconds: Double, now: Double) {
        guard seconds > 0, seconds.isFinite else { return }
        adjusted = seconds; previous = remaining(now)
        // Never generate retroactive notifications when editing a duration.
    }
    mutating func poll(_ now: Double) -> [Int] {
        let r = remaining(now)
        defer { previous = r }
        guard running else { return [] }
        var events: [Int] = []
        for t in [300,60,0] where !fired.contains(t) && previous > Double(t) && r <= Double(t) {
            fired.insert(t); events.append(t)
        }
        return events
    }
    func checkpoint(_ now: Double) -> Countdown {
        var c = self; c.elapsed = used(now); c.running = false; c.anchor = nil; c.previous = c.remaining(now); return c
    }
}
func timeText(_ seconds: Double) -> String {
    guard seconds.isFinite else {return "--:--"}
    let n = Int(min(35999999, abs(seconds).rounded(.up)))
    return (seconds < 0 ? "+" : "") + (n >= 3600 ? String(format:"%02d:%02d:%02d",n/3600,n/60%60,n%60) : String(format:"%02d:%02d",n/60,n%60))
}
