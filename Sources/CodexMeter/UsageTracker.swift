import Foundation
import Combine
import AppKit
import StoreKit

// MARK: - Data Models

enum AppLanguage: String {
    case chinese
    case english
}

enum AppServerError {
    case codexNotFound
    case launchFailed
}

func locateCodexBinary(
    homeDirectory: String = NSHomeDirectory(),
    environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
    applicationDirectories: [String]? = nil,
    systemBinaryPaths: [String]? = nil,
    fileManager: FileManager = .default
) -> String? {
    var candidates: [String] = []

    if let environmentPath {
        candidates += environmentPath
            .split(separator: ":")
            .map { "\($0)/codex" }
    }

    candidates += systemBinaryPaths ?? [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "/opt/local/bin/codex",
        "\(homeDirectory)/.codex/bin/codex",
        "\(homeDirectory)/.local/bin/codex",
        "\(homeDirectory)/.npm-global/bin/codex",
        "\(homeDirectory)/.volta/bin/codex",
        "\(homeDirectory)/.bun/bin/codex",
        "\(homeDirectory)/.asdf/shims/codex",
        "\(homeDirectory)/.nodenv/shims/codex",
        "\(homeDirectory)/Library/pnpm/codex"
    ]

    let appDirectories = applicationDirectories ?? [
        "/Applications",
        "\(homeDirectory)/Applications"
    ]
    for directory in appDirectories {
        candidates += [
            "\(directory)/ChatGPT.app/Contents/Resources/codex",
            "\(directory)/Codex.app/Contents/Resources/codex"
        ]
    }

    let versionedInstallRoots: [(root: String, suffix: String)] = [
        ("\(homeDirectory)/.nvm/versions/node", "bin/codex"),
        ("\(homeDirectory)/.local/share/fnm/node-versions", "installation/bin/codex"),
        ("\(homeDirectory)/Library/Application Support/fnm/node-versions", "installation/bin/codex"),
        ("\(homeDirectory)/.local/share/mise/installs/node", "bin/codex"),
        ("\(homeDirectory)/.asdf/installs/nodejs", "bin/codex"),
        ("\(homeDirectory)/.nodenv/versions", "bin/codex")
    ]
    for installRoot in versionedInstallRoots {
        guard let versions = try? fileManager.contentsOfDirectory(atPath: installRoot.root) else { continue }
        candidates += versions.sorted(by: >).map {
            "\(installRoot.root)/\($0)/\(installRoot.suffix)"
        }
    }

    let editorExtensionRoots = [
        "\(homeDirectory)/.vscode/extensions",
        "\(homeDirectory)/.vscode-insiders/extensions",
        "\(homeDirectory)/.cursor/extensions",
        "\(homeDirectory)/.windsurf/extensions"
    ]
    for extensionsRoot in editorExtensionRoots {
        guard let extensions = try? fileManager.contentsOfDirectory(atPath: extensionsRoot) else { continue }
        for extensionName in extensions.filter({ $0.hasPrefix("openai.chatgpt-") }).sorted(by: >) {
            candidates += [
                "\(extensionsRoot)/\(extensionName)/bin/macos-aarch64/codex",
                "\(extensionsRoot)/\(extensionName)/bin/macos-x86_64/codex"
            ]
        }
    }

    var checked = Set<String>()
    return candidates.first { path in
        checked.insert(path).inserted && fileManager.fileExists(atPath: path)
    }
}

struct RateLimitWindow {
    let usedPercent: Int          // 0-100, percentage already used
    let windowDurationMins: Int   // e.g. 300 for 5h, 10080 for 7d
    let resetsAt: Int64           // Unix timestamp in seconds
}

func normalizeRateLimitWindows(
    _ first: RateLimitWindow?,
    _ second: RateLimitWindow?
) -> (primary: RateLimitWindow?, secondary: RateLimitWindow?) {
    let windows = [first, second].compactMap { $0 }
    let shortWindow = windows
        .filter { $0.windowDurationMins < 1_440 }
        .min { $0.windowDurationMins < $1.windowDurationMins }
    let longWindow = windows
        .filter { $0.windowDurationMins >= 1_440 }
        .max { $0.windowDurationMins < $1.windowDurationMins }
    return (shortWindow, longWindow)
}

