import Foundation
import Testing
@testable import CodexMeter

@Test func codexRateLimitsAcceptsPrimaryOnlyAndIgnoresOtherBuckets() {
    let result: [String: Any] = [
        "rateLimits": ["primary": ["usedPercent": 90]],
        "rateLimitsByLimitId": [
            "codex": ["primary": ["usedPercent": 0, "windowDurationMins": 300]],
            "codex_other": NSNull()
        ]
    ]
    let limits = StoreAccountController.codexRateLimits(in: result)
    #expect((limits?["primary"] as? [String: Any])?["usedPercent"] as? Int == 0)
}

@Test func codexRateLimitsRejectsMissingOrMalformedWindows() {
    #expect(StoreAccountController.codexRateLimits(in: ["rateLimits": ["primary": NSNull()]]) == nil)
    #expect(StoreAccountController.codexRateLimits(in: ["rateLimits": ["primary": ["usedPercent": "0"]]]) == nil)
    let fallback = StoreAccountController.codexRateLimits(in: [
        "rateLimitsByLimitId": ["codex": ["primary": NSNull()]],
        "rateLimits": ["secondary": ["usedPercent": 0]]
    ])
    #expect((fallback?["secondary"] as? [String: Any])?["usedPercent"] as? Int == 0)
}

@MainActor @Test func repeatedLoginReopensPendingBrowserPage() async {
    var opened = 0
    var requests = 0
    let account = StoreAccountController(request: { _, _ in
        requests += 1
        return ["loginId": "test", "authUrl": "https://auth.openai.com/test"]
    }, openURL: { _ in opened += 1 })
    await account.login()
    await account.login()
    #expect(account.state == .waiting)
    #expect(requests == 1)
    #expect(opened == 2)
    account.stop()
}

@MainActor @Test func storeHelperDisablesOptionalTelemetry() {
    #expect(StoreAccountController.helperArguments == [
        "app-server", "-c", "cli_auth_credentials_store=\"file\"",
        "-c", "analytics.enabled=false",
        "-c", "otel.exporter=\"none\"",
        "-c", "otel.trace_exporter=\"none\"",
        "-c", "otel.metrics_exporter=\"none\"",
        "-c", "otel.log_user_prompt=false"
    ])
}

@Test func loginOnlyOpensOfficialHTTPSHosts() {
    #expect(approvedLoginURL("https://auth.openai.com/oauth/authorize?state=test") != nil)
    for url in ["http://auth.openai.com/", "https://auth.openai.com.evil.test/", "https://user:secret@auth.openai.com/", "file:///tmp/a", "https://auth.openai.com:8080/"] {
        #expect(approvedLoginURL(url) == nil)
    }
}

