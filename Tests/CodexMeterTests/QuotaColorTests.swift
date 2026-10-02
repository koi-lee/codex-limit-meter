import Testing
@testable import CodexMeter
@Test func quotaColorsFollowRemainingRatherThanUsed() {
    #expect(quotaLevel(remaining: 78) == .healthy)
    #expect(quotaLevel(remaining: 40) == .healthy)
    #expect(quotaLevel(remaining: 39) == .warning)
    #expect(quotaLevel(remaining: 20) == .warning)
    #expect(quotaLevel(remaining: 19) == .critical)
    #expect(quotaLevel(remaining: 0) == .critical)
}
