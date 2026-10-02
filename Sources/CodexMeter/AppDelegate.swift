import Cocoa
import SwiftUI
import Combine

/// Reserve room for the expanded constellation when introducing the pet.
func guidePetPlacement(guide: NSRect, screen: NSRect, petSize: NSSize = NSSize(width: 736, height: 410)) -> (guide: NSRect, petOrigin: NSPoint) {
    let area = screen.insetBy(dx: 12, dy: 12)
    let gap: CGFloat = 24
    if guide.width + gap + petSize.width <= area.width {
        let x = area.midX - (guide.width + gap + petSize.width) / 2
        let height = min(388, area.height)
        return (NSRect(x: x, y: area.midY - height / 2, width: guide.width, height: height),
                NSPoint(x: x + guide.width + gap, y: area.midY - petSize.height / 2))
    }
    // Keep both windows usable on smaller displays; guide content can scroll.
    let height = min(388, max(160, area.height - petSize.height - gap))
    let frame = NSRect(x: area.midX - guide.width / 2, y: area.maxY - height,
                       width: guide.width, height: height)
    return (frame, NSPoint(x: area.midX - petSize.width / 2, y: area.minY))
}

func isRunningFromMountedDiskImage(bundlePath: String = Bundle.main.bundlePath) -> Bool {
    let path = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
    return path == "/Volumes" || path.hasPrefix("/Volumes/")
}

