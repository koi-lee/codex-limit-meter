import AppKit
import Foundation

// Store builds never locate external programs or share another app's login.
enum StoreLoginState: Equatable {
    case connecting, signedOut, starting, waiting, signedIn, signingOut, failed
}

func approvedLoginURL(_ text: String) -> URL? {
    guard let url = URL(string: text), url.scheme == "https", url.user == nil, url.password == nil,
          url.port == nil || url.port == 443,
          ["auth.openai.com", "chatgpt.com", "auth.chatgpt.com"].contains(url.host?.lowercased() ?? "") else { return nil }
    return url
}

@MainActor
final class StoreAccountController {
    // Keep optional analytics/exporters off in the app-owned helper process.
    // These CLI overrides do not change the user's standalone Codex settings.
    static let helperArguments = [
        "app-server", "-c", "cli_auth_credentials_store=\"file\"",
        "-c", "analytics.enabled=false",
        "-c", "otel.exporter=\"none\"",
        "-c", "otel.trace_exporter=\"none\"",
        "-c", "otel.metrics_exporter=\"none\"",
        "-c", "otel.log_user_prompt=false"
    ]
    enum Failure: Error { case unavailable, timeout, rejected }
    var onState: ((StoreLoginState) -> Void)?
    var onQuota: (([String: Any]) -> Void)?
    var onQuotaFailure: (() -> Void)?
    var onLogoutFailure: (() -> Void)?
    private(set) var state: StoreLoginState = .connecting { didSet { onState?(state) } }
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 0
    private var loginID: String?
    private var earlyLoginResults: [String: Bool] = [:]
    private var loginURL: URL?
    private var generation = 0
    private var deadline: Task<Void, Never>?
    private var polling = false
    private var ready = false
    private let requestOverride: ((String, [String: Any]) async throws -> [String: Any])?
    private let openURL: (URL) -> Void
    private let canAccessAccount: () -> Bool

    init(request: ((String, [String: Any]) async throws -> [String: Any])? = nil,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         canAccessAccount: @escaping () -> Bool = { true }) {
        requestOverride = request; self.openURL = openURL; self.canAccessAccount = canAccessAccount
        if request != nil { ready = true; state = .signedOut }
    }

