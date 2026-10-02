import Foundation
import Testing
import UserNotifications
@testable import CodexMeter

private func fixture(revision: Int = 1, status: String = "active", expires: String = "2099-01-02T08:00:00+08:00") -> Data {
    Data("""
    {"version":1,"announcements":[{"id":"test-only","revision":\(revision),
    "title":{"zh":"测试：明日额外重置","en":"Test: extra reset tomorrow"},
    "summary":{"zh":"仅供本地验证，不是真实公告","en":"Local test, not a real announcement"},
    "audience":{"zh":"测试用户","en":"Test users"},
    "sourceURL":"https://openai.com/","publishedAt":"2020-01-01T00:00:00Z",
    "expiresAt":"\(expires)","resetAt":"2099-01-02T08:00:00+08:00","status":"\(status)"}]}
    """.utf8)
}

@Test func announcementParsingAndEligibility() throws {
    let entry = try #require(AnnouncementFeed.parse(fixture()).announcements.first)
    #expect(entry.resetAt == ISO8601DateFormatter().date(from: "2099-01-02T00:00:00Z"))
    #expect(entry.active(at: Date()))
    #expect(entry.shouldNotify(at: Date(), sent: [:]))
    #expect(!entry.shouldNotify(at: Date(), sent: [entry.id: 1]))
    #expect(!entry.shouldNotify(at: entry.expiresAt, sent: [:]))
    #expect(!entry.shouldNotify(at: Date(timeIntervalSince1970: 0), sent: [:]))
    let withdrawn = try #require(AnnouncementFeed.parse(fixture(revision: 2, status: "withdrawn")).announcements.first)
    #expect(!withdrawn.active(at: Date()))
    #expect(!withdrawn.shouldNotify(at: Date(), sent: [:]))
    #expect(withdrawn.shouldNotify(at: Date(), sent: [entry.id: 1]))
    #expect(withdrawn.notificationTitle(chinese: false, previouslySent: true).hasPrefix("Withdrawn:"))
}

@Test func rejectsInvalidAnnouncements() {
    let text = String(decoding: fixture(), as: UTF8.self)
    for invalid in [
        text.replacingOccurrences(of: "https://openai.com/", with: "http://openai.com/"),
        text.replacingOccurrences(of: "2020-01-01T00:00:00Z", with: "2020-01-01T00:00:00"),
        text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
        text.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":0"),
        text.replacingOccurrences(of: "\"sourceURL\"", with: "\"missingSource\"")
    ] {
        #expect(throws: (any Error).self) { try AnnouncementFeed.parse(Data(invalid.utf8)) }
    }
    #expect(Announcement.source("https://user:password@openai.com/") == nil)
    #expect(Announcement.source("https:///path") == nil)
}

@MainActor @Test func notificationLifecycleAndPersistence() async throws {
    let name = "AnnouncementTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var data = fixture()
    var networkFailure = false
    var delivered: [UNNotificationRequest] = []
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: {
        if networkFailure { throw URLError(.notConnectedToInternet) }
        return data
    }, permission: { .authorized }, requestPermission: { Issue.record("Unexpected prompt"); return false }, deliver: { delivered.append($0) })
    defer { service.stop() }
    await service.check()
    #expect(delivered.isEmpty)
    await service.setEnabled(true)
    #expect(delivered.count == 1)
    #expect(delivered[0].content.body.contains("适用范围"))
    #expect(delivered[0].content.userInfo["sourceURL"] as? String == "https://openai.com/")
    await service.check()
    #expect(delivered.count == 1)
    data = fixture(revision: 2)
    await service.check()
    #expect(delivered.count == 2)
    #expect(delivered.last?.content.title.hasPrefix("公告更新") == true)
    networkFailure = true
    await service.check()
    #expect(service.failed)
    #expect(service.entries.first?.revision == 2)
    networkFailure = false
    data = fixture(revision: 3, status: "withdrawn")
    await service.check()
    #expect(delivered.count == 3)
    #expect(Set(delivered.map(\.identifier)).count == 3)
    #expect(delivered.allSatisfy { $0.content.userInfo["announcementID"] as? String == "test-only" })
    var opened: String?
    service.onOpenAnnouncement = { opened = $0 }
    service.openNotification(id: delivered[0].content.userInfo["announcementID"] as? String, source: nil)
    #expect(opened == "test-only")
    #expect(service.entries.first?.revision == 3)
    let restarted = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: { data }, permission: { .authorized }, deliver: { delivered.append($0) })
    await restarted.check()
    #expect(delivered.count == 3)
    #expect(restarted.entries.first?.status == "withdrawn")
    await service.setEnabled(false)
    data = fixture(revision: 4)
    await service.check()
    #expect(delivered.count == 3)
}

