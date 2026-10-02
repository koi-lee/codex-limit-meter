import Foundation
import Testing
@testable import CodexMeter

@Test func storefrontPolicyFailsClosedForUnknownAndMainlandChina() {
    #expect(AccountRegionAccess(countryCode: nil) == .unknown)
    #expect(AccountRegionAccess(countryCode: "CHN") == .restricted)
    #expect(AccountRegionAccess(countryCode: "chn") == .restricted)
    #expect(AccountRegionAccess(countryCode: "USA") == .available)
    #expect(AccountRegionAccess(countryCode: "JPN").allowsPersonalQuota)
}

@MainActor @Test func restrictedStorefrontBlocksAccountHelperAndLoginRequests() async {
    let canAccess = false
    var requests = 0
    var openedURLs = 0
    let account = StoreAccountController(request: { _, _ in
        requests += 1
        return ["loginId": "unexpected", "authUrl": "https://auth.openai.com/test"]
    }, openURL: { _ in openedURLs += 1 }, canAccessAccount: { canAccess })

    await account.start()
    await account.login()
    await account.refresh()
    account.reopenLogin()

    #expect(requests == 0)
    #expect(openedURLs == 0)
    #expect(account.state == .signedOut)
    account.stop()
}