struct UsageData {
    let primary: RateLimitWindow?    // 5-hour window
    let secondary: RateLimitWindow?  // weekly window
    let planType: String?
    let hasCredits: Bool
    let creditBalance: String?
    let lastUpdated: Date
    let dataSource: DataSource

    enum DataSource {
        case loading     // Connecting to app-server
        case appServer   // Live data from codex app-server
        case config      // Manual config fallback
        case error       // Connection error
    }

    // Remaining percent (0.0 - 1.0)
    var primaryRemainingPercent: Double {
        guard let p = primary else { return 0 }
        return max(0, Double(100 - p.usedPercent)) / 100.0
    }

    var secondaryRemainingPercent: Double {
        guard let s = secondary else { return 0 }
        return max(0, Double(100 - s.usedPercent)) / 100.0
    }

    // Used percent (0.0 - 1.0) for progress bar
    var primaryUsedPercent: Double {
        guard let p = primary else { return 0 }
        return min(1.0, Double(p.usedPercent) / 100.0)
    }

    var secondaryUsedPercent: Double {
        guard let s = secondary else { return 0 }
        return min(1.0, Double(s.usedPercent) / 100.0)
    }

    // Formatted reset time
    func primaryResetFormatted(language: AppLanguage) -> String {
        guard let p = primary else { return "" }
        return formatResetTime(p.resetsAt, durationMins: p.windowDurationMins, language: language)
    }

    func secondaryResetFormatted(language: AppLanguage) -> String {
        guard let s = secondary else { return "" }
        return formatResetTime(s.resetsAt, durationMins: s.windowDurationMins, language: language)
    }

    func primaryWindowLabel(language: AppLanguage) -> String {
        guard let p = primary else { return language == .chinese ? "5小时" : "5-hour" }
        let hours = p.windowDurationMins / 60
        return language == .chinese ? "\(hours)小时" : "\(hours)-hour"
    }

    func secondaryWindowLabel(language: AppLanguage) -> String {
        guard let s = secondary else { return language == .chinese ? "1周" : "Weekly" }
        let days = s.windowDurationMins / 1440
        if days == 7 { return language == .chinese ? "1周" : "Weekly" }
        return language == .chinese ? "\(days)天" : "\(days)-day"
    }

    private func formatResetTime(_ timestamp: Int64, durationMins: Int, language: AppLanguage) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 { return language == .chinese ? "已重置" : "Reset" }

        let formatter = DateFormatter()

        if durationMins <= 300 {
            // Short window — show time HH:mm
            formatter.dateFormat = "HH:mm"
            let time = formatter.string(from: date)
            return language == .chinese ? "重置于 \(time)" : "Resets at \(time)"
        } else {
            // Long window — show date
            formatter.locale = Locale(identifier: language == .chinese ? "zh_CN" : "en_US")
            formatter.dateFormat = language == .chinese ? "M月d日" : "MMM d"
            let dateText = formatter.string(from: date)
            return language == .chinese ? "重置于 \(dateText)" : "Resets on \(dateText)"
        }
    }
}

func appServerNeedsRestart(
    dataSource: UsageData.DataSource,
    lastUpdated: Date,
    serverStartedAt: Date?,
    now: Date = Date(),
    staleAfter: TimeInterval = 120,
    startupTimeout: TimeInterval = 15
) -> Bool {
    switch dataSource {
    case .appServer:
        return now.timeIntervalSince(lastUpdated) > staleAfter
    case .loading:
        guard let serverStartedAt else { return false }
        return now.timeIntervalSince(serverStartedAt) > startupTimeout
    case .config, .error:
        return false
    }
}

// MARK: - UsageTracker

