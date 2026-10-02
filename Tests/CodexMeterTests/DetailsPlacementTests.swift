import AppKit
import Testing
@testable import CodexMeter
@Test func detailsChooseSpaceOnOwningDisplay() {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    #expect(!detailsPreferLeft(parent: NSRect(x: 200, y: 300, width: 320, height: 280), screen: screen))
    #expect(detailsPreferLeft(parent: NSRect(x: 1100, y: 300, width: 320, height: 280), screen: screen))
    let external = NSRect(x: -1440, y: 200, width: 1440, height: 900)
    #expect(detailsPreferLeft(parent: NSRect(x: -340, y: 400, width: 320, height: 280), screen: external))
    #expect(!detailsPreferLeft(parent: NSRect(x: 768, y: 0, width: 320, height: 280), screen: screen))
    #expect(detailsPreferLeft(parent: NSRect(x: 769, y: 0, width: 320, height: 280), screen: screen))
}
