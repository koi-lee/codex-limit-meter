import Testing
@testable import CodexMeter
import Foundation
@Test @MainActor func unreadOrFailedFeedDoesNotClaimNoForecast() {
    let model = PetMessageModel()
    #expect(model.headline == "待读取")
    #expect(model.emptyMessage == "尚未获取消息，请点击刷新")
    model.checking = true
    #expect(model.emptyMessage == "正在获取最新消息…")
    model.checking = false
    model.failed = true
    #expect(model.headline == "待核对")
    #expect(model.emptyMessage.contains("暂不能确认"))
    model.failed = false
    model.checkedAt = Date()
    #expect(model.emptyMessage == "下一次重置：暂无新预告")
}
