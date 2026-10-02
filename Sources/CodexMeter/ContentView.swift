import SwiftUI
import AppKit

struct ContentView: View {
    var companionStyle = false
    var onClose: (() -> Void)? = nil
    @EnvironmentObject var tracker: UsageTracker
    @EnvironmentObject var announcements: AnnouncementService

    private var showPrimary: Bool {
        tracker.usage.primary != nil || tracker.usage.dataSource == .loading
    }

    private var showSecondary: Bool {
        tracker.usage.secondary != nil || tracker.usage.dataSource == .loading
    }

    private var contentHeight: CGFloat {
        showPrimary && showSecondary ? 172 : 125
    }

    var body: some View {
        Group {
            if tracker.needsStoreLogin {
                StoreLoginView().environmentObject(tracker)
            } else { CompactQuotaView(tracker: tracker, announcements: announcements, companionStyle: companionStyle, onClose: onClose) }
        }
        .modifier(FloatingCardDrag())
    }

    private var meter: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: 0x1C1C1E))
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Codex Meter")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    if let plan = tracker.usage.planType {
                        Text(plan.capitalized)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: 0xFFD60A))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(hex: 0xFFD60A).opacity(0.15))
                            )
                    }

                    Spacer()

                    // Refresh button
                    Button(action: { tracker.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(tracker.language == .chinese ? "刷新数据" : "Refresh")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                if showPrimary {
                    UsageSection(
                        title: windowTitle(tracker.usage.primaryWindowLabel(language: tracker.language)),
                        usedPercent: tracker.usage.primaryUsedPercent,
                        remainingPercent: tracker.usage.primaryRemainingPercent,
                        resetFormatted: tracker.usage.primaryResetFormatted(language: tracker.language),
                        hasData: tracker.usage.primary != nil,
                        isLoading: tracker.usage.dataSource == .loading,
                        language: tracker.language
                    )
                    .padding(.horizontal, 16)
                }

                if showPrimary && showSecondary {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                if showSecondary {
                    UsageSection(
                        title: windowTitle(tracker.usage.secondaryWindowLabel(language: tracker.language)),
                        usedPercent: tracker.usage.secondaryUsedPercent,
                        remainingPercent: tracker.usage.secondaryRemainingPercent,
                        resetFormatted: tracker.usage.secondaryResetFormatted(language: tracker.language),
                        hasData: tracker.usage.secondary != nil,
                        isLoading: tracker.usage.dataSource == .loading,
                        language: tracker.language
                    )
                    .padding(.horizontal, 16)
                }

                Spacer()

                // Footer — merged into single clickable line
                Button(action: { tracker.refresh() }) {
                    HStack(spacing: 4) {
                        if tracker.usage.dataSource == .loading {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                                .modifier(PulseEffect())
                        } else {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                        }

                        Text(footerText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(statusColor.opacity(0.8))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 260, height: contentHeight)
        .animation(.easeInOut(duration: 0.2), value: contentHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var statusColor: Color {
        switch tracker.usage.dataSource {
        case .loading:
            return Color(hex: 0x0A84FF)
        case .appServer:
            return Color(hex: 0x30D158)
        case .config:
            return Color(hex: 0xFF9F0A)
        case .error:
            return Color(hex: 0xFF453A)
        }
    }

    private var footerText: String {
        if tracker.usesStoreAuthentication && tracker.storeLoginState != .signedIn {
            return tracker.language == .chinese ? "尚未登录 · 在菜单中连接账号" : "Sign in from the menu to view limits"
        }
        switch tracker.usage.dataSource {
        case .loading:
            return tracker.language == .chinese ? "正在更新…" : "Updating…"
        case .appServer:
            let prefix = tracker.language == .chinese ? "已同步" : "Synced"
            return "\(prefix) · \(timeString(from: tracker.usage.lastUpdated))"
        case .config:
            let prefix = tracker.language == .chinese ? "手动配置" : "Manual config"
            return "\(prefix) · \(timeString(from: tracker.usage.lastUpdated))"
        case .error:
            return tracker.appServerErrorText(language: tracker.language)
        }
    }

    private func windowTitle(_ label: String) -> String {
        tracker.language == .chinese ? label + "额度" : label + " limit"
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct UsageSection: View {
    let title: String
    let usedPercent: Double      // 0.0 - 1.0
    let remainingPercent: Double // 0.0 - 1.0
    let resetFormatted: String
    let hasData: Bool
    let isLoading: Bool
    let language: AppLanguage

    init(title: String, usedPercent: Double, remainingPercent: Double, resetFormatted: String, hasData: Bool, isLoading: Bool = false, language: AppLanguage) {
        self.title = title
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetFormatted = resetFormatted
        self.hasData = hasData
        self.isLoading = isLoading
        self.language = language
    }

    // Color based on REMAINING percentage
    private var barColor: Color {
        if remainingPercent < 0.20 {
            return Color(hex: 0xFF453A)   // red — critical
        } else if remainingPercent < 0.40 {
            return Color(hex: 0xFF9F0A)   // orange — warning
        } else {
            return Color(hex: 0x30D158)   // green — healthy
        }
    }

    @State private var shimmerOffset: CGFloat = -228

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: title (left) + remaining % (right, prominent)
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.gray.opacity(0.85))

                Spacer()

                if hasData {
                    Text(language == .chinese
                        ? "剩余 \(Int(remainingPercent * 100))%"
                        : "\(Int(remainingPercent * 100))% left")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(barColor)
                } else if isLoading {
                    Text(language == .chinese ? "加载中..." : "Loading...")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: 0x0A84FF).opacity(0.8))
                } else {
                    Text("--")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.gray.opacity(0.4))
                }
            }

            // Row 2: progress bar — shows REMAINING (green fill = available)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)

                if hasData {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(0, CGFloat(remainingPercent) * 228), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: remainingPercent)
                } else if isLoading {
                    // Shimmer effect for loading
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0x0A84FF).opacity(0.1),
                                    Color(hex: 0x0A84FF).opacity(0.5),
                                    Color(hex: 0x0A84FF).opacity(0.1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 80, height: 6)
                        .offset(x: shimmerOffset)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                shimmerOffset = 228
                            }
                        }
                }
            }

            // Row 3: used % (left) + reset time (right)
            HStack {
                if hasData {
                    Text(language == .chinese
                        ? "已用 \(Int(usedPercent * 100))%"
                        : "\(Int(usedPercent * 100))% used")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.gray.opacity(0.5))
                }

                Spacer()

                if hasData && !resetFormatted.isEmpty {
                    Text(resetFormatted)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.gray.opacity(0.5))
                }
            }
        }
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// Pulsing animation for loading indicator dot
struct PulseEffect: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .scaleEffect(isPulsing ? 0.8 : 1.2)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}


