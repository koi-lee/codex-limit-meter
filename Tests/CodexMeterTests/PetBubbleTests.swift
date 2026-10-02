import Testing
@testable import CodexMeter
import Foundation

private func bubbleEntry(_ id: String = "preview", revision: Int = 1, title: String = "重置预告", target: Date? = nil, status: String = "active", now: Date) -> Announcement {
    Announcement(id: id, revision: revision, title: .init(zh: title, en: title), summary: .init(zh: "消息", en: "News"), audience: .init(zh: "适用范围待核对", en: "Check scope"), sourceURL: "https://example.com/post", publishedAt: now.addingTimeInterval(-60), expiresAt: now.addingTimeInterval(3600), resetAt: target, status: status)
}
@Test func bubblesDeduplicateRevisionAndExcludeExpiredOrWithdrawn() {
    let now = Date(), entry = bubbleEntry(now: Date())
    #expect(PetBubblePolicy.candidate([entry], delivered: [:], now: now)?.id == entry.id)
    #expect(PetBubblePolicy.candidate([entry], delivered: [entry.id: 1], now: now) == nil)
    #expect(PetBubblePolicy.candidate([bubbleEntry(revision: 2, now: now)], delivered: [entry.id: 1], now: now)?.revision == 2)
    #expect(PetBubblePolicy.candidate([entry], delivered: [:], now: now.addingTimeInterval(7200)) == nil)
    #expect(PetBubblePolicy.candidate([bubbleEntry(status: "withdrawn", now: now)], delivered: [:], now: now) == nil)
}
@Test func bubbleCopyDoesNotInventResetTimeOrAccountArrival() {
    let now = Date()
    #expect(PetBubblePolicy.text(bubbleEntry(now: now)).contains("具体时间尚未公布"))
    #expect(PetBubblePolicy.text(bubbleEntry(title: "重置完成", now: now)).contains("账号是否到账"))
    #expect(PetBubblePolicy.candidate([bubbleEntry(target: now.addingTimeInterval(-5), now: now)], delivered: [:], now: now) == nil)
}

@Test func bubblePlacementAvoidsTopAndKeepsFrameOnScreen() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    for head in [CGPoint(x: 200, y: 500), CGPoint(x: 750, y: 940), CGPoint(x: 1450, y: 500)] {
        for expanded in [false, true] {
            let result = PetBubblePlacement.resolve(head: head, screen: screen, expanded: expanded, scale: 0.75)
            #expect(screen.contains(result.frame))
            if head.y == 940 { #expect(!result.showsBeads) }
        }
    }
    let closed = PetBubblePlacement.resolve(head: CGPoint(x: 750, y: 500), screen: screen, expanded: false, scale: 0.75)
    let opened = PetBubblePlacement.resolve(head: CGPoint(x: 750, y: 500), screen: screen, expanded: true, scale: 0.75)
    #expect(opened.frame.maxX < closed.frame.maxX)
    #expect(opened.frame.minY == closed.frame.minY)
}

@Test func bubbleAvoidsLeftDetailCardAfterWake() {
    let card = CGRect(x: 1234, y: 606, width: 254, height: 310)
    let result = PetBubblePlacement.resolve(head: CGPoint(x: 1598, y: 816),
        screen: CGRect(x: 0, y: 0, width: 1920, height: 1055), expanded: true, scale: 0.75, detailCard: card)
    #expect(!result.frame.intersects(card))
    #expect(result.frame.maxY <= 1047)
}

@Test func bubbleSearchesBeyondPreferredSlots() {
    for x in stride(from: 1100.0, through: 1700.0, by: 100) {
        for y in stride(from: 650.0, through: 950.0, by: 100) {
            let card = CGRect(x: x - 364, y: y - 210, width: 254, height: 310)
            let result = PetBubblePlacement.resolve(head: CGPoint(x: x, y: y),
                screen: CGRect(x: 0, y: 0, width: 1920, height: 1055), expanded: true, scale: 0.75, detailCard: card)
            #expect(!result.frame.intersects(card))
        }
    }
}
