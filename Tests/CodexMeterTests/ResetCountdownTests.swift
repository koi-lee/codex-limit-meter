import Foundation
import Testing
@testable import CodexMeter
@Test func countdownDoesNotClaimExpiredWindowHasReset() {
    let now = Date(timeIntervalSince1970: 1000)
    #expect(quotaResetCountdown(reset: 999, now: now, chinese: true) == "等待服务端更新")
    #expect(quotaResetCountdown(reset: 1001, now: now, chinese: true) == "还有 1 分钟")
    #expect(quotaResetCountdown(reset: 91000, now: now, chinese: true) == "还有 1 天 1 小时")
    #expect(quotaExactDate(Date(timeIntervalSince1970: 0), chinese: true) == "1月1日 08:00（北京时间）")
}