@MainActor @Test func deniedPermissionAndDeliveryRetry() async throws {
    let name = "AnnouncementTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var status: UNAuthorizationStatus = .notDetermined
    var prompts = 0
    var attempts = 0
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: { fixture() }, permission: { status }, requestPermission: {
        prompts += 1; status = .denied; return false
    }, deliver: { _ in
        attempts += 1
        if attempts == 1 { throw URLError(.unknown) }
    })
    defer { service.stop() }
    await service.setEnabled(true)
    await service.setEnabled(false)
    await service.setEnabled(true)
    #expect(prompts == 1)
    #expect(attempts == 0)
    #expect(service.entries.count == 1)
    status = .authorized
    await service.refreshAuthorization()
    #expect(service.authorization == .authorized)
    #expect(attempts == 0)
    #expect(prompts == 1)
    await service.check()
    #expect(service.notificationFailed)
    await service.check()
    #expect(!service.notificationFailed)
    #expect(attempts == 2)
    await service.check()
    #expect(attempts == 2)
}

@MainActor @Test func announcementServiceKeepsPrimaryFeedHealthWhenPartial() async {
    let name = "AnnouncementTests.partial.\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let json = String(decoding: fixture(), as: UTF8.self)
        .replacingOccurrences(of: "{\"version\":1,", with: "{\"version\":1,\"healthy\":true,\"partial\":true,")
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: { Data(json.utf8) },
                                      permission: { .notDetermined })
    await service.check()
    #expect(service.failed == false)
    #expect(service.partialSources)
    #expect(service.primarySourceHealthy == true)
    service.stop()
}

@MainActor @Test func announcementChecksDoNotOverlap() async throws {
    let name = "AnnouncementTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var calls = 0
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: {
        calls += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        return fixture()
    }, permission: { .denied })
    async let first: Void = service.check()
    async let second: Void = service.check()
    _ = await (first, second)
    #expect(calls == 1)
}

@MainActor @Test func unpublishedFeedIsNotAnEmptySuccess() async throws {
    let name = "AnnouncementTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var published = false
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: {
        if !published { throw AnnouncementFetchError.notPublished }
        return Data(#"{"version":1,"announcements":[]}"#.utf8)
    }, permission: { .denied })
    await service.check()
    #expect(service.failed && service.notPublished)
    #expect(service.lastSuccess == nil)
    published = true
    await service.check()
    #expect(!service.failed && !service.notPublished)
    #expect(service.lastSuccess != nil)
    #expect(service.entries.isEmpty)
}

@MainActor @Test func localMonitorDeliversWhenPublicFeedFails() async throws {
    let name = "AnnouncementTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".json")
    defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: file) }
    try fixture().write(to: file)
    var sent = 0
    let service = AnnouncementService(defaults: defaults, localFeedURL: file,
        fetch: { throw URLError(.notConnectedToInternet) }, permission: { .authorized },
        deliver: { _ in sent += 1 })
    defer { service.stop() }
    await service.setEnabled(true)
    #expect(service.failed)
    #expect(sent == 1)
    await service.check()
    #expect(sent == 1)
}

private func resetEntry(_ id: String, title: String, published: Double, reset: Double? = nil, status: String = "active") -> Announcement {
    Announcement(id: id, revision: 1, title: .init(zh: title, en: title),
                 summary: .init(zh: "测试", en: "Test"), audience: .init(zh: "以原文为准", en: "See source"),
                 sourceURL: "https://x.com/thsottiaux/status/123", publishedAt: Date(timeIntervalSince1970: published),
                 expiresAt: Date(timeIntervalSince1970: 10000), resetAt: reset.map { Date(timeIntervalSince1970: $0) }, status: status)
}

@Test func olderPreviewDoesNotLookLikeAnotherUpcomingReset() {
    let preview = resetEntry("preview", title: "Codex：重置预告（转录）", published: 100)
    let done = resetEntry("done", title: "Codex：重置完成消息（转录）", published: 200)
    let overview = ResetAnnouncementOverview(entries: [preview, done], now: Date(timeIntervalSince1970: 300))
    #expect(overview.upcoming.isEmpty)
    #expect(overview.latestCompleted?.id == "done")
    #expect(overview.history.map(\.id) == ["preview"])
    #expect(!preview.resetMenuTitle(chinese: true).contains("已兑现"))
}

