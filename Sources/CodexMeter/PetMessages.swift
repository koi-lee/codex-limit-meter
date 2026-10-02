import SwiftUI

func shouldOfferQuotaRelogin(isDemo: Bool, usesStoreAuthentication: Bool,
                             regionRestricted: Bool, isSignedIn: Bool,
                             hasReadError: Bool) -> Bool {
    !isDemo && usesStoreAuthentication && !regionRestricted && isSignedIn && hasReadError
}

struct PetQuotaObservation: Identifiable {
    let id = UUID()
    let from: Int
    let to: Int
    let at: Date
}

/// Session observations only. An increase is not evidence of an extraordinary reset.
struct PetQuotaJournal {
    private(set) var previous: PetState?
    private(set) var changes: [PetQuotaObservation] = []
    mutating func breakContinuity() { previous = nil }
    mutating func observe(_ state: PetState, at: Date = Date()) {
        defer { previous = state }
        if state.remaining == nil { changes = []; return }
        guard let old = previous, let from = old.remaining, let to = state.remaining else { return }
        guard old.resetsAt == state.resetsAt else { changes = []; return }
        if from != to {
            changes.insert(.init(from: from, to: to, at: at), at: 0)
            changes = Array(changes.prefix(12))
        }
    }
}

@MainActor final class PetMessageModel: ObservableObject {
    @Published var isDemo = false
    @Published var entries: [Announcement] = []
    @Published var checking = false
    @Published var unread = false
    @Published var failed = false
    @Published var partialSources = false
    @Published var primarySourceHealthy: Bool?
    @Published var checkedAt: Date?
    @Published var quotaUpdatedAt: Date?
    @Published var quotaReadStatus = "等待读取额度"
    @Published var quotaNeedsLogin = false
    @Published var quotaCanRelogin = false
    var refreshQuota: (() -> Void)?
    var connectQuotaAccount: (() -> Void)?
    var reloginQuotaAccount: (() -> Void)?
    @Published var changes: [PetQuotaObservation] = []
    @Published var page = "quota"
    @Published var selectedAnnouncementID: String?
    @Published var remindersEnabled = false
    @Published var remindersReady = false
    @Published var reminderStatus = "消息提醒未开启"
    @Published var testReminderStatus = ""
    @Published var testingReminder = false
    var testReminder: (() -> Void)?
    var checkPermission: (() -> Void)?
    @Published var notificationDenied = false
    var enableReminders: (() -> Void)?
    var refresh: (() -> Void)?
    var close: (() -> Void)?
    var exitDemo: (() -> Void)?
    var overview: ResetAnnouncementOverview { .init(entries: entries, now: Date()) }
    var partialSourcesMessage: String? {
        guard partialSources, !failed else { return nil }
        let prefix = primarySourceHealthy == true ? "Tibo 主动态源正常；" : ""
        let detail = entries.isEmpty
            ? "辅助网页来源暂不可用，目前没有可展示的有效消息。"
            : "部分辅助网页来源暂不可用；以下为已获取的消息。"
        return prefix + detail
    }
    var headline: String {
        if checking { return "核对中" }
        if failed { return "待核对" }
        if checkedAt == nil { return "待读取" }
        if !overview.upcoming.isEmpty { return "重置预告" }
        if overview.latestCompleted != nil { return "完成公告" }
        return "暂无预告"
    }
    var emptyMessage: String {
        if checking { return "正在获取最新消息…" }
        if failed { return "暂不能确认是否有新预告，请稍后刷新" }
        if checkedAt == nil { return "尚未获取消息，请点击刷新" }
        return "下一次重置：暂无新预告"
    }
    static func time(_ date: Date?) -> String {
        guard let date else { return "尚未成功读取" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

struct PetMessageView: View {
    @ObservedObject var model: PetMessageModel
    private let gold = Color(red: 0.95, green: 0.84, blue: 0.63)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isDemo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("演示模式 · 示例数据 / Demo · Sample data")
                    Button("退出演示 / Exit Demo") { model.exitDemo?() }.underline()
                }.font(.caption).foregroundColor(gold)
            }
            HStack {
                Text(model.page == "changes" ? "额度足迹" : "星讯 · 额度重置").font(.system(size: 15, weight: .semibold)).foregroundColor(gold)
                Spacer()
                Button(action: { model.close?() }) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.07)))
                        .contentShape(Circle())
                }.help("收起详情").accessibilityLabel("收起详情")
            }
            if model.page == "changes" {
                HStack(spacing: 6) {
                    Text("额度读取：\(PetMessageModel.time(model.quotaUpdatedAt))")
                        .font(.caption)
                    Spacer(minLength: 0)
                    if model.quotaNeedsLogin {
                        Button("连接账号") { model.connectQuotaAccount?() }
                            .font(.caption)
                    }
                    if model.quotaCanRelogin {
                        Button("重新登录") { model.reloginQuotaAccount?() }
                            .font(.caption)
                    }
                    Button("刷新") { model.refreshQuota?() }
                        .font(.caption)
                        .disabled(model.isDemo)
                }
                Text(model.quotaReadStatus).font(.caption).foregroundColor(gold)
                Text(model.isDemo ? "虚构变化，仅演示界面 / Sample changes only" : "本次运行中观察到的变化；不据此判定额外重置或适用账号。").font(.caption).foregroundColor(.white.opacity(0.7))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.changes.isEmpty { Text("还没有连续观察到额度变化。保持桌宠运行即可记录。").font(.system(size: 12)) }
                        ForEach(model.changes) { change in
                            HStack { Text("\(change.from)% → \(change.to)%").foregroundColor(gold); Spacer(); Text(PetMessageModel.time(change.at)).font(.caption) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("仅本次会话 · 恢复周期变化后重新记录").font(.caption2).foregroundColor(.white.opacity(0.6))
            } else {
                HStack(spacing: 5) {
                    Text(model.checking ? "正在核对消息…" : "最近核对：\(PetMessageModel.time(model.checkedAt))")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.82))
                    Button(action: { model.refresh?() }) {
                        Group {
                            if model.checking {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                            }
                        }.frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .foregroundColor(gold.opacity(0.85))
                    .disabled(model.checking)
                    .help(model.checking ? "正在核对消息" : "重新核对消息")
                    .accessibilityLabel("刷新消息")
                    Spacer(minLength: 0)
                }
                if let status = model.partialSourcesMessage { Text(status).font(.system(size: 12, weight: .medium)).foregroundColor(gold) }
                if model.failed { Text("来源暂不可用；以下保留上次记录，不能确认最新状态。").font(.system(size: 12, weight: .medium)).foregroundColor(gold) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let id = model.selectedAnnouncementID, let selected = model.entries.first(where: { $0.id == id }) {
                            Text("通知对应消息").font(.caption).foregroundColor(gold)
                            item(selected, historical: !selected.active(at: Date()))
                        }
                        if model.overview.upcoming.isEmpty {
                            Text(model.emptyMessage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(gold)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(model.overview.upcoming.filter { $0.id != model.selectedAnnouncementID }, id: \.id) { entry in item(entry, historical: false) }
                        if let entry = model.overview.latestCompleted, entry.id != model.selectedAnnouncementID { item(entry, historical: false) }
                        ForEach(model.overview.history.filter { $0.id != model.selectedAnnouncementID }.prefix(5), id: \.id) { entry in item(entry, historical: true) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(model.reminderStatus, systemImage: model.remindersReady ? "bell.badge" : "bell.slash")
                            .font(.caption).foregroundColor(gold)
                        Spacer()
                        if model.notificationDenied {
                            Button("重新检查") { model.checkPermission?() }
                        } else if !model.remindersReady {
                            Button("开启提醒") { model.enableReminders?() }
                        }
                    }.font(.caption)
                        .buttonStyle(ReminderActionStyle())
                    Button(model.isDemo ? "演示提醒 / Preview reminder" : model.testingReminder ? "发送中…" : "发送测试提醒") { model.testReminder?() }
                        .buttonStyle(ReminderActionStyle())
                        .disabled(model.testingReminder)
                    Text(model.isDemo ? "仅显示示例反馈，不发送通知 / No notification sent" : "测试桌宠气泡和系统通知，不代表重置预告。")
                        .font(.caption2).foregroundColor(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.isDemo ? "退出演示后可查看真实消息 / Exit demo for live messages" : model.notificationDenied
                         ? "系统设置 → 通知 → Codex Meter，打开允许通知与横幅。"
                         : "有重置消息时主动提醒，无需点击桌宠。App 需保持运行。")
                        .font(.caption2).foregroundColor(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.testReminderStatus.isEmpty {
                        Text(model.testReminderStatus).font(.caption2).foregroundColor(gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.05)))
                Text("北京时间 · 公告进展不等于本账号已到账")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(Color(red: 0.9, green: 0.86, blue: 0.95))
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.16, green: 0.11, blue: 0.22).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(gold.opacity(0.4), lineWidth: 0.7))
        .padding(3)
    }
    private func item(_ entry: Announcement, historical: Bool) -> some View {
        let copy = PetAnnouncementCopy(entry, historical: historical)
        return VStack(alignment: .leading, spacing: 7) {
            Text(copy.title).font(.system(size: 14, weight: .semibold)).foregroundColor(gold)
            Text(copy.brief).font(.system(size: 13, weight: .semibold)).foregroundColor(gold).fixedSize(horizontal: false, vertical: true)
            Text(copy.timing).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text(copy.explanation).font(.system(size: 13)).foregroundColor(.white.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
            Text(model.isDemo ? "虚构示例，无真实来源 / Fictional sample" : entry.sourceURL.hasPrefix("https://x.com/thsottiaux/status/") ? "Tibo · 第三方转录" : "网页监测 · 查看来源").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if !model.isDemo, let sourceURL = copy.dataSourceURL {
                Link("数据来源 / Data: codex-reset.com ↗", destination: sourceURL)
                    .foregroundColor(gold).font(.caption2)
            }
            if let url = Announcement.source(entry.sourceURL) { Link("查看原文 ↗", destination: url).foregroundColor(gold).font(.caption) }
            DisclosureGroup("原文摘要与适用范围") {
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(entry.isPageObservation ? "发现变化" : "发帖时间")：\(PetMessageModel.time(entry.publishedAt))（北京时间）").font(.caption)
                    Text(entry.summary.zh).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text("适用：\(entry.audience.zh)").font(.caption)
                    if let url = Announcement.source(entry.sourceURL) { Link("查看原帖 ↗", destination: url).foregroundColor(gold) }
                }.padding(.top, 6)
            }.font(.caption).tint(gold)
            Divider().overlay(gold.opacity(0.25))
        }
    }
}

/// Human-readable status without inventing the completion instant or an author's timezone.
struct PetAnnouncementCopy {
    let title: String
    let timing: String
    let explanation: String
    let brief: String
    let dataSourceURL: URL?
    init(_ entry: Announcement, historical: Bool, now: Date = Date()) {
        dataSourceURL = entry.sourceURL.hasPrefix("https://x.com/thsottiaux/status/")
            ? TiboAnnouncementFeed.attributionURL : nil
        if entry.status == "withdrawn" { brief = "预告已撤回，请勿再按原时间安排" }
        else if entry.isResetCompleted { brief = "本次已宣布完成；下次重置时间未公布" }
        else if historical { brief = "历史消息，不是新一轮重置预告" }
        else if let target = entry.resetAt {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day
            if target <= now { brief = "预计时间已过，是否完成待核实" }
            else if days == 0 { brief = "预计今天重置，具体到账以账号为准" }
            else if days == 1 { brief = "预计明天重置，具体到账以账号为准" }
            else { brief = "预计 \(entry.menuDate(target, chinese: true)) 重置" }
        } else { brief = entry.isResetPreview ? "负责人已表示会重置；具体时刻未公布" : "发现相关网页更新；重置时间未公布" }
        let published = entry.menuDate(entry.publishedAt, chinese: true)
        if entry.status == "withdrawn" {
            title = "这条重置消息已撤回"
            timing = "原消息发布于 \(published)"
            explanation = "请勿再按这条消息安排使用，查看原文核对撤回说明。"
        } else if entry.isResetCompleted {
            title = historical ? "较早的重置完成公告" : "已宣布额度重置完成"
            timing = "\(published) 发布完成消息"
            explanation = "消息称本次重置已完成，未给出精确完成时刻。你的账号是否到账，以实际额度为准。"
        } else if entry.isResetPreview {
            title = historical ? "此前预告：额度将重置" : "即将重置 · 尚未确认完成"
            if let target = entry.resetAt {
                timing = "预计 \(entry.menuDate(target, chinese: true)) 重置"
            } else if entry.summary.en.lowercased().contains("by midnight today") || entry.summary.zh.lowercased().contains("by midnight today") {
                timing = "原帖预计：发帖当日午夜前"
            } else {
                timing = entry.summary.en.localizedCaseInsensitiveContains("Tuesday") ? "原帖承诺：周二重置，具体时刻未公布" : "已确认会重置，具体时刻未公布"
            }
            let ambiguous = entry.resetAt == nil && timing.contains("午夜")
            explanation = "\(published) 发布预告。" + (ambiguous ? "原帖未注明时区，不能确定北京时间。" : "") + (historical ? "这是较早预告，不代表将再重置一次。" : "这是预告，实际生效仍待后续消息。")
        } else {
            title = entry.isPageObservation ? "额度相关网页有更新" : entry.title.zh
            timing = entry.isPageObservation ? "发现变化：\(published)（非原文发布时间）" : "\(published) 发布"
            explanation = "尚未确认这条更新包含重置安排，具体内容请查看原文。"
        }
    }
}

/// A visible action surface inside the reminder status card.
private struct ReminderActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(red: 0.17, green: 0.11, blue: 0.23))
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.94, green: 0.81, blue: 0.53)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .brightness(configuration.isPressed ? -0.12 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}


