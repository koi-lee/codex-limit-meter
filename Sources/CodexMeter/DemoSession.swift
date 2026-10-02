import Foundation

/// Ephemeral fixtures. Never passed to account services or persistence.
struct DemoSession {
    let startedAt: Date
    init(now: Date = Date()) { startedAt = now }
    var usage: UsageData {
        UsageData(primary: .init(usedPercent: 28, windowDurationMins: 300,
                                resetsAt: Int64(startedAt.addingTimeInterval(7200).timeIntervalSince1970)),
                  secondary: .init(usedPercent: 41, windowDurationMins: 10080,
                                  resetsAt: Int64(startedAt.addingTimeInterval(172800).timeIntervalSince1970)),
                  planType: "Demo", hasCredits: false, creditBalance: nil,
                  lastUpdated: startedAt, dataSource: .appServer)
    }
    var entries: [Announcement] {
        [.init(id: "demo-preview", revision: 1,
               title: .init(zh: "示例 · 重置预告", en: "Sample reset preview"),
               summary: .init(zh: "仅用于体验消息展示，不是真实公告。", en: "Sample message, not a real announcement."),
               audience: .init(zh: "演示账号（虚构）", en: "Fictional demo account"), sourceURL: "",
               publishedAt: startedAt.addingTimeInterval(-600), expiresAt: startedAt.addingTimeInterval(86400),
               resetAt: startedAt.addingTimeInterval(7200), status: "active")]
    }
    var changes: [PetQuotaObservation] {
        [.init(from: 64, to: 59, at: startedAt),
         .init(from: 70, to: 64, at: startedAt.addingTimeInterval(-1800))]
    }
}