@Test func explicitFutureResetSurvivesUnrelatedCompletion() {
    let scheduled = resetEntry("scheduled", title: "重置预告", published: 100, reset: 500)
    let done = resetEntry("done", title: "重置完成消息", published: 200)
    let newer = resetEntry("newer", title: "重置预告", published: 250)
    let elapsed = resetEntry("elapsed", title: "重置预告", published: 100, reset: 280)
    let withdrawn = resetEntry("withdrawn", title: "重置预告", published: 100, reset: 500, status: "withdrawn")
    let futurePost = resetEntry("futurePost", title: "重置完成消息", published: 400)
    let overview = ResetAnnouncementOverview(entries: [scheduled, done, newer, elapsed, withdrawn, futurePost], now: Date(timeIntervalSince1970: 300))
    #expect(Set(overview.upcoming.map(\.id)) == ["scheduled", "newer"])
    #expect(Set(overview.history.map(\.id)) == ["elapsed", "withdrawn"])
    #expect(overview.latestCompleted?.id == "done")
    #expect(newer.resetMenuTitle(chinese: true, upcoming: true).contains("时间待核对"))
    #expect(scheduled.resetMenuTitle(chinese: true, upcoming: true).contains("08:08"))
}

private func signalFixture(_ text: String, fetched: String = "2026-09-09T00:00:00Z", url: String = "https://x.com/thsottiaux/status/123") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["source": "x-api", "fetched_at": fetched, "items": [["id": "123", "url": url, "at": "2026-09-08T23:00:00Z", "text": text]]])
}

@Test func standaloneFeedParsesWithoutLocalScripts() throws {
    let now = try TiboAnnouncementFeed.date("2026-09-09T00:00:00Z")
    let data = try TiboAnnouncementFeed.parse(signalFixture("Never gonna give you up. We will do a global reset in 3 hours."), now: now, signals: true)
    let entry = try #require(AnnouncementFeed.parse(data).announcements.first)
    #expect(entry.id == "local-tibo-123")
    #expect(entry.isResetPreview)
    #expect(entry.resetAt == (try TiboAnnouncementFeed.date("2026-09-09T02:00:00Z")))
    for text in ["No reset tomorrow.", "Will you reset tomorrow?", "New model released today."] {
        let parsed = try TiboAnnouncementFeed.parse(signalFixture(text), now: now, signals: true)
        #expect(try AnnouncementFeed.parse(parsed).announcements.isEmpty)
    }
    let completed = try TiboAnnouncementFeed.parse(signalFixture("All reset for everyone."), now: now, signals: true)
    #expect(try AnnouncementFeed.parse(completed).announcements.first?.isResetCompleted == true)
}

@Test func codexResetRequestsIdentifyTheApp() {
    let request = TiboAnnouncementFeed.request(TiboAnnouncementFeed.signals)
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == TiboAnnouncementFeed.userAgent)
    #expect(TiboAnnouncementFeed.attributionURL.host == "codex-reset.com")
}

@Test func standaloneFeedRejectsStaleAndForgedSources() throws {
    let now = try TiboAnnouncementFeed.date("2026-09-09T00:00:00Z")
    for data in [try signalFixture("All reset.", fetched: "2026-09-08T20:00:00Z"),
                 try signalFixture("All reset.", url: "https://example.com/123")] {
        #expect(throws: (any Error).self) { try TiboAnnouncementFeed.parse(data, now: now, signals: true) }
    }
}

@Test func tiboPropagationAndUnspecifiedMidnight() throws {
    let now = try TiboAnnouncementFeed.date("2026-09-09T00:00:00Z")
    func parse(_ text: String) throws -> Announcement? {
        try AnnouncementFeed.parse(TiboAnnouncementFeed.parse(signalFixture(text), now: now, signals: true)).announcements.first
    }
    #expect(try parse("Reset all propagated. Sweet dreams.")?.isResetCompleted == true)
    #expect(try parse("Resets all propagated. That will be all. Have a fantastic weekend.")?.isResetCompleted == true)
    #expect(try parse("Reset not propagated.") == nil)
    let nextWeek = try #require(try parse("Sorry Gia. More resets coming next week."))
    #expect(nextWeek.title.zh.contains("重置预告"))
    #expect(nextWeek.resetAt == nil)
    let midnight = try #require(try parse("Hi Astra users. A reset is also landing by midnight today."))
    #expect(midnight.isResetPreview)
    #expect(midnight.resetAt == nil) // No invented timezone for the author's midnight.
    let window = try #require(try parse("We will reset within 3 hours."))
    #expect(window.resetAt == nil) // A deadline is not a scheduled instant.
    let promise = try #require(try parse("We are almost Tuesday and I promised a reset for Tuesday. See you soon."))
    #expect(promise.isResetPreview)
    #expect(promise.resetAt == nil) // A weekday promise is not an exact instant.
    #expect(try parse("Reset not propagated.") == nil)
}

