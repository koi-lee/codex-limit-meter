import Cocoa
import Combine
import UserNotifications

struct AnnouncementText: Codable {
    let zh: String
    let en: String
    func value(_ chinese: Bool) -> String { chinese ? zh : en }
    var valid: Bool { !zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct Announcement: Codable {
    let id: String
    let revision: Int
    let title: AnnouncementText
    let summary: AnnouncementText
    let audience: AnnouncementText
    let sourceURL: String
    let publishedAt: Date
    let expiresAt: Date
    let resetAt: Date?
    let status: String

    static func source(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    func active(at now: Date) -> Bool {
        status == "active" && publishedAt <= now && now < expiresAt
    }

    func shouldNotify(at now: Date, sent: [String: Int]) -> Bool {
        guard publishedAt <= now, (now < expiresAt), revision > (sent[id] ?? 0) else { return false }
        return status == "active" || (status == "withdrawn" && sent[id] != nil)
    }

    func notificationTitle(chinese: Bool, previouslySent: Bool) -> String {
        let prefix = status == "withdrawn" ? (chinese ? "公告撤回：" : "Withdrawn: ")
            : previouslySent ? (chinese ? "公告更新：" : "Updated: ") : ""
        return prefix + title.value(chinese)
    }
}

// Presentation only: publication order is not proof that two posts describe one reset.
struct ResetAnnouncementOverview {
    let upcoming: [Announcement]
    let latestCompleted: Announcement?
    let history: [Announcement]

    init(entries: [Announcement], now: Date) {
        let visible = entries.filter { $0.publishedAt <= now }.sorted { $0.publishedAt > $1.publishedAt }
        latestCompleted = visible.first { $0.status == "active" && $0.isResetCompleted }
        let completion = latestCompleted
        upcoming = visible.filter { entry in
            guard entry.active(at: now), entry.isResetPreview else { return false }
            if let target = entry.resetAt { return target > now }
            // Older undated previews cannot establish a new future opportunity.
            return completion.map { entry.publishedAt > $0.publishedAt } ?? true
        }
        let upcomingIDs = Set(upcoming.map(\.id))
        history = visible.filter { !upcomingIDs.contains($0.id) && $0.id != completion?.id }
    }
}

extension Announcement {
    var isPageObservation: Bool { id.hasPrefix("local-") && !id.hasPrefix("local-tibo-") }
    var isResetCompleted: Bool { title.zh.contains("重置完成") }
    var isResetPreview: Bool { title.zh.contains("重置预告") || (!isResetCompleted && resetAt != nil) }

    func menuDate(_ date: Date, chinese: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: chinese ? "zh_CN" : "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = chinese ? "M月d日 HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }

    func resetMenuTitle(chinese: Bool, upcoming: Bool = false) -> String {
        let published = menuDate(publishedAt, chinese: chinese)
        if upcoming {
            if let resetAt {
                return chinese ? "预计 \(menuDate(resetAt, chinese: true)) 重置" : "Expected reset: \(menuDate(resetAt, chinese: false))"
            }
            return chinese ? "已预告，具体时间待核对（\(published) 发布）" : "Reset announced; check timing (posted \(published))"
        }
        if status == "withdrawn" { return chinese ? "\(published)｜公告已撤回" : "\(published) | Withdrawn" }
        if isResetCompleted { return chinese ? "\(published)｜已宣布重置完成" : "\(published) | Reset completion announced" }
        if isResetPreview {
            return chinese ? "\(published)｜较早预告，查看原文核对结果" : "\(published) | Earlier preview; verify outcome"
        }
        return "\(published)｜\(title.value(chinese))"
    }
}

struct AnnouncementFeed: Codable {
    let version: Int
    let announcements: [Announcement]

    static func parse(_ data: Data) throws -> AnnouncementFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: text)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: text)
            }
            guard let date else { throw CocoaError(.coderReadCorrupt) }
            return date
        }
        let feed = try decoder.decode(Self.self, from: data)
        guard feed.version == 1, Set(feed.announcements.map(\.id)).count == feed.announcements.count,
              feed.announcements.allSatisfy({
                  !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.revision > 0 &&
                  $0.title.valid && $0.summary.valid && $0.audience.valid &&
                  Announcement.source($0.sourceURL) != nil && $0.expiresAt > $0.publishedAt &&
                  ["active", "withdrawn"].contains($0.status)
              }) else { throw CocoaError(.coderReadCorrupt) }
        return feed
    }
}