@MainActor @Test func cancelledLoginCannotBeRestoredByLateSuccess() async throws {
    var methods: [String] = []
    var opened = 0
    let account = StoreAccountController(request: { method, _ in
        methods.append(method)
        return method == "account/login/start" ? ["loginId": "test", "authUrl": "https://auth.openai.com/test"] : [:]
    }, openURL: { _ in opened += 1 })
    await account.login()
    #expect(account.state == .waiting)
    #expect(opened == 1)
    await account.cancelLogin()
    account.receive(Data(#"{"method":"account/login/completed","params":{"loginId":"test","success":true}}"#.utf8) + Data([10]))
    #expect(account.state == .signedOut)
    #expect(methods == ["account/login/start", "account/login/cancel"])
    account.stop()
}

@MainActor @Test func loginSuccessFetchesQuotaAndLogoutIsScoped() async throws {
    var quotaReads = 0
    var methods: [String] = []
    let account = StoreAccountController(request: { method, _ in
        methods.append(method)
        if method == "account/login/start" { return ["loginId": "test", "authUrl": "https://auth.openai.com/test"] }
        if method == "account/rateLimits/read" { return ["rateLimits": ["primary": ["usedPercent": 10]]] }
        return [:]
    }, openURL: { _ in })
    account.onQuota = { _ in quotaReads += 1 }
    await account.login()
    account.receive(Data(#"{"method":"account/login/completed","params":{"loginId":"test","success":true}}"#.utf8) + Data([10]))
    #expect(account.state == .signedIn)
    await account.refresh()
    #expect(quotaReads == 1)
    await account.logout()
    #expect(account.state == .signedOut)
    #expect(methods.contains("account/logout"))
    account.stop()
}

@MainActor @Test func failedLogoutDoesNotPretendAccountWasRemoved() async {
    let account = StoreAccountController(request: { method, _ in
        if method == "account/login/start" { return ["loginId": "test", "authUrl": "https://auth.openai.com/test"] }
        throw StoreAccountController.Failure.rejected
    }, openURL: { _ in })
    await account.login()
    account.receive(Data(#"{"method":"account/login/completed","params":{"loginId":"test","success":true}}"#.utf8) + Data([10]))
    await account.logout()
    #expect(account.state == .signedIn)
    account.stop()
}

@MainActor @Test func explicitReloginWaitsForLogoutThenStartsOfficialLogin() async {
    var methods: [String] = []
    var opened = 0
    let account = StoreAccountController(request: { method, _ in
        methods.append(method)
        if method == "account/login/start" {
            return ["loginId": "test", "authUrl": "https://auth.openai.com/test"]
        }
        if method == "account/rateLimits/read" { return ["rateLimits": ["primary": ["usedPercent": 10]]] }
        return [:]
    }, openURL: { _ in opened += 1 })
    await account.login()
    account.receive(Data(#"{"method":"account/login/completed","params":{"loginId":"test","success":true}}"#.utf8) + Data([10]))
    await account.relogin()
    #expect(account.state == .waiting)
    #expect(methods.suffix(2) == ["account/logout", "account/login/start"])
    #expect(opened == 2)
    account.stop()
}

@MainActor @Test func explicitReloginDoesNotStartIfLogoutFails() async {
    var loginStarts = 0
    let account = StoreAccountController(request: { method, _ in
        if method == "account/login/start" {
            loginStarts += 1
            return ["loginId": "test", "authUrl": "https://auth.openai.com/test"]
        }
        if method == "account/rateLimits/read" { return ["rateLimits": ["primary": ["usedPercent": 10]]] }
        if method == "account/logout" { throw StoreAccountController.Failure.rejected }
        return [:]
    }, openURL: { _ in })
    await account.login()
    account.receive(Data(#"{"method":"account/login/completed","params":{"loginId":"test","success":true}}"#.utf8) + Data([10]))
    await account.relogin()
    #expect(account.state == .signedIn)
    #expect(loginStarts == 1)
    account.stop()
}

@MainActor @Test func quotaFailureIsVisibleWithoutInventingSignedOutState() async throws {
    var failures = 0
    let account = StoreAccountController(request: { method, _ in
        if method == "account/login/start" { return ["loginId": "test", "authUrl": "https://auth.openai.com/test"] }
        if method == "account/read" { return ["account": ["type": "chatgpt"]] }
        throw StoreAccountController.Failure.timeout
    }, openURL: { _ in })
    account.onQuotaFailure = { failures += 1 }
    await account.login()
    account.receive(Data(#"{"method":"account/login/completed","params":{"loginId":"test","success":true}}"#.utf8) + Data([10]))
    for _ in 0..<100 where failures == 0 { await Task.yield() }
    await account.refresh()
    #expect(failures >= 1)
    #expect(account.state == .signedIn)
    account.stop()
}

@MainActor @Test func quotaResponseWithoutWindowsIsReportedAsFailure() async {
    var failures = 0
    let account = StoreAccountController(request: { method, _ in
        if method == "account/login/start" { return ["loginId": "test", "authUrl": "https://auth.openai.com/test"] }
        if method == "account/rateLimits/read" { return ["rateLimits": ["primary": NSNull(), "secondary": NSNull()]] }
        return ["account": ["type": "chatgpt"]]
    }, openURL: { _ in })
    account.onQuotaFailure = { failures += 1 }
    await account.login()
    account.receive(Data(#"{"method":"account/login/completed","params":{"loginId":"test","success":true}}"#.utf8) + Data([10]))
    await account.refresh()
    #expect(failures >= 1)
    #expect(account.state == .signedIn)
    account.stop()
}

@MainActor @Test func quotaResponseAfterLogoutCannotRestoreOldAccountData() async throws {
    var held: CheckedContinuation<[String: Any], Error>?
    var delivered = 0
    let account = StoreAccountController(request: { method, _ in
        if method == "account/login/start" { return ["loginId": "test", "authUrl": "https://auth.openai.com/test"] }
        if method == "account/rateLimits/read" { return try await withCheckedThrowingContinuation { held = $0 } }
        return [:]
    }, openURL: { _ in })
    account.onQuota = { _ in delivered += 1 }
    await account.login()
    account.receive(Data(#"{"method":"account/login/completed","params":{"loginId":"test","success":true}}"#.utf8) + Data([10]))
    let read = Task { await account.refresh() }
    for _ in 0..<100 where held == nil { await Task.yield() }
    #expect(held != nil)
    await account.logout()
    held?.resume(returning: ["rateLimits": ["primary": ["usedPercent": 10]]])
    await read.value
    await Task.yield()
    #expect(delivered == 0)
    #expect(account.state == .signedOut)
    account.stop()
}
