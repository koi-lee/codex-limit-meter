import Cocoa
import SwiftUI

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
    var window: FloatingWindow!
    var tracker = UsageTracker()
    var timer: Timer?
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show in Dock and menu bar (regular app)
        NSApp.setActivationPolicy(.regular)
        
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
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 20
        hostingView.layer?.masksToBounds = true
        
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        
        // Restore saved position
        restoreWindowPosition()
        
        // Initial refresh
        tracker.refresh()
        
        // Auto-refresh every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            self.tracker.refresh()
        }
        
        // Setup menu bar icon
        setupStatusItem()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        saveWindowPosition()
    }
    
    private func restoreWindowPosition() {
        let defaults = UserDefaults.standard
        if let x = defaults.object(forKey: "windowX") as? CGFloat,
           let y = defaults.object(forKey: "windowY") as? CGFloat {
            var frame = window.frame
            frame.origin.x = x
            frame.origin.y = y
            window.setFrame(frame, display: true)
        }
    }
    
    private func saveWindowPosition() {
        let defaults = UserDefaults.standard
        defaults.set(window.frame.origin.x, forKey: "windowX")
        defaults.set(window.frame.origin.y, forKey: "windowY")
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

        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示悬浮窗", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "刷新数据", action: #selector(refreshData), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func refreshData() {
        tracker.refresh()
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

class FloatingWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isOpaque = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
