import AppKit
import Testing
@testable import CodexMeter

@Test func savedPositionPreservesExternalCoordinatesAndRejectsInvalidData() {
    #expect(savedPetOrigin([-1200, 80]) == NSPoint(x: -1200, y: 80))
    #expect(savedPetOrigin(nil) == nil)
    #expect(savedPetOrigin([1]) == nil)
    #expect(savedPetOrigin([.nan, 2]) == nil)
    #expect(savedPetOrigin([1, .infinity]) == nil)
}

@Test func sleepAnchorIsIndependentOfDetailCardSide() {
    let screen = NSRect(x: 1920, y: 30, width: 1920, height: 1080)
    let right = NSRect(x: 3100, y: 400, width: 600, height: 410)
    let left = NSRect(x: 2830, y: 400, width: 600, height: 410)
    let saved = petAnchorOffset(frame: right, surfaceOffset: 0, screen: screen)
    #expect(saved == petAnchorOffset(frame: left, surfaceOffset: 270, screen: screen))
    #expect(screen.minX + saved.x == 3100)
    #expect(screen.minY + saved.y == 400)
}

@Test func displayIdentitySurvivesTransientIDChangesAfterWake() {
    let beforeSleep = PetDisplayIdentity(stableUUID: "external-display", transientID: 2)
    let afterWake = PetDisplayIdentity(stableUUID: "external-display", transientID: 9)
    let internalDisplay = PetDisplayIdentity(stableUUID: "internal-display", transientID: 1)

    #expect(beforeSleep.matches(afterWake))
    #expect(!beforeSleep.matches(internalDisplay))
}

@Test func displayIdentityFallsBackToTransientIDWhenUUIDIsUnavailable() {
    let saved = PetDisplayIdentity(stableUUID: nil, transientID: 2)
    #expect(saved.matches(PetDisplayIdentity(stableUUID: nil, transientID: 2)))
    #expect(!saved.matches(PetDisplayIdentity(stableUUID: nil, transientID: 3)))
}
