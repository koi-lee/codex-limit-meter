import AppKit
import Testing
@testable import CodexMeter

@Test func floatingCardStaysInsideAllEdgesAndCorners() {
    let visible = NSRect(x: 0, y: 80, width: 1440, height: 796)
    for x in [-1000.0, 0, 500, 1400, 2000] {
        for y in [-1000.0, 0, 300, 850, 2000] {
            let result = boundedFloatingFrame(NSRect(x: x, y: y, width: 320, height: 280), visibleFrame: visible)
            #expect(visible.insetBy(dx: 8, dy: 8).contains(result))
            #expect(result.size == NSSize(width: 320, height: 280))
        }
    }
}

@Test func floatingCardPreservesInteriorAndHandlesExternalDisplay() {
    let external = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
    let interior = NSRect(x: -1000, y: 200, width: 350, height: 370)
    #expect(boundedFloatingFrame(interior, visibleFrame: external) == interior)
    let crossed = boundedFloatingFrame(NSRect(x: -50, y: -400, width: 350, height: 370), visibleFrame: external)
    #expect(external.insetBy(dx: 8, dy: 8).contains(crossed))
    #expect(crossed.origin == NSPoint(x: -358, y: -192))
}

@Test func dragReversesImmediatelyAfterPushingAgainstEdge() {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = NSRect(x: 1112, y: 300, width: 320, height: 280)
    let pushed = floatingDragFrame(frame, from: NSPoint(x: 1300, y: 400), to: NSPoint(x: 1430, y: 400), visibleFrame: screen)
    #expect(pushed == frame)
    let reversed = floatingDragFrame(pushed, from: NSPoint(x: 1430, y: 400), to: NSPoint(x: 1420, y: 405), visibleFrame: screen)
    #expect(reversed.origin == NSPoint(x: 1102, y: 305))
}
