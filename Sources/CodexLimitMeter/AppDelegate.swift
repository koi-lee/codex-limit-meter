import Cocoa
import SwiftUI
import Combine

func isRunningFromMountedDiskImage(bundlePath: String = Bundle.main.bundlePath) -> Bool {
    let path = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
    return path == "/Volumes" || path.hasPrefix("/Volumes/")
}

@main
struct CodexLimitMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let showOnAllDesktopsKey = "showOnAllDesktops"
    var window: FloatingWindow!
    var tracker = UsageTracker()
    var timer: Timer?
    var statusItem: NSStatusItem?
    var usageCancellable: AnyCancellable?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show in Dock and menu bar (regular app)
        NSApp.setActivationPolicy(.regular)

        if isRunningFromMountedDiskImage() {
            showInstallRequiredAlert()
            NSApp.terminate(nil)
            return
        }
        
        // Set custom dock icon from Resources
        if let iconPath = findResource("AppIcon", ext: "png"),
           let iconImage = NSImage(contentsOfFile: iconPath) {
            iconImage.size = NSSize(width: 128, height: 128)
            NSApp.applicationIconImage = iconImage
        }
        
        // Create the floating window
        let contentView = ContentView()
            .environmentObject(tracker)
        
        window = FloatingWindow(
            contentRect: NSRect(x: 100, y: 100, width: 260, height: 172),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        applyDesktopVisibilityPreference()
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 20
        hostingView.layer?.masksToBounds = true
        
        window.contentView = hostingView
        centerWindow()
        window.makeKeyAndOrderFront(nil)

        usageCancellable = tracker.$usage
            .receive(on: RunLoop.main)
            .sink { [weak self] usage in
                self?.resizeWindow(for: usage)
            }
        
        // Initial refresh
        tracker.refresh()
        
        // Auto-refresh every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            self.tracker.refresh()
        }
        
        // Setup menu bar icon
        setupStatusItem()
    }

    private func showInstallRequiredAlert() {
        let isChinese = tracker.language == .chinese
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = isChinese ? "请先安装到应用程序文件夹" : "Install the app before opening it"
        alert.informativeText = isChinese
            ? "请将 CodexLimitMeter 拖到“应用程序”，推出 Codex Limit Meter 磁盘，然后从“应用程序”打开。"
            : "Drag CodexLimitMeter to Applications, eject the Codex Limit Meter disk, then open the app from Applications."
        alert.addButton(withTitle: isChinese ? "打开应用程序文件夹" : "Open Applications")
        alert.addButton(withTitle: isChinese ? "退出" : "Quit")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func centerWindow() {
        window.center()
    }

    private func resizeWindow(for usage: UsageData) {
        guard window != nil else { return }
        let visibleWindowCount = [usage.primary, usage.secondary].compactMap { $0 }.count
        let targetHeight: CGFloat = usage.dataSource == .loading || visibleWindowCount > 1 ? 172 : 125
        guard window.frame.height != targetHeight else { return }

        var frame = window.frame
        let topEdge = frame.maxY
        frame.size.height = targetHeight
        frame.origin.y = topEdge - targetHeight
        window.setFrame(frame, display: true, animate: true)
        centerWindow()
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
        if let button = statusItem?.button {
            // 使用图片作为菜单栏图标（兼容 build.sh .app 和 Xcode SPM 调试两种模式）
            if let iconPath = findResource("appIcon2", ext: "png"),
               let image = NSImage(contentsOfFile: iconPath) {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
                button.image?.isTemplate = false  // 保持彩色
            } else {
                button.title = "◈"  // 如果图片找不到，退回文字
            }
        }

        
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let isChinese = tracker.language == .chinese
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: isChinese ? "显示悬浮窗" : "Show Window", action: #selector(showWindow), keyEquivalent: ""))
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

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: isChinese ? "退出" : "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func refreshData() {
        tracker.refresh()
    }

    @objc func toggleLanguage() {
        tracker.setLanguage(tracker.language == .chinese ? .english : .chinese)
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

class FloatingWindow: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        self.isMovableByWindowBackground = true
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
