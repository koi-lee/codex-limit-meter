import Foundation
import Testing
@testable import CodexMeter

@Test func quotaIconUsesWeeklyRemainingAndPreservesUnknown() {
    func data(_ source: UsageData.DataSource, _ weekly: RateLimitWindow?) -> UsageData {
        UsageData(primary: RateLimitWindow(usedPercent: 90, windowDurationMins: 300, resetsAt: 0), secondary: weekly, planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: source)
    }
    let weekly = RateLimitWindow(usedPercent: 20, windowDurationMins: 10080, resetsAt: 0)
    let state = QuotaIconState(data(.appServer, weekly))
    #expect(state == .value(80))
    #expect(state.fills[0] == 1 && state.fills[1] == 1)
    #expect(abs(state.fills[2] - 0.4) < 0.0001)
    #expect(QuotaIconState(data(.appServer, nil)) == .value(10))
    #expect(QuotaIconState(data(.error, weekly)) == .unavailable)
    #expect(QuotaIconState(data(.loading, weekly)) == .loading)
    #expect(QuotaIconState.value(0).fills == [0, 0, 0])
    #expect(QuotaIconState.value(100).fills == [1, 1, 1])
}

@Test func statusMenuDistinguishesQuotaWindowsAndUnavailable() {
    let weekly = RateLimitWindow(usedPercent: 100, windowDurationMins: 10080, resetsAt: 0)
    let short = RateLimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: 0)
    let usage = UsageData(primary: short, secondary: weekly, planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: .appServer)
    #expect(QuotaIconState(usage).statusText == "0%")
    #expect(QuotaIconState.loading.statusText == "…")
    #expect(QuotaIconState.unavailable.statusText == "—")
    #expect(QuotaIconState.windowLabel(usage, chinese: true) == "周")
    let onlyShort = UsageData(primary: short, secondary: nil, planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: .appServer)
    #expect(QuotaIconState.windowLabel(onlyShort, chinese: false) == "5h")
}