struct StoreLoginView: View {
    var onDemo: (() -> Void)?
    @EnvironmentObject var tracker: UsageTracker
    private var chinese: Bool { tracker.language == .chinese }
    private var waiting: Bool { tracker.storeLoginState == .waiting }
    var body: some View {
        Group {
            if tracker.isStoreRegionRestricted {
                VStack(alignment: .leading, spacing: 15) {
                    Text(chinese ? "个人额度连接暂不可用" : "Personal quota access unavailable")
                        .font(.title3.weight(.semibold))
                    Text(tracker.storeRegionNotice)
                        .font(.body).fixedSize(horizontal: false, vertical: true)
                    Button(chinese ? "体验演示（示例数据）" : "Try Demo (Sample Data)") { onDemo?() }
                    Text(chinese ? "在顶部菜单栏打开「公开重置消息」。" : "Open Public Reset Updates from the menu bar.")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 15) {
                    Text(waiting ? (chinese ? "等待浏览器登录" : "Complete sign-in in your browser") : (chinese ? "连接你的 Codex 账号" : "Connect your Codex account"))
                        .font(.title3.weight(.semibold))
                    Text(chinese ? "使用 ChatGPT 登录后查看剩余额度。登录在官方浏览器页面完成，本 App 不接收你的账号密码。" : "Sign in with ChatGPT to see your limits. Sign-in happens on the official website; this app never receives your password.")
                        .font(.body).fixedSize(horizontal: false, vertical: true)
                    if tracker.storeLoginState == .connecting || tracker.storeLoginState == .starting {
                        ProgressView(chinese ? "正在连接…" : "Connecting…")
                    } else if waiting {
                        Button(chinese ? "重新打开登录页" : "Reopen sign-in page") { tracker.reopenStoreLogin() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        if tracker.storeLoginState == .failed {
                            Text(chinese ? "连接或登录未完成，请重试。" : "Connection or sign-in failed. Please retry.")
                                .foregroundColor(.orange).font(.callout)
                        }
                        Button(chinese ? "用 ChatGPT 登录" : "Sign in with ChatGPT") { tracker.loginToStoreAccount() }
                            .buttonStyle(.borderedProminent)
                    }
                    if waiting || tracker.storeLoginState == .starting {
                        Button(chinese ? "取消" : "Cancel") { tracker.cancelStoreLogin() }
                    }
                    Button(chinese ? "体验演示（示例数据）" : "Try Demo (Sample Data)") { onDemo?() }
                    Button(chinese ? "暂不登录，仅查看重置公告" : "Skip sign-in; view reset announcements") {
                        tracker.cancelStoreLogin(); tracker.skipStoreLogin = true
                    }.buttonStyle(.plain)
                    Text(chinese ? "在顶部菜单栏打开「公开重置消息」。登录信息仅保存在本 App 中。非 OpenAI 官方产品。" : "Open Public Reset Updates from the menu bar. Sign-in is stored only in this app. Not an official OpenAI product.")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22).frame(width: 350, height: 360)
        .background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 20))
    }
}


struct CompactQuotaView: View {
    @ObservedObject var tracker: UsageTracker
    @ObservedObject var announcements: AnnouncementService
    var companionStyle = false
    var onClose: (() -> Void)? = nil
    @Environment(\.colorScheme) private var inheritedColorScheme
    @State private var details = false
    private var chinese: Bool { tracker.language == .chinese }
    private var windows: [RateLimitWindow] { [tracker.usage.secondary, tracker.usage.primary].compactMap { $0 } }
    private var overview: ResetAnnouncementOverview { ResetAnnouncementOverview(entries: announcements.entries, now: Date()) }
    private var headline: String {
        if announcements.failed { return chinese ? "预告检查失败" : "Announcement check failed" }
        if announcements.lastSuccess == nil { return chinese ? "正在检查预告…" : "Checking announcements…" }
        if let next = overview.upcoming.first { return next.resetMenuTitle(chinese: chinese, upcoming: true) }
        return chinese ? "暂未发现新预告" : "No new announcement found"
    }
    @ViewBuilder private func newsSection(_ title: String, entries: [Announcement], upcoming: Bool) -> some View {
        Divider()
        Text(title).font(.headline)
        if entries.isEmpty { Text(chinese ? "暂无消息" : "No entries").font(.caption).foregroundStyle(.secondary) }
        ForEach(entries, id: \.id) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.resetMenuTitle(chinese: chinese, upcoming: upcoming)).font(.subheadline.bold())
                Text(entry.summary.value(chinese)).font(.callout)
                Text(entry.audience.value(chinese)).font(.caption).foregroundStyle(.secondary)
                Text((chinese ? "发布于 " : "Posted ") + quotaExactDate(entry.publishedAt, chinese: chinese)).font(.caption).foregroundStyle(.secondary)
                if let url = Announcement.source(entry.sourceURL) { Link(chinese ? "查看原文" : "View source", destination: url) }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if companionStyle {
                    Image(systemName: "moon.stars.fill").foregroundStyle(Color(hex: 0xAE8953))
                }
                Text(companionStyle ? (chinese ? "月夜额度簿" : "Quota journal") : "Codex Meter").font(.headline)
                Spacer()
                if let plan = tracker.usage.planType { Text(plan.capitalized).font(.caption).foregroundStyle(.secondary) }
                Button { tracker.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help(chinese ? "刷新额度" : "Refresh quota")
                    .buttonStyle(.plain)
                if companionStyle {
                    Button { onClose?() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(Color(hex: 0x71536E).opacity(0.10), in: Circle())
                    }.buttonStyle(.plain)
                        .help(chinese ? "收起额度簿" : "Close quota journal")
                        .accessibilityLabel(chinese ? "收起额度簿" : "Close quota journal")
                }
            }
            if tracker.usage.dataSource == .appServer && !windows.isEmpty {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(window.windowDurationMins >= 1440 ? (chinese ? (window.windowDurationMins == 10080 ? "周额度剩余" : "长期额度剩余") : "Long-window remaining") : (chinese ? "短期额度剩余" : "Short-window remaining"))
                                .font(.subheadline)
                            Spacer()
                            Text("\(100 - min(100, max(0, window.usedPercent)))%")
                                .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundColor(quotaLevel(remaining: 100 - window.usedPercent).color)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.10))
                                Capsule().fill(quotaLevel(remaining: 100 - window.usedPercent).color)
                                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, 100 - window.usedPercent))) / 100)
                            }
                        }
                        .frame(height: 8)
                        .accessibilityLabel(chinese ? "剩余额度" : "Remaining quota")
                        .accessibilityValue("\(min(100, max(0, 100 - window.usedPercent)))%")
                        Text((chinese ? "常规恢复：" : "Regular reset: ") + quotaResetCountdown(reset: window.resetsAt, now: Date(), chinese: chinese))
                            .help(quotaExactDate(Date(timeIntervalSince1970: Double(window.resetsAt)), chinese: chinese))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    Text(tracker.usage.dataSource == .loading ? (chinese ? "正在读取额度…" : "Loading quota…") : (chinese ? "额度暂不可用，点击刷新重试" : "Quota unavailable. Refresh to retry."))
                    Spacer(); Text("—").font(.title)
                }.font(.subheadline)
            }
            Divider()
            Button { details = true } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(chinese ? "额外重置预告" : "Extra reset announcements").font(.subheadline.bold()); Spacer(); Image(systemName: "chevron.right") }
                    Text(headline).font(.subheadline).lineLimit(2)
                    Text(announcements.failed ? (chinese ? "暂时无法确认是否有新消息" : "New announcements cannot be confirmed") : (chinese ? "第三方转录 · 查看来源与历史" : "Third-party relay · Sources and history"))
                        .font(.caption).foregroundStyle(.secondary)
                    Link(destination: TiboAnnouncementFeed.attributionURL) {
                        Text(chinese ? "数据来源：codex-reset.com" : "Data: codex-reset.com")
                            .font(.caption2).underline()
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Divider()
            HStack {
                Text(tracker.usage.dataSource == .appServer ? (chinese ? "额度已更新" : "Quota updated") : (chinese ? "额度未同步" : "Quota not synced"))
                Spacer()
                Text(chinese ? "更多选项见状态栏" : "More in menu bar")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(width: 320, height: windows.count > 1 ? 370 : 280)
        .background(companionStyle ? Color(hex: 0xF3EBE1) : Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(companionStyle ? Color(hex: 0xB89A70).opacity(0.45) : .clear, lineWidth: 1))
        .foregroundColor(companionStyle ? Color(hex: 0x49364C) : .primary)
        .environment(\.colorScheme, companionStyle ? .light : inheritedColorScheme)
        .popover(isPresented: $details, attachmentAnchor: .rect(.bounds), arrowEdge: tracker.detailsOnLeft ? .leading : .trailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(chinese ? "额外重置消息" : "Extra reset news").font(.headline)
                        Spacer()
                        Button { details = false } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).help(chinese ? "关闭详情" : "Close details")
                    }
                    Text(headline).font(.subheadline)
                    Button(chinese ? "重新检查" : "Check again") { Task { await announcements.check() } }.disabled(announcements.checking)
                    if let checked = announcements.lastSuccess {
                        Text((chinese ? "上次成功检查：" : "Last successful check: ") + quotaExactDate(checked, chinese: chinese)).font(.caption).foregroundStyle(.secondary)
                    }
                    if !overview.upcoming.isEmpty {
                        newsSection(chinese ? "接下来的重置" : "Upcoming resets", entries: overview.upcoming, upcoming: true)
                    }
                    if let completed = overview.latestCompleted {
                        newsSection(chinese ? "最近一次重置" : "Latest reset", entries: [completed], upcoming: false)
                    }
                    if !overview.history.isEmpty {
                        DisclosureGroup(chinese ? "历史消息（\(overview.history.count)）" : "History (\(overview.history.count))") {
                            newsSection(chinese ? "历史记录" : "Previous announcements", entries: Array(overview.history.prefix(20)), upcoming: false)
                        }
                    }
                    if overview.upcoming.isEmpty && overview.latestCompleted == nil && overview.history.isEmpty {
                        Text(announcements.failed || announcements.lastSuccess == nil
                            ? (chinese ? "尚未取得有效消息，请稍后重试。" : "No verified results yet. Try again shortly.")
                            : (chinese ? "当前没有可展示的重置消息。" : "No reset announcements to display."))
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    Text(chinese ? "未发现预告不代表不会临时重置；请核对原文适用范围。" : "No announcement does not rule out an unscheduled reset. Check eligibility in the source.").font(.caption)
                    Link(destination: TiboAnnouncementFeed.attributionURL) {
                        Text(chinese ? "数据来源：codex-reset.com" : "Data source: codex-reset.com")
                            .font(.caption).underline()
                    }
                }.padding(18)
            }.frame(width: 320, height: announcements.entries.isEmpty ? 230 : 350)
        }
    }
}


