import Foundation

struct TrendSignal: Identifiable, Hashable {
    let id = UUID()
    let species: String
    let start: Int
    let end: Int

    var delta: Int { end - start }
    var changeRate: Double {
        start == 0 ? Double(end) : Double(end - start) / Double(start)
    }
    var direction: String {
        if delta > 0 { return "rising" }
        if delta < 0 { return "falling" }
        return "steady"
    }
}

struct TrendRollup {
    let recentTotal: Int
    let priorTotal: Int
    let busiestDayKey: String?
    let busiestDayTotal: Int

    var pctChange: Double {
        guard priorTotal > 0 else { return recentTotal > 0 ? 100.0 : 0.0 }
        return Double(recentTotal - priorTotal) / Double(priorTotal) * 100
    }

    var direction: String {
        if recentTotal == priorTotal { return "steady" }
        return recentTotal > priorTotal ? "rising" : "falling"
    }

    var pctLabel: String {
        String(format: "%@%.1f%%", pctChange >= 0 ? "+" : "", pctChange)
    }

    var hasAnyData: Bool {
        recentTotal > 0 || priorTotal > 0 || busiestDayKey != nil
    }
}