/// Bubble delivery is independent of system notification authorization.
struct PetBubblePolicy {
    static func candidate(_ entries: [Announcement], delivered: [String: Int], now: Date) -> Announcement? {
        let overview = ResetAnnouncementOverview(entries: entries, now: now)
        let eligible = overview.upcoming + [overview.latestCompleted].compactMap { $0 }
        return eligible.filter { $0.active(at: now) && $0.revision > (delivered[$0.id] ?? 0) }
            .sorted { $0.publishedAt > $1.publishedAt }.first
    }
    static func text(_ entry: Announcement) -> String {
        if entry.isResetCompleted { return "本轮重置已宣布完成，账号是否到账请查看实际额度。" }
        if let date = entry.resetAt { return "预计北京时间\(entry.menuDate(date, chinese: true))重置，以来源公告及适用范围为准。" }
        return "有新的额度重置预告，具体时间尚未公布。"
    }
}

struct PetNewsBubble: View {
    let text: String
    var tipX: CGFloat = 100
    var showsBeads = true
    let open: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("✦ 星夜来信").font(.system(size: 10, weight: .medium)).opacity(0.7)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).accessibilityLabel("关闭消息气泡")
            }
            Button(action: open) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Text("查看消息 →").font(.system(size: 11, weight: .semibold))
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("查看气泡消息详情")
        }
        .padding(.horizontal, 20)
        .foregroundColor(Color(red: 0.96, green: 0.85, blue: 0.65))
        .frame(width: 264, height: 118)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.16, blue: 0.29), Color(red: 0.15, green: 0.11, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
            .stroke(Color(red: 0.94, green: 0.81, blue: 0.53).opacity(0.3), lineWidth: 0.7))
        .overlay(alignment: .bottomLeading) {
            // The descending beads point back toward the reader's head.
            ZStack(alignment: .topLeading) {
                thoughtOval(width: 13, height: 8).offset(x: tipX - 18, y: 2)
                thoughtOval(width: 8, height: 6).offset(x: tipX - 8, y: 12)
                thoughtOval(width: 4, height: 4).offset(x: tipX - 2, y: 20)
            }.frame(width: 264, height: 24, alignment: .topLeading).offset(y: 24).opacity(showsBeads ? 1 : 0)
        }
        .padding(.bottom, 24)
    }

    private func thoughtOval(width: CGFloat, height: CGFloat) -> some View {
        Ellipse()
            .fill(Color(red: 0.17, green: 0.12, blue: 0.23))
            .overlay(Ellipse().stroke(Color(red: 0.94, green: 0.81, blue: 0.53).opacity(0.6), lineWidth: 0.8))
            .frame(width: width, height: height)
    }
}


