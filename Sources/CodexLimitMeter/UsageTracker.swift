import Foundation
import Combine
import AppKit

// MARK: - Data Models

struct RateLimitWindow {
    let usedPercent: Int          // 0-100, percentage already used
    let windowDurationMins: Int   // e.g. 300 for 5h, 10080 for 7d
    let resetsAt: Int64           // Unix timestamp in seconds
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
    var primaryResetFormatted: String {
        guard let p = primary else { return "" }
        return formatResetTime(p.resetsAt, durationMins: p.windowDurationMins)
    }

    var secondaryResetFormatted: String {
        guard let s = secondary else { return "" }
        return formatResetTime(s.resetsAt, durationMins: s.windowDurationMins)
    }

    var primaryWindowLabel: String {
        guard let p = primary else { return "5小时" }
        let hours = p.windowDurationMins / 60
        return "\(hours)小时"
    }

    var secondaryWindowLabel: String {
        guard let s = secondary else { return "1周" }
        let days = s.windowDurationMins / 1440
        if days == 7 { return "1周" }
        return "\(days)天"
    }

    private func formatResetTime(_ timestamp: Int64, durationMins: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 { return "已重置" }

        let formatter = DateFormatter()

        if durationMins <= 300 {
            // Short window — show time HH:mm
            formatter.dateFormat = "HH:mm"
            return "重置于 \(formatter.string(from: date))"
        } else {
            // Long window — show date
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日"
            return "重置于 \(formatter.string(from: date))"
        }
    }
}

// MARK: - UsageTracker

class UsageTracker: ObservableObject {
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

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextRequestId = 1
    private var pendingResponses: [Int: ( [String: Any]) -> Void] = [:]
    private var responseBuffer = ""
    private let lock = NSLock()
    private var refreshTimer: Timer?
    private var isInitialized = false

    init() {
        startAppServer()
    }

    deinit {
        stopAppServer()
    }

    // MARK: - App Server Management

    private func findCodexBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.codex/bin/codex"
        ]
        for path in candidates {
            // Use fileExists instead of isExecutableFile because codex is a symlink
            // pointing to a Node.js script with a shebang
            if FileManager.default.fileExists(atPath: path) {
                print("[CodexLimitMeter] Found codex at: \(path)")
                return path
            }
        }
        // Try which
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["codex"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = path, !p.isEmpty, FileManager.default.fileExists(atPath: p) {
            print("[CodexLimitMeter] Found codex via which: \(p)")
            return p
        }
        print("[CodexLimitMeter] Could not find codex binary")
        return nil
    }

    private func startAppServer() {
        guard let codexPath = findCodexBinary() else {
            print("[CodexLimitMeter] codex binary not found")
            DispatchQueue.main.async {
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
        if !path.contains("/opt/homebrew/bin") {
            env["PATH"] = "/opt/homebrew/bin:\(path)"
        }
        if !path.contains("/usr/local/bin") {
            env["PATH"] = "/usr/local/bin:\(env["PATH"]!)"
        }
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = Pipe() // Suppress stderr

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
            print("[CodexLimitMeter] app-server started (PID: \(proc.processIdentifier))")

            // Send initialize
            sendInitialize()

            // Start periodic refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.refresh()
                self?.startRefreshTimer()
            }
        } catch {
            print("[CodexLimitMeter] Failed to start app-server: \(error)")
        }
    }

    private func stopAppServer() {
        refreshTimer?.invalidate()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
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
            // Live update notification
            if let rateLimits = params["rateLimits"] as? [String: Any] {
                applyRateLimits(rateLimits)
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
                "title": "Codex Limit Meter",
                "version": "1.0.0"
            ]
        ]) { [weak self] response in
            if response["result"] != nil {
                print("[CodexLimitMeter] Initialized successfully")
                // Send initialized notification
                self?.sendNotification(method: "initialized", params: [:])
                self?.isInitialized = true
                // Immediately fetch rate limits
                self?.fetchRateLimits()
            } else if let error = response["error"] {
                print("[CodexLimitMeter] Init error: \(error)")
            }
        }
    }

    // MARK: - Rate Limits

    private func fetchRateLimits() {
        sendRPC(method: "account/rateLimits/read") { [weak self] response in
            guard let result = response["result"] as? [String: Any] else {
                print("[CodexLimitMeter] No result in rate limits response")
                return
            }

            if let rateLimits = result["rateLimits"] as? [String: Any] {
                self?.applyRateLimits(rateLimits)
            }
        }
    }

    private func applyRateLimits(_ rateLimits: [String: Any]) {
        let primary = parseWindow(rateLimits["primary"] as? [String: Any])
        let secondary = parseWindow(rateLimits["secondary"] as? [String: Any])
        let planType = rateLimits["planType"] as? String
        let credits = rateLimits["credits"] as? [String: Any]
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
            print("[CodexLimitMeter] Updated: primary=\(primary?.usedPercent ?? -1)%, secondary=\(secondary?.usedPercent ?? -1)%")
        }
    }

    private func parseWindow(_ dict: [String: Any]?) -> RateLimitWindow? {
        guard let dict = dict else { return nil }
        guard let usedPercent = dict["usedPercent"] as? Int else { return nil }
        let durationMins = dict["windowDurationMins"] as? Int ?? 300
        let resetsAt = Int64(dict["resetsAt"] as? Int ?? 0)
        return RateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMins: durationMins,
            resetsAt: resetsAt
        )
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard isInitialized else {
            // Try to initialize again
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.refresh()
            }
            return
        }
        fetchRateLimits()
    }

    func openConfigFolder() {
        let configDir = "\(NSHomeDirectory())/.config/codex-limit-meter"
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: configDir))
    }
}