@main
struct CodexMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let showOnAllDesktopsKey = "showOnAllDesktops"
    var window: FloatingWindow!
    var tracker = UsageTracker()
    let announcements = AnnouncementService()
    var timer: Timer?
    var statusItem: NSStatusItem?
    var usageCancellable: AnyCancellable?
    var loginCancellable: AnyCancellable?
    var pet: PetWindowController?
    private var accountWindow: NSWindow?
    private var demo: DemoSession?
    private let demoPresentation = DemoPresentationState()
    private var displayUsage: UsageData { demo?.usage ?? tracker.usage }
    private var displayState: PetState {
        var value = PetState(displayUsage, chinese: tracker.language == .chinese)
        value.isDemo = demo != nil
        return value
    }
    @objc private func toggleDemo() {
        if demo != nil {
            demo = nil
            demoPresentation.isActive = false
            pet?.setDemo(nil)
            announcements.setDemoSuspended(false)
            tracker.resumeAfterDemo()
        } else {
            demo = DemoSession()
            demoPresentation.isActive = true
            tracker.suspendForDemo()
            announcements.setDemoSuspended(true)
            accountWindow?.orderOut(nil)
        }
        applyPetMode()
        updateQuotaIcon(displayUsage)
        rebuildStatusMenu()
    }

    private func applyPetMode() {
        if pet == nil {
            let controller = PetWindowController()
            controller.onLayout = { [weak self] in
                DispatchQueue.main.async { self?.arrangeGuideAndPet() }
            }
            pet = controller
        }
        pet?.setDemo(demo)
        updatePetQuotaStatus(displayUsage)
        pet?.messages.exitDemo = { [weak self] in
            guard let self, self.demo != nil else { return }
            self.toggleDemo()
        }
        pet?.update(displayState, observedAt: displayUsage.lastUpdated)
        pet?.show(near: window.frame, allDesktops: showsOnAllDesktops)
        pet?.updateAnnouncements(announcements)
    }

    private func updatePetQuotaStatus(_ usage: UsageData) {
        guard let pet else { return }
        pet.messages.refreshQuota = { [weak self] in self?.tracker.refresh() }
        pet.messages.connectQuotaAccount = { [weak self] in self?.showAccountWindow() }
        pet.messages.reloginQuotaAccount = { [weak self] in self?.tracker.reloginStoreAccount() }
        pet.messages.quotaNeedsLogin = demo == nil
            && tracker.usesStoreAuthentication
            && !tracker.isStoreRegionRestricted
            && tracker.storeLoginState != .signedIn
        pet.messages.quotaCanRelogin = shouldOfferQuotaRelogin(
            isDemo: demo != nil,
            usesStoreAuthentication: tracker.usesStoreAuthentication,
            regionRestricted: tracker.isStoreRegionRestricted,
            isSignedIn: tracker.storeLoginState == .signedIn,
            hasReadError: usage.dataSource == .error
        )
        if demo != nil {
            pet.messages.quotaReadStatus = "演示额度，不代表真实账号状态。"
        } else if usage.dataSource == .appServer, (usage.primary != nil || usage.secondary != nil) {
            pet.messages.quotaReadStatus = "已同步本 App 当前连接账号的额度"
        } else if tracker.isStoreRegionRestricted {
            pet.messages.quotaReadStatus = tracker.storeRegionNotice
        } else if tracker.usesStoreAuthentication && tracker.storeLoginState != .signedIn {
            pet.messages.quotaReadStatus = "尚未连接本 App 账号；Codex 主应用的登录状态不会自动共享。"
        } else if usage.dataSource == .loading {
            pet.messages.quotaReadStatus = "正在读取本 App 连接账号的额度…"
        } else if usage.dataSource == .error {
            pet.messages.quotaReadStatus = tracker.usesStoreAuthentication
                ? (tracker.language == .chinese
                   ? "本 App 账号已连接，但额度服务读取失败。点击刷新重试；持续失败请在菜单栏退出本 App 账号后重新连接。"
                   : "This app is connected, but the quota service failed. Refresh to retry; if it persists, sign out from this app's menu and reconnect.")
                : tracker.appServerErrorText(language: tracker.language)
        } else {
            pet.messages.quotaReadStatus = "额度响应中没有可用窗口，请点击刷新重试。"
        }
    }

    private func showAccountWindow() {
        if accountWindow == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Codex Meter · 账号登录"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: StoreLoginView(onDemo: { [weak self] in self?.toggleDemo() }).environmentObject(tracker))
            panel.center()
            accountWindow = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        accountWindow?.makeKeyAndOrderFront(nil)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        tracker.exitDemoBeforeLogin = { [weak self] in
            guard let self, self.demo != nil else { return }
            self.toggleDemo()
        }
        // Show in Dock and menu bar (regular app)
        NSApp.setActivationPolicy(.regular)

        if isRunningFromMountedDiskImage() {
            showInstallRequiredAlert()
            NSApp.terminate(nil)
            return
        }
        
        // Set custom dock icon from Resources
        if let iconPath = findResource("BrandIcon", ext: "png"),
           let iconImage = NSImage(contentsOfFile: iconPath) {
            iconImage.size = NSSize(width: 128, height: 128)
            NSApp.applicationIconImage = iconImage
        }
        
        // Hidden placement anchor only; all quota presentation belongs to the pet.
        window = FloatingWindow(contentRect: NSRect(x: 100, y: 100, width: 256, height: 286),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        applyDesktopVisibilityPreference()
        centerWindow()

        usageCancellable = tracker.$usage
            .receive(on: RunLoop.main)
            .sink { [weak self] usage in
                guard let self, self.demo == nil else { return }
                self.updateQuotaIcon(usage)
                self.updatePetQuotaStatus(usage)
                self.pet?.update(PetState(usage, chinese: self.tracker.language == .chinese), observedAt: usage.lastUpdated)
            }
        
        loginCancellable = Publishers.CombineLatest3(tracker.$storeLoginState, tracker.$skipStoreLogin, tracker.$accountRegionAccess)
            .receive(on: RunLoop.main).sink { [weak self] _, _, _ in
                guard let self else { return }
                if self.tracker.storeLoginState == .signedIn || self.tracker.skipStoreLogin || self.tracker.isStoreRegionRestricted { self.accountWindow?.orderOut(nil) }
                self.rebuildStatusMenu()
            }

        // Initial refresh
        tracker.refresh()
        
        // Auto-refresh every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.tracker.refresh() }
        }
        
        // Setup menu bar icon
        setupStatusItem()
        announcements.chinese = { [weak self] in self?.tracker.language == .chinese }
        announcements.onChange = { [weak self] in
            guard let self else { return }; self.rebuildStatusMenu(); self.pet?.updateAnnouncements(self.announcements)
        }
        announcements.onOpenAnnouncement = { [weak self] id in
            guard let self else { return }
            if self.pet == nil { self.applyPetMode() }
            self.pet?.updateAnnouncements(self.announcements)
            self.pet?.openAnnouncement(id)
        }
        announcements.start()
        if !needsWelcomeGuide { applyPetMode(); rebuildStatusMenu() }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.announcements.refreshAuthorization()
            let key = "onboarding.guide.v1.seen"
            guard CommandLine.arguments.contains("--show-guide") || !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)
            self.showReminderIntroduction()
        }
    }

    private var needsWelcomeGuide: Bool {
        CommandLine.arguments.contains("--show-guide") || !UserDefaults.standard.bool(forKey: "onboarding.guide.v1.seen")
    }
    private var guideWindow: NSWindow?

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === guideWindow else { return }
        guideWindow = nil
        applyPetMode()
        rebuildStatusMenu()
    }

    private func arrangeGuideAndPet() {
        guard let guide = guideWindow, let pet, pet.panel.isVisible,
              let screen = guide.screen ?? NSScreen.main else { return }
        let placement = guidePetPlacement(guide: guide.frame, screen: screen.visibleFrame,
                                          petSize: pet.panel.frame.size)
        guide.setFrame(placement.guide, display: true)
        pet.panel.setFrameOrigin(placement.petOrigin)
        pet.panel.keepInsideScreen()
    }

    @objc private func showReminderIntroduction() {
        if let guideWindow {
            NSApp.activate(ignoringOtherApps: true)
            if guideWindow.isMiniaturized { guideWindow.deminiaturize(nil) }
            guideWindow.makeKeyAndOrderFront(nil)
            guideWindow.orderFrontRegardless()
            return
        }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.orderOut(nil)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.title = "Codex Meter · 使用指南"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: MeterWelcomeGuide(tracker: tracker, announcements: announcements,
            demoPresentation: demoPresentation,
            demo: { [weak self] in
                guard let self else { return }
                self.toggleDemo()
                DispatchQueue.main.async { self.arrangeGuideAndPet() }
            }, openNotifications: { [weak self] in self?.openNotificationSettings() },
            finish: { [weak self] in self?.guideWindow?.close(); self?.guideWindow = nil }))
        guideWindow = panel
        panel.center(); panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func reminderIntroduction(chinese: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = chinese ? "有重置预告时，及时提醒你" : "Get notified about quota reset announcements"
        alert.informativeText = chinese
            ? "开启通知后，有新的额度重置预告或进展，我们会主动提醒你，方便安排额度使用。\n\n未开启通知，你可能错过预告；仍可在消息星盘中主动查看。\n\n提醒需要 App 保持运行，并允许 macOS 通知；不保证一定提前获得预告。"
            : "Enable notifications to hear about new quota reset announcements and progress.\n\nWithout notifications, you may miss announcements. You can still check the message constellation.\n\nThe app must remain running and macOS notifications must be allowed. Advance notice is not guaranteed."
        alert.addButton(withTitle: chinese ? "开启消息提醒" : "Enable Notifications")
        alert.addButton(withTitle: chinese ? "稍后再说" : "Not Now")
        return alert
    }

    private func showInstallRequiredAlert() {
        let isChinese = tracker.language == .chinese
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = isChinese ? "请先安装到应用程序文件夹" : "Install the app before opening it"
        alert.informativeText = isChinese
            ? "请将 Codex Meter 拖到“应用程序”，推出 Codex Meter 磁盘，然后从“应用程序”打开。"
            : "Drag Codex Meter to Applications, eject the Codex Meter disk, then open the app from Applications."
        alert.addButton(withTitle: isChinese ? "打开应用程序文件夹" : "Open Applications")
        alert.addButton(withTitle: isChinese ? "退出" : "Quit")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        pet?.stop()
        announcements.stop()
        tracker.stopStoreAccount()
    }

    private func centerWindow() {
        window.center()
        updateDetailsSide()
    }

    func windowDidMove(_ notification: Notification) {
        window.keepInsideScreen()
        updateDetailsSide()
    }
    func windowDidChangeScreen(_ notification: Notification) {
        window.keepInsideScreen()
        updateDetailsSide()
    }
    func windowDidResize(_ notification: Notification) {
        window.keepInsideScreen()
        updateDetailsSide()
    }

    private func updateDetailsSide() {
        guard let window, let screen = window.screen else { return }
        tracker.detailsOnLeft = detailsPreferLeft(parent: window.frame, screen: screen.visibleFrame)
    }

    /// 查找资源文件路径，兼容两种运行模式：
    /// 1. build.sh 构建的 .app → Bundle.main 的 Resources 目录
    /// 2. Xcode ⌘R 调试（SPM）→ SPM 生成的子 bundle
    private func findResource(_ name: String, ext: String) -> String? {
        // 1. 优先从 Bundle.main 查找（build.sh .app 包）
        if let path = Bundle.main.path(forResource: name, ofType: ext) {
            return path
        }
        
        // 2. 遍历 Bundle.main 同级目录下的 .bundle（SPM 资源 bundle）
        let bundleDir = Bundle.main.bundleURL
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: bundleDir, includingPropertiesForKeys: nil
        ) {
            for entry in entries where entry.pathExtension == "bundle" {
                if let bundle = Bundle(url: entry),
                   let path = bundle.path(forResource: name, ofType: ext) {
                    return path
                }
            }
        }
        
        return nil
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateQuotaIcon(tracker.usage)
        rebuildStatusMenu()
    }

    private func updateQuotaIcon(_ usage: UsageData) {
        guard let button = statusItem?.button else { return }
        let state = QuotaIconState(usage)
        button.image = state.image()
        let chinese = tracker.language == .chinese
        let window = QuotaIconState.windowLabel(usage, chinese: chinese)
        button.title = (demo != nil ? "Demo · " : "") + (window.isEmpty ? "" : window + " ") + state.statusText
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let description: String
        switch state {
        case .value(let percent): description = chinese ? "Codex Meter · \(window)额度剩余 \(percent)%" : "Codex Meter · \(window) quota remaining \(percent)%"
        case .loading: description = chinese ? "Codex Meter · 正在读取额度" : "Codex Meter · Loading quota"
        case .unavailable: description = chinese ? "Codex Meter · 额度不可用" : "Codex Meter · Quota unavailable"
        }
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    private func rebuildStatusMenu() {
        let isChinese = tracker.language == .chinese
        let menu = NSMenu()
        menu.delegate = self
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let versionItem = NSMenuItem(title: "Codex Meter \(version)（\(build)）", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        let subtitle = NSMenuItem(title: isChinese ? "额度查看 · 重置监控" : "Usage tracking · Reset monitoring", action: nil, keyEquivalent: "")
        subtitle.isEnabled = false
        menu.addItem(subtitle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: isChinese ? "显示桌宠" : "Show Companion", action: #selector(showWindow), keyEquivalent: ""))
        let demoItem = NSMenuItem(title: demo == nil
            ? (isChinese ? "体验演示（示例数据）" : "Try Demo (Sample Data)")
            : (isChinese ? "退出演示并继续引导…" : "Exit Demo and Continue Guide…"),
            action: demo == nil ? #selector(toggleDemo) : #selector(exitDemoAndContinueGuide), keyEquivalent: "")
        demoItem.target = self
        menu.addItem(demoItem)
        let characters = NSMenuItem(title: isChinese ? "选择角色" : "Choose Character", action: nil, keyEquivalent: "")
        let characterMenu = NSMenu()
        for character in PetCharacter.allCases {
            let item = NSMenuItem(title: character.title(chinese: isChinese), action: #selector(changeCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = character.rawValue
            item.state = PetCharacter.selected(in: .standard) == character ? .on : .off
            characterMenu.addItem(item)
        }
        characters.submenu = characterMenu
        menu.addItem(characters)
        let sizes = NSMenuItem(title: isChinese ? "桌宠大小" : "Companion Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for size in PetDisplaySize.allCases {
            let item = NSMenuItem(title: size.title(chinese: isChinese), action: #selector(changePetSize(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = size.rawValue
            item.state = PetDisplaySize.selected(in: .standard) == size ? .on : .off
            sizeMenu.addItem(item)
        }
        sizes.submenu = sizeMenu; menu.addItem(sizes)

        menu.addItem(NSMenuItem(title: isChinese ? "刷新数据" : "Refresh", action: #selector(refreshData), keyEquivalent: "r"))
        let desktopItem = NSMenuItem(
            title: isChinese ? "在所有桌面显示" : "Show on All Desktops",
            action: #selector(toggleDesktopVisibility),
            keyEquivalent: ""
        )
        desktopItem.state = showsOnAllDesktops ? .on : .off
        menu.addItem(desktopItem)

        menu.addItem(NSMenuItem(
            title: isChinese ? "切换到 English" : "Switch to 中文",
            action: #selector(toggleLanguage),
            keyEquivalent: ""
        ))

        if tracker.usesStoreAuthentication {
            if tracker.isStoreRegionRestricted {
                let message = NSMenuItem(title: tracker.storeRegionNotice, action: nil, keyEquivalent: "")
                message.isEnabled = false
                menu.addItem(message)
            } else {
                let signedIn = tracker.storeLoginState == .signedIn
                let account = NSMenuItem(title: signedIn ? (isChinese ? "退出本 App 的账号登录" : "Sign out of this app") : (isChinese ? "连接 ChatGPT 账号…" : "Connect ChatGPT account…"), action: #selector(storeAccountAction), keyEquivalent: "")
                menu.addItem(account)
            }
        }
        let announcementItem = NSMenuItem(title: isChinese ? "公开重置消息" : "Public Reset Updates", action: nil, keyEquivalent: "")
        announcementItem.identifier = NSUserInterfaceItemIdentifier("announcements")
        announcementItem.submenu = announcementMenu(chinese: isChinese)
        menu.addItem(announcementItem)

        menu.addItem(NSMenuItem.separator())
        let guideItem = NSMenuItem(title: isChinese ? "使用指南…" : "Getting Started…", action: #selector(showReminderIntroduction), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)
        menu.addItem(NSMenuItem(title: isChinese ? "隐私与支持…" : "Privacy & Support…", action: #selector(showPrivacyAndSupport), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: isChinese ? "退出" : "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    @objc private func exitDemoAndContinueGuide() {
        if demo != nil { toggleDemo() }
        showReminderIntroduction()
    }
    
    @objc private func testPetBubble() {
        applyPetMode(); pet?.showTestBubble()
    }
    @objc private func changePetSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let size = PetDisplaySize(rawValue: value) else { return }
        if pet == nil { applyPetMode() }
        pet?.selectDisplaySize(size)
        rebuildStatusMenu()
    }

    @objc private func changeCharacter(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let character = PetCharacter(rawValue: value) else { return }
        if pet == nil { applyPetMode() }
        pet?.selectCharacter(character)
        rebuildStatusMenu()
    }

    @objc private func showPrivacyAndSupport() {
        let chinese = tracker.language == .chinese
        let alert = NSAlert()
        alert.messageText = chinese ? "隐私与支持" : "Privacy & Support"
        if tracker.isStoreRegionRestricted {
            alert.informativeText = chinese
                ? "此区域的个人额度连接暂不可用。桌宠演示使用样例数据；公开消息请求发送到 starshoreai.com，点击原文会打开外部网站。可在菜单中关闭公告提醒。\n\n客服邮箱：service@starshoreai.com"
                : "Personal quota access is unavailable in this App Store region. The desktop companion demo uses sample data. Public updates are requested from starshoreai.com; source links open external websites. You can disable announcements from the menu.\n\nSupport: service@starshoreai.com"
        } else {
            alert.informativeText = chinese
            ? "本应用是独立第三方工具，非 OpenAI 官方产品。商店模式通过官方浏览器登录，凭据保存在本 App 沙盒内；额度请求发送到 OpenAI。公告请求发送到 starshoreai.com，点击原文会打开外部网站。可在菜单中关闭公告提醒或退出本 App 登录。\n\n客服邮箱：service@starshoreai.com"
            : "This is an independent third-party utility, not an official OpenAI product. Store mode signs in through the official browser and stores credentials in this app’s sandbox. Quota requests go to OpenAI. Announcements are requested from starshoreai.com; source links open external websites. You can disable announcements or sign out from the menu.\n\nSupport: service@starshoreai.com"
        }
        alert.addButton(withTitle: chinese ? "关闭" : "Close")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func storeAccountAction() {
        guard tracker.canUsePersonalQuota else { return }
        if demo != nil { toggleDemo() }
        if tracker.storeLoginState == .signedIn { tracker.logoutStoreAccount() }
        else { tracker.skipStoreLogin = false; showAccountWindow() }
    }

    private func announcementMenu(chinese: Bool) -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: chinese ? "接收公告提醒" : "Receive Announcements", action: #selector(toggleAnnouncements), keyEquivalent: "")
        toggle.state = announcements.enabled ? .on : .off
        menu.addItem(toggle)
        let check = NSMenuItem(title: announcements.checking ? (chinese ? "检查中…" : "Checking…") : (chinese ? "立即检查公告" : "Check Now"), action: announcements.checking ? nil : #selector(checkAnnouncements), keyEquivalent: "")
        menu.addItem(check)
        if announcements.enabled && announcements.authorization == .denied {
            menu.addItem(NSMenuItem(title: chinese ? "通知未授权，打开通知设置…" : "Notifications denied — Open Settings…", action: #selector(openNotificationSettings), keyEquivalent: ""))
        }
        if announcements.notificationFailed {
            menu.addItem(NSMenuItem(title: chinese ? "通知发送失败，将在下次检查重试" : "Notification failed; retrying next check", action: nil, keyEquivalent: ""))
        }
        if announcements.failed {
            let failureText: String
            if announcements.notPublished {
                failureText = chinese ? "公告源尚未发布" : "Announcement feed not published yet"
            } else if announcements.lastSuccess == nil {
                failureText = chinese ? "检查失败，请稍后重试" : "Check failed; try again later"
            } else {
                failureText = chinese ? "检查失败，保留上次结果" : "Check failed; showing previous results"
            }
            menu.addItem(NSMenuItem(title: failureText, action: nil, keyEquivalent: ""))
        }
        let checked = announcements.lastSuccess.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) }
        menu.addItem(NSMenuItem(title: checked.map { (chinese ? "上次成功检查：" : "Last successful check: ") + $0 } ?? (chinese ? "尚未检查" : "Not checked yet"), action: nil, keyEquivalent: ""))
        let overview = ResetAnnouncementOverview(entries: announcements.entries, now: Date())
        func label(_ text: String) {
            menu.addItem(NSMenuItem(title: text, action: nil, keyEquivalent: ""))
        }
        func entryItem(_ entry: Announcement, upcoming: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: entry.resetMenuTitle(chinese: chinese, upcoming: upcoming), action: #selector(openAnnouncement(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.sourceURL
            item.toolTip = entry.summary.value(chinese) + "\n" + entry.audience.value(chinese)
            let details = NSMenu()
            let source = NSMenuItem(title: chinese ? "查看原文与适用范围…" : "View original post and eligibility…", action: #selector(openAnnouncement(_:)), keyEquivalent: "")
            source.target = self
            source.representedObject = entry.sourceURL
            details.addItem(NSMenuItem(title: entry.audience.value(chinese), action: nil, keyEquivalent: ""))
            details.addItem(source)
            item.submenu = details
            return item
        }
        menu.addItem(.separator())
        label(chinese ? "接下来的重置" : "Upcoming resets")
        if overview.upcoming.isEmpty {
            label(announcements.failed || announcements.lastSuccess == nil
                ? (chinese ? "消息尚未检查完整，暂无法判断" : "Check incomplete; upcoming reset unknown")
                : (chinese ? "暂未发现新的重置预告" : "No new reset announcement found"))
        }
        for entry in overview.upcoming { menu.addItem(entryItem(entry, upcoming: true)) }
        menu.addItem(.separator())
        label(chinese ? "最近一次重置" : "Latest reset announcement")
        if let completed = overview.latestCompleted {
            menu.addItem(entryItem(completed))
        } else {
            label(chinese ? "暂无重置完成消息" : "No reset completion message available")
        }
        if !overview.history.isEmpty {
            let historyItem = NSMenuItem(title: chinese ? "历史消息" : "History", action: nil, keyEquivalent: "")
            let history = NSMenu()
            for entry in overview.history.prefix(20) { history.addItem(entryItem(entry)) }
            historyItem.submenu = history
            menu.addItem(historyItem)
        }
        menu.addItem(.separator())
        label(chinese ? "时间均为北京时间；完成时间以原文为准" : "Beijing time; shown dates are post times unless marked expected")
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            await announcements.refreshAuthorization()
            if let item = menu.items.first(where: { $0.identifier?.rawValue == "announcements" }) {
                item.submenu = announcementMenu(chinese: tracker.language == .chinese)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await announcements.refreshAuthorization() }
    }

    @objc private func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    @objc private func toggleAnnouncements() {
        Task { await announcements.setEnabled(!announcements.enabled) }
    }

    @objc private func checkAnnouncements() {
        Task { await announcements.check() }
    }

    @objc private func openAnnouncement(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String, let url = Announcement.source(text) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showWindow() {
        applyPetMode()
    }
    
    @objc func refreshData() {
        tracker.refresh()
    }

    @objc func toggleLanguage() {
        tracker.setLanguage(tracker.language == .chinese ? .english : .chinese)
        updateQuotaIcon(displayUsage)
        pet?.update(displayState, observedAt: displayUsage.lastUpdated)
        rebuildStatusMenu()
    }

    @objc func toggleDesktopVisibility() {
        UserDefaults.standard.set(!showsOnAllDesktops, forKey: showOnAllDesktopsKey)
        applyDesktopVisibilityPreference()
        rebuildStatusMenu()
    }

    private var showsOnAllDesktops: Bool {
        UserDefaults.standard.object(forKey: showOnAllDesktopsKey) as? Bool ?? true
    }

    private func applyDesktopVisibilityPreference() {
        pet?.setAllDesktops(showsOnAllDesktops)
        if showsOnAllDesktops {
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications]
        } else {
            window.collectionBehavior = [.moveToActiveSpace, .canJoinAllApplications]
        }
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

/// Clamp the whole card, leaving a small inset from the Dock and menu bar.
func boundedFloatingFrame(_ frame: NSRect, visibleFrame: NSRect, inset: CGFloat = 8) -> NSRect {
    let bounds = visibleFrame.insetBy(dx: inset, dy: inset)
    var result = frame
    result.origin.x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
    result.origin.y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
    return result
}

/// Incremental movement means reversing at an edge responds immediately.
func floatingDragFrame(_ frame: NSRect, from previous: NSPoint, to mouse: NSPoint,
                       visibleFrame: NSRect) -> NSRect {
    boundedFloatingFrame(frame.offsetBy(dx: mouse.x - previous.x, dy: mouse.y - previous.y),
                         visibleFrame: visibleFrame)
}

class FloatingWindow: NSPanel {
    private var correctingPosition = false

    func keepInsideScreen() {
        guard !correctingPosition else { return }
        // Cursor ownership permits crossing a shared display edge without trapping the card.
        let dragScreen = NSEvent.pressedMouseButtons & 1 != 0
            ? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } : nil
        // Before a hidden window is ordered front, `screen` may still describe
        // its old display. Resolve the requested global frame first.
        let frameScreen = NSScreen.screens.max { a, b in
            let x = frame.intersection(a.frame), y = frame.intersection(b.frame)
            return (x.isNull ? 0 : x.width * x.height) < (y.isNull ? 0 : y.width * y.height)
        }.flatMap { frame.intersects($0.frame) ? $0 : nil }
        guard let target = dragScreen ?? frameScreen ?? screen ?? NSScreen.main else { return }
        let bounded = boundedFloatingFrame(frame, visibleFrame: target.visibleFrame)
        guard bounded.origin != frame.origin else { return }
        correctingPosition = true
        setFrameOrigin(bounded.origin)
        correctingPosition = false
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        self.isMovableByWindowBackground = false
        self.isMovable = false
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.level = .floating
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isOpaque = false
        // Allow this floating overlay to move across displays and join Spaces,
        // full-screen apps, and Stage Manager groups owned by other apps.
        self.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications]
        self.isReleasedWhenClosed = false
        
        // Ensure contentView layer is transparent and clipped to corner radius
        if let contentView = self.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
            contentView.layer?.cornerRadius = 20
            contentView.layer?.masksToBounds = true
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}


/// Keep unknown data distinct from a confirmed empty quota.
enum QuotaIconState: Equatable {
    case value(Int), loading, unavailable

    init(_ usage: UsageData) {
        if usage.dataSource == .loading { self = .loading; return }
        guard usage.dataSource == .appServer,
              let window = usage.secondary ?? usage.primary else {
            self = .unavailable; return
        }
        self = .value(100 - min(100, max(0, window.usedPercent)))
    }

    var fills: [Double] {
        guard case .value(let percent) = self else { return [] }
        return (0..<3).map { min(1, max(0, Double(percent) * 3 / 100 - Double($0))) }
    }

    var statusText: String {
        switch self {
        case .value(let percent): return "\(percent)%"
        case .loading: return "…"
        case .unavailable: return "—"
        }
    }

    static func windowLabel(_ usage: UsageData, chinese: Bool) -> String {
        guard let window = usage.secondary ?? usage.primary else { return "" }
        let minutes = window.windowDurationMins
        if minutes == 10080 { return chinese ? "周" : "Week" }
        guard minutes > 0 else { return "" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m"
    }

    func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let book = NSBezierPath()
            book.move(to: NSPoint(x: 3, y: 14))
            book.curve(to: NSPoint(x: 12, y: 13), controlPoint1: NSPoint(x: 6, y: 16), controlPoint2: NSPoint(x: 9, y: 15))
            book.curve(to: NSPoint(x: 21, y: 14), controlPoint1: NSPoint(x: 15, y: 15), controlPoint2: NSPoint(x: 18, y: 16))
            book.line(to: NSPoint(x: 21, y: 3))
            book.curve(to: NSPoint(x: 12, y: 2), controlPoint1: NSPoint(x: 18, y: 5), controlPoint2: NSPoint(x: 15, y: 4))
            book.curve(to: NSPoint(x: 3, y: 3), controlPoint1: NSPoint(x: 9, y: 4), controlPoint2: NSPoint(x: 6, y: 5))
            book.close()
            book.lineWidth = 1.4
            book.lineJoinStyle = .round
            book.stroke()
            let lines = NSBezierPath()
            for (a, b) in [(NSPoint(x: 12, y: 13), NSPoint(x: 12, y: 2)), (NSPoint(x: 15, y: 11), NSPoint(x: 18, y: 11)), (NSPoint(x: 15, y: 8), NSPoint(x: 18, y: 8))] {
                lines.move(to: a); lines.line(to: b)
            }
            lines.lineWidth = 1.2; lines.lineCapStyle = .round; lines.stroke()
            if case .value(let percent) = self, percent > 0 {
                NSBezierPath(rect: NSRect(x: 5, y: 6, width: 5, height: 6 * Double(percent) / 100)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

}


/// Space is measured in the owning display's coordinates (including negative origins).
func detailsPreferLeft(parent: NSRect, screen: NSRect, width: CGFloat = 320, gap: CGFloat = 20, margin: CGFloat = 12) -> Bool {
    let right = screen.maxX - parent.maxX - margin
    let left = parent.minX - screen.minX - margin
    let required = width + gap
    if right >= required { return false }
    if left >= required { return true }
    return left > right
}

/// Keep the open journal attached to the companion, including on external displays.
func companionCardFrame(anchor: NSRect, size: NSSize, screen: NSRect) -> NSRect {
    let gap: CGFloat = 12
    let left = detailsPreferLeft(parent: anchor, screen: screen, width: size.width, gap: gap)
    return boundedFloatingFrame(NSRect(x: left ? anchor.minX-size.width-gap : anchor.maxX+gap,
                                      y: anchor.maxY-size.height, width: size.width, height: size.height),
                                visibleFrame: screen)
}

@MainActor private final class DemoPresentationState: ObservableObject {
    @Published var isActive = false
}

private struct MeterWelcomeGuide: View {
    @ObservedObject var tracker: UsageTracker
    @ObservedObject var announcements: AnnouncementService
    @ObservedObject var demoPresentation: DemoPresentationState
    @Environment(\.colorScheme) private var colorScheme
    var demo: () -> Void
    var openNotifications: () -> Void
    var finish: () -> Void
    @State private var step = 0
    @State private var appliedInitialStep = false
    private var guideAccent: Color {
        colorScheme == .dark ? Color(hex: 0xD8B9E2) : Color(hex: 0x71536E)
    }
    private var guideAccentTint: Color {
        colorScheme == .dark ? Color(hex: 0x8C5697) : Color(hex: 0x71536E)
    }
    private var guideCalloutBackground: Color {
        colorScheme == .dark ? Color(hex: 0x71536E).opacity(0.30) : Color(hex: 0x71536E).opacity(0.10)
    }
    private var notificationAppName: String {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
              !name.isEmpty else { return "Codex Meter" }
        return name
    }
    private var connected: Bool {
        tracker.usesStoreAuthentication ? tracker.storeLoginState == .signedIn : tracker.usage.primary != nil || tracker.usage.secondary != nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            Text("第 \(step + 1) 步，共 3 步").font(.caption).foregroundColor(.secondary)
            Text(["连接 Codex", "认识你的桌宠", "有重置预告，及时告诉你"][step]).font(.title2.bold())
            if step == 0 {
                if tracker.isStoreRegionRestricted {
                    Text(tracker.storeRegionNotice)
                } else {
                    Text(connected ? "已连接，可以查看你的真实额度。" : "连接后，这里会显示你的真实额度。")
                }
                Button(demoPresentation.isActive
                       ? (tracker.language == .chinese ? "退出演示，恢复真实数据" : "Exit Demo and Restore Live Data")
                       : (tracker.language == .chinese ? "体验演示（示例数据）" : "Try Demo (Sample Data)")) {
                    demo()
                }
                Text(demoPresentation.isActive
                     ? (tracker.language == .chinese ? "当前桌宠显示示例数据；点上方按钮恢复真实数据，再点“下一步”继续引导。" : "The companion is showing sample data. Exit above to restore live data, then choose Next to continue.")
                     : (tracker.language == .chinese ? "体验时指南会保留在旁边；示例不代表真实额度，完成后可退出。" : "The guide stays open beside the demo. Sample data is not your real quota; you can exit when done."))
                    .font(.caption)
                if !connected && !tracker.isStoreRegionRestricted {
                    if tracker.usesStoreAuthentication {
                        switch tracker.storeLoginState {
                        case .connecting, .starting:
                            ProgressView(tracker.storeLoginState == .connecting ? "正在启动登录服务…" : "正在准备官方登录页…")
                        case .waiting:
                            Text("等待在浏览器中完成登录。未看到页面时，可以重新打开。").font(.caption)
                            Button("重新打开登录页") { tracker.reopenStoreLogin() }
                            Button("取消登录") { tracker.cancelStoreLogin() }
                        case .failed:
                            Text("连接或登录未完成，请重试；也可以先体验演示。").font(.caption).foregroundColor(.orange)
                            Button("重试连接 ChatGPT 账号") { tracker.loginToStoreAccount() }
                        case .signingOut:
                            ProgressView("正在退出账号…")
                        case .signedOut:
                            Button("连接 ChatGPT 账号") { tracker.loginToStoreAccount() }
                            Text("在浏览器完成登录后返回；也可以稍后连接。").font(.caption)
                        case .signedIn:
                            EmptyView()
                        }
                    } else {
                        Text("请先在 Codex CLI 中完成登录，再点击检查连接。")
                        Button("检查连接") { tracker.refresh() }
                    }
                }
            } else if step == 1 {
                Text("先点“下一步”继续设置。完成指南后，点击桌宠展开星盘查看额度、消息和变化；拖动桌宠可调整位置。")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        announcements.remindersReady ? "有新预告或进展时，会主动提醒你" : "开启后，有新预告或进展时会主动提醒你",
                        systemImage: announcements.remindersReady ? "bell.badge.fill" : "bell.badge"
                    )
                    .font(.headline)
                    .foregroundStyle(guideAccent)

                    Text(announcements.remindersReady ? "消息提醒已开启；你也可以发送测试提醒。" : "不开启可能错过消息，你仍可随时在星盘查看。")
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(guideCalloutBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(guideAccent.opacity(colorScheme == .dark ? 0.38 : 0.24), lineWidth: 1))

                if announcements.remindersReady {
                    Label("消息提醒已开启", systemImage: "bell.badge")
                    Button(announcements.testingReminder ? "发送中…" : "发送测试提醒") {
                        Task { await announcements.sendTestReminder() }
                    }.disabled(announcements.testingReminder)
                    Text(announcements.testReminderStatus).font(.caption)
                } else if announcements.authorization == .denied {
                    Text("这台 Mac 之前关闭了通知权限，macOS 不会再次弹出授权框。请在系统设置的通知列表中找到「\(notificationAppName)」并开启允许通知。如果出现多个同名项，请选紫色书本图标（与本 App 图标一致）的那一项。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(action: openNotifications) {
                        Text("打开系统通知设置")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(guideAccentTint, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { Task { await announcements.setEnabled(true) } } label: {
                        Text("开启消息提醒")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(guideAccentTint, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                }
                Text("App 需保持运行；预告以消息来源为准，不保证提前获得。").font(.caption).foregroundColor(.secondary)
            }
            }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if step > 0 { Button("上一步") { step -= 1 } }
                Spacer()
                if step == 2 && !announcements.remindersReady {
                    Button("稍后再说") { finish() }
                } else {
                    Button(step == 2 ? "开始使用" : "下一步") {
                        if step < 2 { step += 1 } else { finish() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24).frame(width: 460).frame(maxHeight: .infinity).buttonStyle(.bordered)
        .onAppear {
            guard !appliedInitialStep else { return }
            appliedInitialStep = true
            if connected { step = 1 }
        }
    }

}