    func start() async {
        guard canAccessAccount(), process == nil else { return }
        let startupGeneration = generation
        state = .connecting
        var phase = "prepare"
        do {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codex")
            guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw Failure.unavailable }
            let home = FileManager.default.homeDirectoryForCurrentUser
            let data = home.appendingPathComponent("Library/Application Support/CodexMeter/Account", isDirectory: true)
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let task = Process()
            task.executableURL = helper
            task.arguments = Self.helperArguments
            // Do not inherit keys, CODEX_HOME, proxy credentials, or host configuration.
            task.environment = ["HOME": home.path, "CODEX_HOME": data.path, "PATH": "/usr/bin:/bin", "TMPDIR": NSTemporaryDirectory()]
            let stdin = Pipe(), stdout = Pipe()
            task.standardInput = stdin; task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
                Task { @MainActor in self?.receive(chunk) }
            }
            task.terminationHandler = { [weak self] task in
                Task { @MainActor in
                    guard let self, self.process === task else { return }
                    self.process = nil; self.ready = false
                    self.failPending(); self.state = .failed
                }
            }
            phase = "launch"
            try task.run()
            process = task; input = stdin
            phase = "initialize"
            _ = try await rpc("initialize", ["clientInfo": ["name": "codex_limit_meter", "version": "1.2.0"]])
            guard generation == startupGeneration else { return }
            try send(["method": "initialized"])
            ready = true
            phase = "account/read"
            let result = try await rpc("account/read", ["refreshToken": false])
            guard generation == startupGeneration else { return }
            state = (result["account"] as? [String: Any])?["type"] as? String == "chatgpt" ? .signedIn : .signedOut
            if state == .signedIn { await refresh() }
        } catch {
            guard generation == startupGeneration else { return }
            UserDefaults.standard.set("\(phase):\((error as NSError).domain):\((error as NSError).code)", forKey: "store.connectionDiagnostic")
            stop(); state = .failed
        }
    }

    func login() async {
        guard canAccessAccount() else { return }
        if state == .waiting { reopenLogin(); return }
        if process == nil && requestOverride == nil { await start() }
        guard ready, state == .signedOut || state == .failed else { return }
        generation += 1; earlyLoginResults.removeAll()
        let attempt = generation
        state = .starting
        do {
            let result = try await rpc("account/login/start", ["type": "chatgpt"])
            guard let id = result["loginId"] as? String else { throw Failure.rejected }
            guard attempt == generation else {
                _ = try? await rpc("account/login/cancel", ["loginId": id]); return
            }
            guard let text = result["authUrl"] as? String, let url = approvedLoginURL(text) else {
                _ = try? await rpc("account/login/cancel", ["loginId": id]); throw Failure.rejected
            }
            if let success = earlyLoginResults.removeValue(forKey: id) {
                state = success ? .signedIn : .failed
                if success { await refresh() }
                return
            }
            loginID = id; loginURL = url; state = .waiting
            reopenLogin()
            deadline?.cancel()
            deadline = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                guard let self, self.generation == attempt, self.state == .waiting else { return }
                await self.cancelLogin(); self.state = .failed
            }
        } catch { if attempt == generation { state = .failed } }
    }

    func reopenLogin() { guard canAccessAccount() else { return }; if let loginURL { openURL(loginURL) } }

    func cancelLogin() async {
        generation += 1; deadline?.cancel()
        let id = loginID
        loginID = nil; loginURL = nil; state = .signedOut
        if let id { _ = try? await rpc("account/login/cancel", ["loginId": id]) }
    }

    func logout() async {
        guard ready, state == .signedIn else { return }
        generation += 1
        state = .signingOut
        do { _ = try await rpc("account/logout"); state = .signedOut }
        catch { state = .signedIn; onLogoutFailure?() } // Never claim logout succeeded if it did not.
    }

    /// Explicit recovery path for a user-requested reconnect after quota reads fail.
    /// Never discard a working session automatically on a transient RPC error.
    func relogin() async {
        guard canAccessAccount(), ready else { return }
        if state == .signedIn {
            await logout()
            guard state == .signedOut else { return }
        }
        await login()
    }

    func refresh() async {
        guard canAccessAccount(), ready, state == .signedIn, !polling else { return }
        polling = true
        let requestGeneration = generation
        defer { polling = false }
        do {
            let result = try await rpc("account/rateLimits/read")
            guard state == .signedIn, generation == requestGeneration else { return }
            if let limits = Self.codexRateLimits(in: result) {
                onQuota?(limits)
            } else {
                onQuotaFailure?()
            }
        } catch {
            guard state == .signedIn, generation == requestGeneration else { return }
            onQuotaFailure?()
            if let result = try? await rpc("account/read", ["refreshToken": false]), result["account"] is NSNull { state = .signedOut }
        }
    }

    nonisolated static func codexRateLimits(in result: [String: Any]) -> [String: Any]? {
        let byID = result["rateLimitsByLimitId"] as? [String: Any]
        if let codex = byID?["codex"] as? [String: Any], hasUsableWindow(codex["primary"]) || hasUsableWindow(codex["secondary"]) {
            return codex
        }
        guard let legacy = result["rateLimits"] as? [String: Any],
              hasUsableWindow(legacy["primary"]) || hasUsableWindow(legacy["secondary"]) else { return nil }
        return legacy
    }

    nonisolated private static func hasUsableWindow(_ value: Any?) -> Bool {
        guard let window = value as? [String: Any], let used = window["usedPercent"] as? Int else { return false }
        return (0...100).contains(used)
    }

    func stop() {
        generation += 1; ready = false; deadline?.cancel(); loginID = nil; loginURL = nil
        process?.terminationHandler = nil
        process?.terminate(); process = nil; input = nil
        buffer.removeAll(); failPending()
    }

    private func failPending() {
        let callbacks = Array(pending.values); pending.removeAll()
        for continuation in callbacks { continuation.resume(throwing: Failure.unavailable) }
    }

    private func send(_ message: [String: Any]) throws {
        guard let input, process?.isRunning == true else { throw Failure.unavailable }
        var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func rpc(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        if let requestOverride { return try await requestOverride(method, params) }
        nextID += 1; let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.pending.removeValue(forKey: id)?.resume(throwing: Failure.timeout)
            }
        }
    }

    func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 2_000_000 else { stop(); state = .failed; return }
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if let id = json["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                if let result = json["result"] as? [String: Any] { continuation.resume(returning: result) }
                else {
                    let code = (json["error"] as? [String: Any])?["code"] as? Int ?? 0
                    UserDefaults.standard.set("request \(id), code \(code)", forKey: "store.rpcDiagnostic")
                    continuation.resume(throwing: Failure.rejected)
                }
            } else if json["method"] as? String == "account/login/completed", let params = json["params"] as? [String: Any],
                      let id = params["loginId"] as? String {
                if id == loginID {
                    deadline?.cancel(); loginID = nil; loginURL = nil
                    state = params["success"] as? Bool == true ? .signedIn : .failed
                    if state == .signedIn { Task { await refresh() } }
                } else if state == .starting && earlyLoginResults.count < 10 {
                    earlyLoginResults[id] = params["success"] as? Bool == true
                }
            } else if json["method"] as? String == "account/rateLimits/updated", state == .signedIn {
                Task { await refresh() } // Request a complete snapshot, not sparse events.
            }
        }
    }
}