enum AnnouncementFetchError: Error {
    case notPublished
}

@MainActor
final class AnnouncementService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let feedURL = URL(string: "https://raw.githubusercontent.com/koi-lee/codex-limit-meter/main/announcements.json")!
    private let defaults: UserDefaults
    private let localFeedURL: URL?
    private let fetch: () async throws -> Data
    private let permission: () async -> UNAuthorizationStatus
    private let requestPermission: () async throws -> Bool
    private let diagnostics: () async -> String
    private let deliver: (UNNotificationRequest) async throws -> Void
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var sent: [String: Int]
    @Published private(set) var entries: [Announcement] = []
    @Published private(set) var checking = false
    @Published private(set) var failed = false
    @Published private(set) var partialSources = false
    @Published private(set) var primarySourceHealthy: Bool?
    private(set) var notPublished = false
    private(set) var notificationFailed = false
    @Published private(set) var lastSuccess: Date?
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    var onChange: (() -> Void)?
    var onOpenAnnouncement: ((String) -> Void)?
    var chinese: () -> Bool = { true }
    var enabled: Bool { defaults.bool(forKey: "announcements.enabled") }

    init(defaults: UserDefaults = .standard,
         localFeedURL: URL? = PublicAnnouncementFeed.configuredURL == nil ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexMeter/official-monitor/announcements.json") : nil,
         fetch: @escaping () async throws -> Data = {
             if let url = PublicAnnouncementFeed.configuredURL { return try await PublicAnnouncementFeed.fetch(url) }
             return try await TiboAnnouncementFeed.fetch()
         },
         permission: @escaping () async -> UNAuthorizationStatus = { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
         requestPermission: @escaping () async throws -> Bool = { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) },
         diagnostics: @escaping () async -> String = {
             let settings = await UNUserNotificationCenter.current().notificationSettings()
             if settings.alertSetting != .enabled || settings.alertStyle == .none {
                 return "桌面横幅未开启，请到系统设置 → 通知 → Codex Meter 开启。"
             }
             return "横幅设置已开启；若未看到，请检查专注模式及录屏/共享屏幕时的通知限制。"
         },
         deliver: @escaping (UNNotificationRequest) async throws -> Void = { try await UNUserNotificationCenter.current().add($0) }) {
        self.defaults = defaults
        self.localFeedURL = localFeedURL
        self.fetch = fetch
        self.permission = permission
        self.requestPermission = requestPermission
        self.deliver = deliver
        self.diagnostics = diagnostics
        self.sent = defaults.dictionary(forKey: "announcements.sent") as? [String: Int] ?? [:]
        super.init()
        if let data = defaults.data(forKey: "announcements.cache"), let feed = try? AnnouncementFeed.parse(data) {
            entries = feed.announcements
            lastSuccess = defaults.object(forKey: "announcements.lastSuccess") as? Date
        }
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self { await self.check() } }
        }
        schedule()
        Task { await check() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        // Public news powers in-app bubbles even when system alerts are disabled.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func setEnabled(_ value: Bool) async {
        guard !demoSuspended else { return }
        let generation = demoGeneration
        defaults.set(value, forKey: "announcements.enabled")
        schedule()
        onChange?()
        guard value else { return }
        authorization = await permission()
        guard !demoSuspended, generation == demoGeneration else { return }
        if authorization == .notDetermined {
            do { _ = try await requestPermission() } catch { notificationFailed = true }
            guard !demoSuspended, generation == demoGeneration else { return }
            authorization = await permission()
        }
        guard !demoSuspended, generation == demoGeneration else { return }
        await check()
    }

    @Published private(set) var testReminderStatus = ""
    @Published private(set) var testingReminder = false
    var remindersReady: Bool { enabled && (authorization == .authorized || authorization == .provisional) }
    var reminderStatusText: String {
        if !enabled { return "消息提醒未开启" }
        switch authorization {
        case .authorized: return "提醒权限已允许"
        case .provisional: return "已允许静默通知"
        case .denied: return "系统通知未允许"
        default: return "还需要允许系统通知"
        }
    }
    func sendTestReminder() async {
        guard !demoSuspended else { return }
        guard !testingReminder else { return }
        let generation = demoGeneration
        testingReminder = true
        testReminderStatus = "正在检查通知设置并发送…"
        onChange?()
        defer { testingReminder = false; onChange?() }
        authorization = await permission()
        guard !demoSuspended, generation == demoGeneration else { return }
        guard remindersReady else {
            testReminderStatus = "请先开启提醒并允许系统通知。"; return
        }
        let diagnostic = await diagnostics()
        guard !demoSuspended, generation == demoGeneration else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())
        let content = UNMutableNotificationContent()
        content.title = "Codex Meter · 测试提醒 " + time
        content.body = "这是一条通知测试，不是额度重置预告。点击返回消息星盘。"
        content.userInfo = ["codexMeterTest": true]
        do {
            try await deliver(UNNotificationRequest(identifier: "codex-meter.test." + UUID().uuidString, content: content, trigger: nil))
            guard !demoSuspended, generation == demoGeneration else { return }
            testReminderStatus = "\(time) 已提交系统，尚未确认横幅显示。\n\(diagnostic)"
        } catch {
            guard !demoSuspended, generation == demoGeneration else { return }
            testReminderStatus = "测试提醒发送失败，请检查系统通知设置。"
        }
    }

    /// Consume once per local user profile; deferring must not become a launch nag.
    func consumeReminderIntroduction() -> Bool {
        let key = "announcements.introduction.v1.seen"
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        return !remindersReady
    }

    func refreshAuthorization() async {
        authorization = await permission()
        onChange?()
    }

    private(set) var demoSuspended = false
    private var demoGeneration = 0
    func setDemoSuspended(_ value: Bool) {
        demoSuspended = value
        demoGeneration += 1
        if value { testReminderStatus = "" }
    }
    func check() async {
        guard !demoSuspended, !checking else { return }
        let generation = demoGeneration
        checking = true
        onChange?()
        defer { checking = false; onChange?() }
        authorization = await permission()
        guard !demoSuspended, generation == demoGeneration else { return }
        var candidates: [Announcement] = []
        do {
            let data = try await fetch()
            guard !demoSuspended, generation == demoGeneration else { return }
            let feed = try AnnouncementFeed.parse(data)
            let metadata = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            partialSources = metadata?["partial"] as? Bool ?? false
            primarySourceHealthy = metadata?["healthy"] as? Bool
            entries = feed.announcements
            candidates = entries
            lastSuccess = Date()
            defaults.set(data, forKey: "announcements.cache")
            defaults.set(lastSuccess, forKey: "announcements.lastSuccess")
            failed = false
            notPublished = false
        } catch {
            guard !demoSuspended, generation == demoGeneration else { return }
            notPublished = (error as? AnnouncementFetchError) == .notPublished
            failed = true
        }
        if let localFeedURL, let data = try? Data(contentsOf: localFeedURL), let local = try? AnnouncementFeed.parse(data) {
            let ids = Set(local.announcements.map(\.id))
            entries.removeAll { ids.contains($0.id) || ($0.id.hasPrefix("local-") && !$0.id.hasPrefix("local-tibo-")) }
            entries += local.announcements
            candidates += local.announcements
        }
        notificationFailed = false
        guard enabled, authorization == .authorized || authorization == .provisional else { return }
        for entry in candidates where entry.shouldNotify(at: Date(), sent: sent) {
            guard enabled, !demoSuspended, generation == demoGeneration else { break }
            let content = UNMutableNotificationContent()
            content.title = entry.notificationTitle(chinese: chinese(), previouslySent: sent[entry.id] != nil)
            content.body = entry.summary.value(chinese()) + "\n" + (chinese() ? "适用范围：" : "Applies to: ") + entry.audience.value(chinese()) + "\n" + (chinese() ? "原文：" : "Source: ") + entry.sourceURL
            if chinese() {
                let copy = PetAnnouncementCopy(entry, historical: false)
                content.body = copy.brief + "\n" + copy.timing + "\n适用范围：" + entry.audience.zh
            }
            content.userInfo = ["sourceURL": entry.sourceURL, "announcementID": entry.id]
            let request = UNNotificationRequest(identifier: "announcement.\(entry.id).revision.\(entry.revision)", content: content, trigger: nil)
            do {
                try await deliver(request)
                sent[entry.id] = entry.revision
                defaults.set(sent, forKey: "announcements.sent")
            } catch { notificationFailed = true }
        }
    }

    func openNotification(id: String?, source: String?) {
        if let id, entries.contains(where: { $0.id == id }), let onOpenAnnouncement {
            onOpenAnnouncement(id)
        } else if let source, let url = Announcement.source(source) {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let info = response.notification.request.content.userInfo
            let isTest = info["codexMeterTest"] as? Bool == true
            let id = info["announcementID"] as? String
            let source = info["sourceURL"] as? String
            Task { @MainActor in
                if isTest { self.onOpenAnnouncement?("") }
                else { self.openNotification(id: id, source: source) }
            }
        }
        completionHandler()
    }
}