struct PetBubblePlacement {
    let frame: CGRect
    let tipX: CGFloat
    let showsBeads: Bool

    static func resolve(head: CGPoint, screen: CGRect, expanded: Bool, scale: CGFloat, detailCard: CGRect? = nil) -> Self {
        let safe = screen.insetBy(dx: 8, dy: 8)
        let width: CGFloat = 264, height: CGFloat = 142
        let character = CGRect(x: head.x - 128 * scale, y: head.y - 256 * scale, width: 256 * scale, height: 256 * scale)
        let stars = CGRect(x: head.x + 80 * scale, y: head.y - 76 * scale, width: 220 * scale, height: 200 * scale)
        var positions = [
            CGPoint(x: head.x - (expanded ? 244 : 100), y: head.y + 2),
            CGPoint(x: character.minX - width - 8, y: head.y - 118),
            CGPoint(x: head.x - 100, y: stars.maxY + 8),
            CGPoint(x: character.maxX + 8, y: character.minY),
            CGPoint(x: head.x - 100, y: character.minY - height - 8)
        ]
        if let card = detailCard {
            positions.insert(CGPoint(x: head.x - 244, y: max(head.y + 2, card.maxY + 8)), at: 1)
        }
        let obstacles = [character] + (expanded ? [stars] : []) + (detailCard.map { [$0.insetBy(dx: -8, dy: -8)] } ?? [])
        // Search obstacle edges when the preferred head-adjacent slots are blocked.
        // Clamping a preferred slot to the screen can otherwise put it back on a card.
        if detailCard != nil {
            let xs = [safe.minX, safe.maxX - width, head.x - width / 2]
                + obstacles.flatMap { [$0.minX - width - 8, $0.maxX + 8] }
            let ys = [safe.minY, safe.maxY - height, head.y + 2]
                + obstacles.flatMap { [$0.minY - height - 8, $0.maxY + 8] }
            var alternatives: [CGPoint] = []
            for x in xs { for y in ys { alternatives.append(CGPoint(x: x, y: y)) } }
            func distance(_ point: CGPoint) -> CGFloat {
                let dx = point.x + width / 2 - head.x
                let dy = point.y - head.y
                return dx * dx + dy * dy
            }
            alternatives.sort { distance($0) < distance($1) }
            positions.append(contentsOf: alternatives)
        }
        let candidates = positions.map { point in
            CGRect(x: min(max(point.x, safe.minX), safe.maxX - width),
                   y: min(max(point.y, safe.minY), safe.maxY - height), width: width, height: height)
        }
        let frame = candidates.first { candidate in
            !obstacles.contains { candidate.intersects($0) }
        } ?? candidates[0]
        let tip = head.x - frame.minX
        return Self(frame: frame, tipX: min(244, max(20, tip)),
                    showsBeads: frame.minY >= head.y && tip >= 20 && tip <= 244)
    }
}