class UsageTracker: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
    }

    @Published var usage: UsageData = UsageData(
        primary: nil,
        secondary: nil,
        planType: nil,
        hasCredits: false,
        creditBalance: nil,
        lastUpdated: Date(),
        dataSource: .loading
    )

    @Published var showSettings = false
    @Published var detailsOnLeft = false
    @Published private(set) var appServerError: AppServerError?

    #if MAC_APP_STORE
    let usesStoreAuthentication = true
    #else
    let usesStoreAuthentication = false
    #endif
    @Published var storeLoginState: StoreLoginState = .connecting
    @Published var skipStoreLogin = false
    @Published private(set) var accountRegionAccess: AccountRegionAccess = .unknown
    private var storeAccount: StoreAccountController?
    private var storefrontTask: Task<Void, Never>?
    var demoSuspended = false
    var exitDemoBeforeLogin: (() -> Void)?
    private var demoAccountTransition: Task<Void, Never>?
    func suspendForDemo() {
        demoSuspended = true
        if usesStoreAuthentication {
            demoAccountTransition = Task { @MainActor in
                guard self.demoSuspended else { return }
                self.storeAccount?.stop()
            }
        }
        else { stopAppServer() }
    }
    func resumeAfterDemo() {
        demoSuspended = false
        usage = UsageData(primary: nil, secondary: nil, planType: nil, hasCredits: false,
                          creditBalance: nil, lastUpdated: Date(), dataSource: .loading)
        if usesStoreAuthentication {
            let suspension = demoAccountTransition
            demoAccountTransition = Task { @MainActor in
                await suspension?.value
                guard !self.demoSuspended else { return }
                guard self.canUsePersonalQuota else { return }
                await self.storeAccount?.start()
            }
        }
        else { startAppServer() }
    }
    var canUsePersonalQuota: Bool { !usesStoreAuthentication || accountRegionAccess.allowsPersonalQuota }
    var isStoreRegionRestricted: Bool { usesStoreAuthentication && !canUsePersonalQuota }
    var needsStoreLogin: Bool { usesStoreAuthentication && canUsePersonalQuota && storeLoginState != .signedIn && !skipStoreLogin }

    var storeRegionNotice: String {
        switch accountRegionAccess {
        case .unknown: return language == .chinese
            ? "当前 App Store 区域未确认，个人额度连接暂不可用。演示与公开消息仍可使用。"
            : "The App Store region is not confirmed, so personal quota access is temporarily unavailable. Demo and public updates remain available."
        case .restricted: return language == .chinese
            ? "当前 App Store 区域暂不提供个人额度连接。演示与公开消息仍可使用。"
            : "Personal quota access is unavailable in the current App Store region. Demo and public updates remain available."
        case .available: return ""
        }
    }

    func updateStorefrontCountryCode(_ countryCode: String?) {
        let previousAccess = accountRegionAccess
        let newAccess = AccountRegionAccess(countryCode: countryCode)
        guard newAccess != previousAccess else { return }
        accountRegionAccess = newAccess
        guard usesStoreAuthentication else { return }

        if newAccess.allowsPersonalQuota {
            guard previousAccess != .available else { return }
            let transition = demoAccountTransition
            demoAccountTransition = Task { @MainActor in
                await transition?.value
                guard !self.demoSuspended, self.canUsePersonalQuota else { return }
                await self.storeAccount?.start()
            }
        } else {
            demoAccountTransition = Task { @MainActor in
                self.storeAccount?.stop()
                self.storeLoginState = .signedOut
                self.clearStoreQuota()
            }
        }
    }

    private func clearStoreQuota() {
        latestRateLimits = [:]
        usage = UsageData(primary: nil, secondary: nil, planType: nil, hasCredits: false,
                          creditBalance: nil, lastUpdated: Date(), dataSource: .error)
    }

    func loginToStoreAccount() {
        guard canUsePersonalQuota else { return }
        if demoSuspended { exitDemoBeforeLogin?() }
        let transition = demoAccountTransition
        Task { @MainActor in
            await transition?.value
            guard !self.demoSuspended, self.canUsePersonalQuota else { return }
            await storeAccount?.login()
        }
    }
    func cancelStoreLogin() { guard canUsePersonalQuota else { return }; Task { @MainActor in await storeAccount?.cancelLogin() } }
    func reopenStoreLogin() { guard canUsePersonalQuota else { return }; Task { @MainActor in storeAccount?.reopenLogin() } }
    func logoutStoreAccount() { guard canUsePersonalQuota else { return }; Task { @MainActor in await storeAccount?.logout() } }
    func reloginStoreAccount() { guard canUsePersonalQuota else { return }; Task { @MainActor in await storeAccount?.relogin() } }
    func stopStoreAccount() { Task { @MainActor in storeAccount?.stop() } }

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextRequestId = 1
    private var pendingResponses: [Int: ( [String: Any]) -> Void] = [:]
    private var responseBuffer = ""
    private let lock = NSLock()
    private var refreshTimer: Timer?
    private var isInitialized = false
    private var latestRateLimits: [String: Any] = [:]
    private var appServerStartedAt: Date?

    init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        language = AppLanguage(rawValue: savedLanguage ?? "") ?? .chinese
        if usesStoreAuthentication {
            Task { @MainActor in
                let account = StoreAccountController(canAccessAccount: { [weak self] in
                    self?.canUsePersonalQuota == true
                })
                self.storeAccount = account
                account.onState = { [weak self] state in
                    guard let self else { return }
                    guard self.canUsePersonalQuota else { return }
                    self.storeLoginState = state
                    if state != .signedIn {
                        self.latestRateLimits = [:]
                        self.usage = UsageData(primary: nil, secondary: nil, planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: .error)
                    }
                }
                account.onQuota = { [weak self] limits in
                    guard self?.canUsePersonalQuota == true else { return }
                    self?.applyRateLimits(limits, isPartialUpdate: false)
                }
                account.onQuotaFailure = { [weak self] in
                    self?.usage = UsageData(primary: nil, secondary: nil, planType: nil, hasCredits: false, creditBalance: nil, lastUpdated: Date(), dataSource: .error)
                }
                account.onLogoutFailure = { [weak self] in
                    guard let self else { return }
                    let alert = NSAlert()
                    alert.messageText = self.language == .chinese ? "退出未完成" : "Sign-out failed"
                    alert.informativeText = self.language == .chinese ? "账号仍处于登录状态，请重试。" : "The account remains signed in. Please retry."
                    alert.runModal()
                }
                self.storefrontTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    let current = await Storefront.current
                    self.updateStorefrontCountryCode(current?.countryCode)
                    for await storefront in Storefront.updates {
                        guard !Task.isCancelled else { break }
                        self.updateStorefrontCountryCode(storefront.countryCode)
                    }
                }
            }
        } else { startAppServer() }
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
    }

    deinit {
        storefrontTask?.cancel()
        stopAppServer()
    }

    // MARK: - App Server Management

    private func findCodexBinary() -> String? {
        if let path = locateCodexBinary() {
            print("[CodexMeter] Found codex at: \(path)")
            return path
        }
        print("[CodexMeter] Could not find codex binary")
        return nil
    }

    private func startAppServer() {
        guard !demoSuspended else { return }
        appServerError = nil
        guard let codexPath = findCodexBinary() else {
            print("[CodexMeter] codex binary not found")
            DispatchQueue.main.async {
                self.appServerError = .codexNotFound
                self.usage = UsageData(
                    primary: nil, secondary: nil,
                    planType: nil, hasCredits: false, creditBalance: nil,
                    lastUpdated: Date(), dataSource: .error
                )
            }
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: codexPath)
        proc.arguments = ["app-server"]

        // Set PATH so that codex's shebang (#!/usr/bin/env node) can find node
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let codexDirectory = URL(fileURLWithPath: codexPath).deletingLastPathComponent().path
        env["PATH"] = [codexDirectory, "/opt/homebrew/bin", "/usr/local/bin", path]
            .joined(separator: ":")
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = Pipe() // Suppress stderr
        proc.terminationHandler = { [weak self, weak proc] _ in
            guard let self, let proc, self.process === proc else { return }
            DispatchQueue.main.async {
                self.process = nil
                self.isInitialized = false
                self.appServerError = .launchFailed
                self.usage = UsageData(
                    primary: nil, secondary: nil,
                    planType: nil, hasCredits: false, creditBalance: nil,
                    lastUpdated: Date(), dataSource: .error
                )
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            self?.handleStdout(text)
        }

        do {
            try proc.run()
            self.process = proc
            self.stdinPipe = stdin
            self.stdoutPipe = stdout
            self.appServerStartedAt = Date()
            print("[CodexMeter] app-server started (PID: \(proc.processIdentifier))")

            // Send initialize
            sendInitialize()

            // Start periodic refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.refresh()
                self?.startRefreshTimer()
            }
        } catch {
            print("[CodexMeter] Failed to start app-server: \(error)")
            appServerError = .launchFailed
            usage = UsageData(
                primary: nil, secondary: nil,
                planType: nil, hasCredits: false, creditBalance: nil,
                lastUpdated: Date(), dataSource: .error
            )
        }
    }

    private func stopAppServer() {
        refreshTimer?.invalidate()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        let runningProcess = process
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        appServerStartedAt = nil
        isInitialized = false
        latestRateLimits = [:]
        responseBuffer = ""

        lock.lock()
        pendingResponses.removeAll()
        lock.unlock()

        runningProcess?.terminate()
    }

    private func restartAppServer() {
        print("[CodexMeter] app-server response timed out; restarting")
        stopAppServer()
        usage = UsageData(
            primary: nil, secondary: nil,
            planType: nil, hasCredits: false, creditBalance: nil,
            lastUpdated: Date(), dataSource: .loading
        )
        startAppServer()
    }

    // MARK: - JSON-RPC Communication

    private func sendJSON(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let str = String(data: data, encoding: .utf8) else { return }
        guard let pipe = stdinPipe else { return }
        pipe.fileHandleForWriting.write("\(str)\n".data(using: .utf8)!)
    }

    private func sendRPC(method: String, params: [String: Any] = [:], completion: @escaping ([String: Any]) -> Void) {
        let id = nextRequestId
        nextRequestId += 1

        lock.lock()
        pendingResponses[id] = completion
        lock.unlock()

        var msg: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "id": id
        ]
        if !params.isEmpty {
            msg["params"] = params
        }
        sendJSON(msg)
    }

    private func sendNotification(method: String, params: [String: Any] = [:]) {
        var msg: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if !params.isEmpty {
            msg["params"] = params
        }
        sendJSON(msg)
    }

    private func handleStdout(_ text: String) {
        responseBuffer += text

        while let newlineIndex = responseBuffer.firstIndex(of: "\n") {
            let line = String(responseBuffer[..<newlineIndex])
            responseBuffer = String(responseBuffer[responseBuffer.index(after: newlineIndex)...])

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            handleJSONMessage(json)
        }
    }

    private func handleJSONMessage(_ json: [String: Any]) {
        // Check if it's a response (has "id" and "result" or "error")
        if let id = json["id"] as? Int {
            lock.lock()
            let completion = pendingResponses.removeValue(forKey: id)
            lock.unlock()

            if let completion = completion {
                completion(json)
            }
            return
        }

        // Check if it's a notification (has "method" but no "id")
        if let method = json["method"] as? String {
            handleNotification(method: method, params: json["params"] as? [String: Any] ?? [:])
        }
    }

    private func handleNotification(method: String, params: [String: Any]) {
        switch method {
        case "account/rateLimits/updated":
            // Notifications are sparse. Merge them into the latest full snapshot
            // before classifying the windows.
            if let rateLimits = params["rateLimits"] as? [String: Any] {
                applyRateLimits(rateLimits, isPartialUpdate: true)
            }
        default:
            break // Ignore other notifications
        }
    }

    // MARK: - Initialization

    private func sendInitialize() {
        sendRPC(method: "initialize", params: [
            "clientInfo": [
                "name": "codex_limit_meter",
                "title": "Codex Meter",
                "version": "1.1.3"
            ]
        ]) { [weak self] response in
            if response["result"] != nil {
                print("[CodexMeter] Initialized successfully")
                // Send initialized notification
                self?.sendNotification(method: "initialized", params: [:])
                self?.isInitialized = true
                // Immediately fetch rate limits
                self?.fetchRateLimits()
            } else if let error = response["error"] {
                print("[CodexMeter] Init error: \(error)")
            }
        }
    }

    // MARK: - Rate Limits

    private func fetchRateLimits() {
        sendRPC(method: "account/rateLimits/read") { [weak self] response in
            guard let result = response["result"] as? [String: Any] else {
                print("[CodexMeter] No result in rate limits response")
                return
            }

            if let rateLimits = result["rateLimits"] as? [String: Any] {
                self?.applyRateLimits(rateLimits, isPartialUpdate: false)
            }
        }
    }

    private func applyRateLimits(_ rateLimits: [String: Any], isPartialUpdate: Bool) {
        guard !demoSuspended, canUsePersonalQuota else { return }
        latestRateLimits = isPartialUpdate
            ? mergeRateLimits(latestRateLimits, with: rateLimits)
            : rateLimits

        let serverPrimary = parseWindow(
            latestRateLimits["primary"] as? [String: Any],
            fallbackDurationMins: 300
        )
        let serverSecondary = parseWindow(
            latestRateLimits["secondary"] as? [String: Any],
            fallbackDurationMins: 10_080
        )
        let (primary, secondary) = normalizeRateLimitWindows(serverPrimary, serverSecondary)
        guard primary != nil || secondary != nil else {
            DispatchQueue.main.async {
                self.usage = UsageData(primary: nil, secondary: nil, planType: nil,
                                       hasCredits: false, creditBalance: nil,
                                       lastUpdated: Date(), dataSource: .error)
            }
            return
        }
        let planType = latestRateLimits["planType"] as? String
        let credits = latestRateLimits["credits"] as? [String: Any]
        let hasCredits = credits?["hasCredits"] as? Bool ?? false
        let balance = credits?["balance"] as? String

        DispatchQueue.main.async {
            self.usage = UsageData(
                primary: primary,
                secondary: secondary,
                planType: planType,
                hasCredits: hasCredits,
                creditBalance: balance,
                lastUpdated: Date(),
                dataSource: .appServer
            )
            print("[CodexMeter] Updated: primary=\(primary?.usedPercent ?? -1)%, secondary=\(secondary?.usedPercent ?? -1)%")
        }
    }

    private func parseWindow(_ dict: [String: Any]?, fallbackDurationMins: Int) -> RateLimitWindow? {
        guard let dict = dict else { return nil }
        guard let usedPercent = dict["usedPercent"] as? Int else { return nil }
        let durationMins = dict["windowDurationMins"] as? Int ?? fallbackDurationMins
        let resetsAt = Int64(dict["resetsAt"] as? Int ?? 0)
        return RateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMins: durationMins,
            resetsAt: resetsAt
        )
    }

    private func mergeRateLimits(
        _ current: [String: Any],
        with update: [String: Any]
    ) -> [String: Any] {
        var merged = current
        for (key, value) in update {
            if let existingObject = merged[key] as? [String: Any],
               let updatedObject = value as? [String: Any] {
                merged[key] = mergeRateLimits(existingObject, with: updatedObject)
            } else {
                merged[key] = value
            }
        }
        return merged
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !demoSuspended else { return }
        if usesStoreAuthentication {
            guard canUsePersonalQuota else { return }
            Task { @MainActor in await storeAccount?.refresh() }
            return
        }
        if process != nil,
           appServerNeedsRestart(
               dataSource: usage.dataSource,
               lastUpdated: usage.lastUpdated,
               serverStartedAt: appServerStartedAt
           ) {
            restartAppServer()
            return
        }

        guard isInitialized else {
            if process == nil {
                usage = UsageData(
                    primary: nil, secondary: nil,
                    planType: nil, hasCredits: false, creditBalance: nil,
                    lastUpdated: Date(), dataSource: .loading
                )
                startAppServer()
            }
            return
        }
        fetchRateLimits()
    }

    func appServerErrorText(language: AppLanguage) -> String {
        switch appServerError {
        case .codexNotFound:
            return language == .chinese ? "未找到 Codex · 点击重试" : "Codex not found · Click to retry"
        case .launchFailed:
            return language == .chinese ? "Codex 启动失败 · 点击重试" : "Codex failed to start · Click to retry"
        case nil:
            return language == .chinese ? "更新失败 · 点击重试" : "Update failed · Click to retry"
        }
    }

    func openConfigFolder() {
        let configDir = "\(NSHomeDirectory())/.config/codex-limit-meter"
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: configDir))
    }
}
