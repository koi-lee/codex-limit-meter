import AppKit
import Testing
@testable import CodexMeter

@Test func guideAndPetDoNotOverlapAcrossDisplays() {
    for screen in [NSRect(x: 0, y: 0, width: 1440, height: 875),
                   NSRect(x: -1280, y: 80, width: 1280, height: 720),
                   NSRect(x: 0, y: 0, width: 1024, height: 768),
                   NSRect(x: 0, y: 0, width: 700, height: 1000)] {
        let size = NSSize(width: screen.width < 760 ? 256 : 736, height: 410)
        let result = guidePetPlacement(guide: NSRect(x: 300, y: 300, width: 460, height: 388), screen: screen, petSize: size)
        let pet = NSRect(origin: result.petOrigin, size: NSSize(width: 256, height: 286))
        #expect(!result.guide.intersects(pet))
        #expect(screen.contains(result.guide))
        #expect(screen.contains(pet))
        if screen.width >= 760 {
            let expanded = NSRect(origin: result.petOrigin, size: NSSize(width: 736, height: 410))
            #expect(screen.contains(expanded))
            #expect(!result.guide.intersects(expanded))
        }
    }
}
