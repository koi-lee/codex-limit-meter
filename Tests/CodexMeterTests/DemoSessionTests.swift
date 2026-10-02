import Foundation
import Testing
import UserNotifications
@testable import CodexMeter

@Test @MainActor func oldPermissionCheckCannotPromptAfterDemoRoundTrip() async {
    let suite = "demo-permission-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var pending: CheckedContinuation<UNAuthorizationStatus, Never>?
    var prompts = 0
    var fetches = 0
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil,
        fetch: { fetches += 1; return Data("{\"version\":1,\"announcements\":[]}".utf8) },
        permission: { await withCheckedContinuation { pending = $0 } },
        requestPermission: { prompts += 1; return false })
    let request = Task { await service.setEnabled(true) }
    while pending == nil { await Task.yield() }
    service.setDemoSuspended(true)
    service.setDemoSuspended(false)
    pending?.resume(returning: .notDetermined)
    await request.value
    #expect(prompts == 0)
    #expect(fetches == 0)
}

@Test @MainActor func oldTestReminderIsDiscardedAfterDemoRoundTrip() async {
    let suite = "demo-reminder-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "announcements.enabled")
    var pending: CheckedContinuation<String, Never>?
    var deliveries = 0
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil,
        permission: { .authorized },
        diagnostics: { await withCheckedContinuation { pending = $0 } },
        deliver: { _ in deliveries += 1 })
    let request = Task { await service.sendTestReminder() }
    while pending == nil { await Task.yield() }
    service.setDemoSuspended(true)
    service.setDemoSuspended(false)
    pending?.resume(returning: "test")
    await request.value
    #expect(deliveries == 0)
    #expect(!service.testingReminder)
    #expect(service.testReminderStatus.isEmpty)
}

@Test func demoFixturesAreExplicitAndUseRelativeDates() {
    let now = Date(timeIntervalSince1970: 1800000000)
    let demo = DemoSession(now: now)
    #expect(demo.usage.secondaryRemainingPercent == 0.59)
    #expect(demo.usage.primary?.resetsAt == Int64(now.timeIntervalSince1970 + 7200))
    #expect(demo.entries.allSatisfy { $0.id.hasPrefix("demo-") && $0.sourceURL.isEmpty })
    #expect(demo.entries.allSatisfy { $0.title.zh.contains("示例") })
    #expect(demo.changes.count == 2)
    #expect(demo.changes.first?.to == 59)
}

@Test func normalPetStateIsNotDemoByDefault() {
    var state = PetState(DemoSession().usage)
    #expect(!state.isDemo)
    state.isDemo = true
    #expect(state.isDemo)
    #expect(state.remaining == 59)
}

@Test func demoBoundaryPreservesJournalWithoutInventingAChange() {
    var journal = PetQuotaJournal()
    let sample = DemoSession().usage
    journal.observe(PetState(sample))
    let changed = UsageData(primary: sample.primary,
                            secondary: .init(usedPercent: 50, windowDurationMins: 10080, resetsAt: sample.secondary!.resetsAt),
                            planType: sample.planType, hasCredits: false, creditBalance: nil,
                            lastUpdated: sample.lastUpdated, dataSource: .appServer)
    journal.observe(PetState(changed))
    let before = journal.changes.count
    #expect(before == 1)
    journal.breakContinuity()
    journal.observe(PetState(sample))
    #expect(journal.changes.count == before)
}

@Test @MainActor func demoSuspendsAnnouncementsWithoutChangingPreferences() async {
    let suite = "demo-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "announcements.enabled")
    var fetches = 0
    var notifications = 0
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil,
        fetch: { fetches += 1; return Data("{\"version\":1,\"announcements\":[]}".utf8) },
        permission: { .authorized }, deliver: { _ in notifications += 1 })
    service.setDemoSuspended(true)
    await service.check()
    await service.setEnabled(false)
    await service.sendTestReminder()
    #expect(fetches == 0 && notifications == 0)
    #expect(service.enabled)
    #expect(defaults.data(forKey: "announcements.cache") == nil)
    service.setDemoSuspended(false)
    await service.check()
    #expect(fetches == 1)
}

@Test @MainActor func inFlightAnnouncementCannotWriteAfterEnteringDemo() async {
    let suite = "demo-flight-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var pending: CheckedContinuation<Data, Never>?
    let service = AnnouncementService(defaults: defaults, localFeedURL: nil,
        fetch: { await withCheckedContinuation { pending = $0 } }, permission: { .denied })
    let check = Task { await service.check() }
    while pending == nil { await Task.yield() }
    service.setDemoSuspended(true)
    service.setDemoSuspended(false)
    pending?.resume(returning: Data("{\"version\":1,\"announcements\":[]}".utf8))
    await check.value
    #expect(service.lastSuccess == nil)
    #expect(defaults.data(forKey: "announcements.cache") == nil)
}
