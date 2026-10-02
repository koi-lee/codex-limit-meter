import Foundation
import AppKit
import Testing
@testable import CodexMeter

@Test func characterPreferencePreservesExistingReaderAndRejectsUnknownAssets() {
    let name = "test.character.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: name)!
    defer { preferences.removePersistentDomain(forName: name) }
    #expect(PetCharacter.selected(in: preferences) == .reader)
    preferences.set("archivist", forKey: PetCharacter.preferenceKey)
    #expect(PetCharacter.selected(in: preferences) == .archivist)
    #expect(PetCharacter.selected(in: UserDefaults(suiteName: name)!) == .archivist)
    preferences.set("../invalid", forKey: PetCharacter.preferenceKey)
    #expect(PetCharacter.selected(in: preferences) == .reader)
}
@Test func petQuotaKeepsErrorsUnknownAndUsesExistingWindowPriority() {
    func usage(_ used: Int, source: UsageData.DataSource = .appServer, weekly: Bool = true) -> UsageData {
        UsageData(primary: RateLimitWindow(usedPercent: weekly ? 99 : used, windowDurationMins: 300, resetsAt: 0), secondary: weekly ? RateLimitWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: 0) : nil, planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: source)
    }
    #expect(PetState(usage(0)).lamps == 3)
    #expect(PetState(usage(50)).remaining == 50)
    #expect(PetState(usage(50)).lamps == 2)
    #expect(PetState(usage(99)).lamps == 1)
    #expect(PetState(usage(100)).lamps == 0)
    #expect(PetState(usage(100)).remaining == 0)
    for source: UsageData.DataSource in [.error, .loading, .config] {
        #expect(PetState(usage(0, source: source)).remaining == nil)
        #expect(PetState(usage(0, source: source)).lamps == 0)
    }
    #expect(PetState(usage(60)).color == "#30D158")
    #expect(PetState(usage(61)).color == "#FF9F0A")
    #expect(PetState(usage(80)).color == "#FF9F0A")
    #expect(PetState(usage(81)).color == "#FF453A")
    #expect(PetState(usage(55, weekly: false)).label == "短期额度 45%")
    #expect(PetState(usage(-10)).remaining == 100)
    #expect(PetState(usage(150)).remaining == 0)
}

@Test func petDragUsesEventTravelNotCurrentCursorPolling() {
    #expect(!petGestureIsDrag(from: .zero, to: NSPoint(x: 2, y: 2)))
    #expect(petGestureIsDrag(from: .zero, to: NSPoint(x: 65, y: 25)))
    #expect(petGestureIsDrag(from: NSPoint(x: -1500, y: 200), to: NSPoint(x: -1450, y: 200)))
}

@Test func petResetUsesSelectedWindowAndHidesInvalidData() {
    let usage = UsageData(primary: RateLimitWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: 100), secondary: RateLimitWindow(usedPercent: 30, windowDurationMins: 10080, resetsAt: 200), planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: .appServer)
    #expect(PetState(usage).resetsAt == 200)
    let error = UsageData(primary: usage.primary, secondary: usage.secondary, planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: .error)
    #expect(PetState(error).resetsAt == nil)
}