/// Anonymous, third-party copies of Tibo posts; never reads account credentials.
enum TiboAnnouncementFeed {
    static let signals = URL(string: "https://codex-reset.com/api/tibo/signals")!
    static let fallback = URL(string: "https://codex-reset.com/api/feed")!
    static let attributionURL = URL(string: "https://codex-reset.com/")!
    static let userAgent = "CodexMeter/1.0 (+https://starshoreai.com/codex-meter)"

    static func request(_ url: URL, timeout: TimeInterval = 20) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func matches(_ pattern: String, _ value: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func date(_ value: Any?) throws -> Date {
        guard let text = value as? String else { throw URLError(.cannotParseResponse) }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = parser.date(from: text) { return value }
        parser.formatOptions = [.withInternetDateTime]
        guard let value = parser.date(from: text) else { throw URLError(.cannotParseResponse) }
        return value
    }

    static func parse(_ data: Data, now: Date = Date(), signals: Bool) throws -> Data {
        guard data.count <= 2_000_000,
              let feed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (feed["stale"] as? Bool ?? (signals ? false : true)) == false else { throw URLError(.cannotParseResponse) }
        let fetched = try date(feed["fetched_at"])
        guard (-300...1800).contains(now.timeIntervalSince(fetched)) else { throw URLError(.resourceUnavailable) }
        if signals {
            guard feed["source"] as? String == "x-api" else { throw URLError(.cannotParseResponse) }
        } else {
            guard let profile = feed["profile"] as? [String: Any],
                  (profile["handle"] as? String)?.lowercased() == "thsottiaux" else { throw URLError(.cannotParseResponse) }
        }
        guard let posts = feed[signals ? "items" : "tweets"] as? [[String: Any]], !posts.isEmpty else { throw URLError(.cannotParseResponse) }
        var entries: [Announcement] = []
        for post in posts {
            guard let id = post["id"] as? String, matches(#"^\d+$"#, id),
                  let url = post["url"] as? String, url == "https://x.com/thsottiaux/status/" + id,
                  let raw = post["text"] as? String else { throw URLError(.cannotParseResponse) }
            let published = try date(post["at"])
            guard published.timeIntervalSince(now) <= 300 else { throw URLError(.cannotParseResponse) }
            let text = raw.replacingOccurrences(of: #"\n"#, with: "\n")
            guard matches(#"\breset\w*\b"#, text) else { continue }
            let clauses = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).filter { matches(#"\breset\w*\b"#, $0) }
            let negative = #"\b(not|never|won't|no reset)\b"#
            let planned = clauses.contains { matches(#"\b(?:we will (?:do (?:a |the )?(?:global |full )?reset|reset)|we are going to reset|i promised (?:a |the )?reset|(?:more )?resets? (?:are )?coming)\b"#, $0) && !matches(negative, $0) }
            let kind: String
            if planned && !matches(#"\bbanked\b"#, text) { kind = "重置预告" }
            else if text.contains("?") || matches(negative, clauses.joined(separator: " ")) { continue }
            else if matches(#"\bbanked\b"#, text) { kind = "备用重置相关动态" }
            else if clauses.contains(where: { matches(#"\b(all reset|have reset|has reset|just reset|reset (?:all )?propagated|resets? all propagated)\b"#, $0) && !matches(negative, $0) }) { kind = "重置完成消息" }
            else if matches(#"\b(will (?:do|reset|land)|going to reset|promised (?:a |the )?reset|(?:more )?resets? (?:are )?coming|(?:is (?:also )?)?landing|lands|give us \d+ hours?)\b"#, text) { kind = "重置预告" }
            else { continue }
            var target: Date?
            if kind == "重置预告" {
                let regex = try NSRegularExpression(pattern: #"\b(?:in)\s+(?:~\s*)?(\d{1,3})\s*(hours?|hrs?|minutes?|mins?)\b"#, options: .caseInsensitive)
                if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let amountRange = Range(match.range(at: 1), in: text), let amount = Double(text[amountRange]),
                   let unitRange = Range(match.range(at: 2), in: text), amount > 0, amount <= 168 {
                    target = published.addingTimeInterval(amount * (text[unitRange].lowercased().hasPrefix("h") ? 3600 : 60))
                }
            }
            let age = now.timeIntervalSince(published)
            guard age <= 86400 || (target.map { $0 > now } == true && age < 604800) else { continue }
            let title = "Codex：" + kind + "（转录）"
            entries.append(Announcement(id: "local-tibo-" + id, revision: 1,
                title: .init(zh: title, en: kind == "重置预告" ? "Reset announced (third-party copy)" : kind == "重置完成消息" ? "Reset completion announced (third-party copy)" : "Banked reset update (third-party copy)"),
                summary: .init(zh: "第三方转录，请核对原帖时间及适用范围。\n" + String(text.prefix(1500)), en: "Third-party copy; check the original timing and eligibility.\n" + String(text.prefix(1500))),
                audience: .init(zh: "以 Tibo 原帖为准，不保证你的账号适用", en: "Check Tibo's original post for eligibility"),
                sourceURL: url, publishedAt: published,
                expiresAt: max(published.addingTimeInterval(86400), (target ?? published).addingTimeInterval(3600)),
                resetAt: target, status: "active"))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(AnnouncementFeed(version: 1, announcements: entries))
    }

    static func fetch() async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        var lastError: Error = URLError(.resourceUnavailable)
        for (url, isSignals) in [(signals, true), (fallback, false)] {
            do {
                let request = request(url)
                let (bytes, response) = try await session.bytes(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
                    data.append(byte)
                }
                return try parse(data, signals: isSignals)
            } catch { lastError = error }
        }
        throw lastError
    }
}

/// Set only after the public HTTPS endpoint has passed deployment verification.
enum PublicAnnouncementFeed {
    static var configuredURL: URL? {
        let text = Bundle.main.object(forInfoDictionaryKey: "PublicAnnouncementFeedURL") as? String
            ?? "https://starshoreai.com/codex-meter/announcements.json"
        return Announcement.source(text)
    }
    static func validate(_ data: Data, now: Date = Date()) throws -> Data {
        guard data.count <= 2_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["healthy"] as? Bool == true else { throw URLError(.resourceUnavailable) }
        let generated = try TiboAnnouncementFeed.date(root["generatedAt"])
        guard (-300...1800).contains(now.timeIntervalSince(generated)) else { throw URLError(.resourceUnavailable) }
        _ = try AnnouncementFeed.parse(data)
        return data
    }
    static func fetch(_ url: URL) async throws -> Data {
        let request = TiboAnnouncementFeed.request(url, timeout: 30)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https" else { throw URLError(.badServerResponse) }
        return try validate(data)
    }
}