func quotaResetCountdown(reset: Int64, now: Date, chinese: Bool) -> String {
    let seconds = Double(reset) - now.timeIntervalSince1970
    guard seconds > 0 else { return chinese ? "等待服务端更新" : "Awaiting server update" }
    let minutes = Int(ceil(seconds / 60))
    let days = minutes / 1440, hours = (minutes % 1440) / 60
    if days > 0 { return chinese ? "还有 \(days) 天 \(hours) 小时" : "in \(days)d \(hours)h" }
    if hours > 0 { return chinese ? "还有 \(hours) 小时 \(minutes % 60) 分钟" : "in \(hours)h \(minutes % 60)m" }
    return chinese ? "还有 \(minutes) 分钟" : "in \(minutes)m"
}

func quotaExactDate(_ date: Date, chinese: Bool) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = chinese ? "M月d日 HH:mm（北京时间）" : "MMM d, HH:mm 'Beijing time'"
    return formatter.string(from: date)
}


enum QuotaLevel: Equatable {
    case healthy, warning, critical
    var color: Color {
        switch self {
        case .healthy: return Color(hex: 0x30D158)
        case .warning: return Color(hex: 0xFF9F0A)
        case .critical: return Color(hex: 0xFF453A)
        }
    }
}

func quotaLevel(remaining: Int) -> QuotaLevel {
    remaining < 20 ? .critical : remaining < 40 ? .warning : .healthy
}

/// Application-controlled dragging avoids the system's window-tiling preview.
private struct FloatingCardDrag: ViewModifier {
    @State private var previousMouse: NSPoint?
    @GestureState private var dragging = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        guard let window = NSApp.windows.compactMap({ $0 as? FloatingWindow }).first else { return }
                        let mouse = NSEvent.mouseLocation
                        let previous = previousMouse ?? NSPoint(
                            x: mouse.x - value.translation.width,
                            y: mouse.y + value.translation.height)
                        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? window.screen
                        if let screen {
                            let next = floatingDragFrame(window.frame, from: previous, to: mouse,
                                                         visibleFrame: screen.visibleFrame)
                            window.setFrameOrigin(next.origin)
                        }
                        previousMouse = mouse
                    }
                    .onEnded { _ in previousMouse = nil }
            )
            .onChange(of: dragging) { active in
                if !active { previousMouse = nil }
            }
    }
}
