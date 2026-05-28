import Foundation

// Quick stats over a session's records — user/assistant turn counts, total
// tool calls, and start/end timestamps for duration. Computed lazily; small
// enough that we just walk the records once per detail view.
struct SessionStats {
    var userTurns: Int = 0
    var assistantTurns: Int = 0
    var toolCalls: Int = 0
    var firstTimestamp: Date? = nil
    var lastTimestamp: Date? = nil
    var activityBuckets: [Int] = []   // for the sparkline

    var duration: TimeInterval? {
        guard let first = firstTimestamp, let last = lastTimestamp, last > first else { return nil }
        return last.timeIntervalSince(first)
    }

    var durationLabel: String? {
        guard let d = duration else { return nil }
        if d < 60 { return "<1m" }
        if d < 3600 { return "\(Int(d / 60))m" }
        let hours = Int(d / 3600)
        let mins = Int(d.truncatingRemainder(dividingBy: 3600) / 60)
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }

    static func compute(records: [SessionRecord], buckets: Int = 24) -> SessionStats {
        var stats = SessionStats()
        var timestamps: [Date] = []

        for rec in records {
            if let ts = rec.timestamp { timestamps.append(ts) }
            switch rec.type {
            case "user":
                if case .text = rec.message?.content { stats.userTurns += 1 }
                else if case .parts(let parts) = rec.message?.content {
                    // count user messages that aren't only tool_results
                    let hasText = parts.contains(where: { $0.type == "text" || $0.text != nil })
                    if hasText { stats.userTurns += 1 }
                }
            case "assistant":
                stats.assistantTurns += 1
                if case .parts(let parts) = rec.message?.content {
                    for part in parts where part.type == "tool_use" {
                        stats.toolCalls += 1
                    }
                }
            default:
                continue
            }
        }

        stats.firstTimestamp = timestamps.min()
        stats.lastTimestamp = timestamps.max()
        stats.activityBuckets = makeActivityBuckets(timestamps: timestamps, count: buckets)
        return stats
    }

    private static func makeActivityBuckets(timestamps: [Date], count: Int) -> [Int] {
        guard timestamps.count >= 2, count > 0 else { return [] }
        guard let first = timestamps.min(), let last = timestamps.max(), last > first else { return [] }
        let span = last.timeIntervalSince(first)
        let bucketSize = span / Double(count)
        var buckets = Array(repeating: 0, count: count)
        for ts in timestamps {
            let offset = ts.timeIntervalSince(first)
            var idx = Int(offset / bucketSize)
            if idx >= count { idx = count - 1 }
            if idx < 0 { idx = 0 }
            buckets[idx] += 1
        }
        return buckets
    }
}
