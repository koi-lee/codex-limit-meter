import Foundation
import Testing
@testable import CodexMeter

@Test func quotaReadFailureOffersExplicitReloginOnlyForConnectedStoreAccount() {
    #expect(shouldOfferQuotaRelogin(isDemo: false, usesStoreAuthentication: true,
                                    regionRestricted: false, isSignedIn: true,
                                    hasReadError: true))
    #expect(!shouldOfferQuotaRelogin(isDemo: true, usesStoreAuthentication: true,
                                     regionRestricted: false, isSignedIn: true,
                                     hasReadError: true))
    #expect(!shouldOfferQuotaRelogin(isDemo: false, usesStoreAuthentication: false,
                                     regionRestricted: false, isSignedIn: true,
                                     hasReadError: true))
    #expect(!shouldOfferQuotaRelogin(isDemo: false, usesStoreAuthentication: true,
                                     regionRestricted: true, isSignedIn: true,
                                     hasReadError: true))
    #expect(!shouldOfferQuotaRelogin(isDemo: false, usesStoreAuthentication: true,
                                     regionRestricted: false, isSignedIn: true,
                                     hasReadError: false))
}

@Test func quotaJournalDoesNotInferResetAndBreaksAtUnknown() {
    func state(_ value: Int?, reset: Int64 = 1000) -> PetState {
        PetState(UsageData(primary: nil, secondary: value.map { RateLimitWindow(usedPercent: 100-$0, windowDurationMins: 10080, resetsAt: reset) }, planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: value == nil ? .error : .appServer))
    }
    var journal = PetQuotaJournal()
    journal.observe(state(36)); journal.observe(state(36))
    #expect(journal.changes.isEmpty)
    journal.observe(state(94))
    #expect(journal.changes.first?.from == 36 && journal.changes.first?.to == 94)
    journal.observe(state(nil)); journal.observe(state(50))
    #expect(journal.changes.isEmpty)
    journal.observe(state(49)); journal.observe(state(100, reset: 2000))
    #expect(journal.changes.isEmpty)
}

@MainActor @Test func partialFeedStatusNamesHealthyPrimarySource() {
    let model = PetMessageModel()
    model.partialSources = true
    model.primarySourceHealthy = true
    #expect(model.partialSourcesMessage == "Tibo 主动态源正常；辅助网页来源暂不可用，目前没有可展示的有效消息。")
    model.entries = [Announcement(id: "test", revision: 1, title: .init(zh: "预告", en: "Preview"), summary: .init(zh: "", en: ""), audience: .init(zh: "", en: ""), sourceURL: "https://x.com/", publishedAt: Date(), expiresAt: .distantFuture, resetAt: nil, status: "active")]
    #expect(model.partialSourcesMessage?.contains("以下为已获取的消息") == true)
    model.failed = true
    #expect(model.partialSourcesMessage == nil)
}

@Test func messageCopySeparatesPostTimeFromResetTime() {
    func entry(_ title: String, summary: String = "", reset: Date? = nil, status: String = "active") -> Announcement {
        Announcement(id: "copy-test", revision: 1, title: .init(zh: title, en: title), summary: .init(zh: summary, en: summary), audience: .init(zh: "以原文为准", en: "See source"), sourceURL: "https://x.com/thsottiaux/status/123", publishedAt: Date(timeIntervalSince1970: 1789200557), expiresAt: .distantFuture, resetAt: reset, status: status)
    }
    let complete = PetAnnouncementCopy(entry("重置完成消息"), historical: false)
    #expect(complete.dataSourceURL == TiboAnnouncementFeed.attributionURL)
    #expect(complete.timing.contains("发布完成消息"))
    #expect(complete.explanation.contains("未给出精确完成时刻"))
    let old = PetAnnouncementCopy(entry("重置预告", summary: "A reset is also landing by midnight today."), historical: true)
    #expect(old.timing == "原帖预计：发帖当日午夜前")
    #expect(old.explanation.contains("未注明时区"))
    #expect(old.explanation.contains("不代表将再重置一次"))
    let future = PetAnnouncementCopy(entry("重置预告", reset: .distantFuture), historical: false)
    #expect(future.timing.hasPrefix("预计"))
    let withdrawn = PetAnnouncementCopy(entry("重置预告", status: "withdrawn"), historical: true)
    #expect(withdrawn.title.contains("已撤回"))
    let webObservation = Announcement(id: "page", revision: 1, title: .init(zh: "网页变化", en: "Page change"), summary: .init(zh: "", en: ""), audience: .init(zh: "", en: ""), sourceURL: "https://help.openai.com/", publishedAt: Date(), expiresAt: .distantFuture, resetAt: nil, status: "active")
    #expect(PetAnnouncementCopy(webObservation, historical: false).dataSourceURL == nil)
}

@Test func messageSummaryUsesBeijingDayAndDetectionTime() {
    let now = ISO8601DateFormatter().date(from: "2026-09-13T15:30:00Z")!
    func entry(_ id: String, target: Date?) -> Announcement {
        Announcement(id: id, revision: 1, title: .init(zh: "官方额度公告更新（本地监测）", en: "Update"), summary: .init(zh: "网页变化", en: "Changed"), audience: .init(zh: "见原文", en: "See source"), sourceURL: "https://help.openai.com/", publishedAt: now, expiresAt: .distantFuture, resetAt: target, status: "active")
    }
    let local = PetAnnouncementCopy(entry("local-page", target: nil), historical: false, now: now)
    #expect(local.timing.contains("发现变化"))
    #expect(local.brief.contains("时间未公布"))
    #expect(!local.title.contains("本地监测"))
    let today = PetAnnouncementCopy(entry("forecast", target: now.addingTimeInterval(600)), historical: false, now: now)
    let tomorrow = PetAnnouncementCopy(entry("forecast", target: now.addingTimeInterval(3600)), historical: false, now: now)
    #expect(today.brief.contains("今天"))
    #expect(tomorrow.brief.contains("明天"))
}