@MainActor @Test func localQueueDoesNotEraseLiveTiboEntries() async throws {
    let suite = "PetSourceMerge.\(UUID())", file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: file) }
    try fixture().write(to: file)
    let raw = String(decoding: fixture(), as: UTF8.self).replacingOccurrences(of: "test-only", with: "local-tibo-123")
    let service = AnnouncementService(defaults: defaults, localFeedURL: file, fetch: { Data(raw.utf8) }, permission: { .denied })
    await service.check()
    #expect(Set(service.entries.map(\.id)) == ["test-only", "local-tibo-123"])
}

@Test func publicFeedRejectsStaleOrUnhealthyData() throws {
    let now = Date()
    var object = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
    object["healthy"] = true
    object["generatedAt"] = ISO8601DateFormatter().string(from: now)
    let fresh = try JSONSerialization.data(withJSONObject: object)
    #expect(try PublicAnnouncementFeed.validate(fresh, now: now) == fresh)
    #expect(throws: (any Error).self) { try PublicAnnouncementFeed.validate(fresh, now: now.addingTimeInterval(1900)) }
    object["healthy"] = false
    let failed = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: (any Error).self) { try PublicAnnouncementFeed.validate(failed, now: now) }
}

@Test @MainActor func notificationRoutesToMatchingAnnouncement() async throws {
    let suite = "notification-route-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: { fixture() }, permission: { .denied })
    await service.check()
    var opened: String?
    service.onOpenAnnouncement = { opened = $0 }
    service.openNotification(id: "test-only", source: nil)
    #expect(opened == "test-only")
    opened = nil
    service.openNotification(id: "missing", source: nil)
    #expect(opened == nil)
}

@Test @MainActor func testReminderRequiresPermissionAndDoesNotChangeAnnouncementHistory() async throws {
    let suite = "test-reminder-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "announcements.enabled")
    var status = UNAuthorizationStatus.denied
    var delivered: [UNNotificationRequest] = []
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: { fixture() }, permission: { status }, diagnostics: { "桌面横幅未开启" }, deliver: { delivered.append($0) })
    await service.sendTestReminder()
    #expect(delivered.isEmpty)
    #expect(service.reminderStatusText == "系统通知未允许")
    status = .authorized
    await service.sendTestReminder()
    #expect(delivered.count == 1)
    #expect(delivered.first?.content.title.contains("测试提醒") == true)
    #expect(service.remindersReady)
    #expect(defaults.dictionary(forKey: "announcements.sent") == nil)
    #expect(service.entries.isEmpty)
    #expect(service.testReminderStatus.contains("已提交系统"))
    #expect(service.testReminderStatus.contains("尚未确认横幅显示"))
    #expect(service.testReminderStatus.contains("桌面横幅未开启"))
    await service.sendTestReminder()
    #expect(delivered.count == 2)
    #expect(delivered[0].identifier != delivered[1].identifier)
    status = .denied
    await service.sendTestReminder()
    #expect(!service.testReminderStatus.contains("已提交系统"))
    #expect(!service.testingReminder)
}

@Test @MainActor func introductionIsOnceOnlyAndSkipsReadyUsers() async {
    let name = "intro-\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.removeObject(forKey: "announcements.introduction.v1.seen")
    defaults.set(false, forKey: "announcements.enabled")
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: { fixture() }, permission: { .notDetermined })
    #expect(service.consumeReminderIntroduction())
    #expect(!service.consumeReminderIntroduction())
    let restarted = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: { fixture() }, permission: { .notDetermined })
    #expect(!restarted.consumeReminderIntroduction())
    defaults.removeObject(forKey: "announcements.introduction.v1.seen")
    defaults.set(true, forKey: "announcements.enabled")
    let ready = AnnouncementService(defaults: defaults, localFeedURL: nil, fetch: { fixture() }, permission: { .authorized })
    await ready.refreshAuthorization()
    #expect(!ready.consumeReminderIntroduction())
    defaults.removeObject(forKey: "announcements.introduction.v1.seen")
    defaults.removeObject(forKey: "announcements.enabled")
}

@Test @MainActor func disabledSystemAlertsStillPollForPetBubbles() async {
    let name = "bubble-disabled-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    var fetched = 0
    var delivered = 0
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil,
        fetch: { fetched += 1; return fixture() }, permission: { .denied },
        deliver: { _ in delivered += 1 })
    await service.setEnabled(false)
    let timer = Mirror(reflecting: service).children.first { $0.label == "timer" }?.value as? Timer
    #expect(timer?.isValid == true)
    await service.check()
    #expect(fetched > 0)
    #expect(delivered == 0)
    service.stop()
}
