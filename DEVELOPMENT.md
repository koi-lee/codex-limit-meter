# 开发指南

适合想要修改源码、调试功能或参与贡献的开发者。

## 工作原理

悬浮窗启动时会在后台运行 `codex app-server` 子进程，通过 stdin/stdout 传输 JSON-RPC 消息：

1. 发送 `initialize` 请求建立连接
2. 发送 `initialized` 通知完成握手
3. 调用 `account/rateLimits/read` 获取配额数据
4. 监听 `account/rateLimits/updated` 通知实现实时更新
5. 每 30 秒主动刷新一次防止漏通知

返回数据结构：

```json
{
  "rateLimits": {
    "primary": {
      "usedPercent": 67,
      "windowDurationMins": 300,
      "resetsAt": 1783839814
    },
    "secondary": {
      "usedPercent": 31,
      "windowDurationMins": 10080,
      "resetsAt": 1784356056
    },
    "planType": "plus"
  }
}
```

- `primary`：短期窗口（通常 5 小时 / 300 分钟）
- `secondary`：长期窗口（通常 1 周 / 10080 分钟）
- `usedPercent`：已用百分比（0-100）
- `resetsAt`：Unix 秒级时间戳

## 技术细节

- **数据源**：Codex App Server JSON-RPC 接口（`codex app-server`）
- **通信方式**：stdin/stdout 逐行 JSON-RPC 2.0
- **初始化流程**：`initialize` → `initialized` → `account/rateLimits/read`
- **实时更新**：监听 `account/rateLimits/updated` 通知
- **刷新频率**：30 秒自动刷新 + 通知驱动更新
- **技术栈**：Swift + SwiftUI + AppKit + Process/Pipe

## 文件结构

```
codex-limit-meter/
├── Sources/CodexLimitMeter/
│   ├── AppDelegate.swift          # App 入口（@main）、浮动窗口、菜单栏
│   ├── UsageTracker.swift         # App Server JSON-RPC 通信 + 数据管理
│   ├── ContentView.swift          # SwiftUI 界面
│   ├── AppIcon.png                # Dock 图标（SPM 资源 + build.sh 共用）
│   └── appIcon2.png               # 菜单栏图标（SPM 资源 + build.sh 共用）
├── build.sh                       # 一键编译脚本
├── Package.swift                  # SPM 包配置
├── .gitignore
├── LICENSE                        # MIT
├── README.md
└── DEVELOPMENT.md                 # 本文件
```

## 命名约定

| 用途 | 名称 |
|------|------|
| 应用显示名 | Codex Limit Meter |
| GitHub 仓库 | codex-limit-meter |
| 代码内部名称 | CodexLimitMeter |
| Bundle ID | com.codex.limit-meter |

## 前提条件

- macOS 13.0+
- **Xcode 15+**（从 App Store 安装，非仅 Command Line Tools）
- Swift 5.9+
- 已安装 Codex CLI 并完成登录

## 用 Xcode 打开项目

本项目使用 Swift Package Manager（SPM）管理，没有 `.xcodeproj` 文件，直接用 Xcode 打开 `Package.swift`：

```bash
open Package.swift
```

Xcode 会自动识别 SPM 项目并解析依赖。首次打开可能需要几秒钟等待索引完成。

## 编辑与调试

三个源文件：

- `AppDelegate.swift` — App 入口（`@main`）、浮动窗口创建、菜单栏设置
- `UsageTracker.swift` — Codex App Server JSON-RPC 通信、数据模型
- `ContentView.swift` — SwiftUI 界面布局

修改源码后按 **⌘R** 运行调试。底部控制台输出日志（前缀 `[CodexLimitMeter]`），可用于调试 JSON-RPC 通信和数据更新。

> **注意**：Xcode 的 ⌘R 是通过 SPM 直接运行可执行文件，**不会**生成 `.app` 包，因此不会显示自定义 Dock 图标。这是正常的调试行为，不影响功能验证。

## 构建可分发的 .app

```bash
chmod +x build.sh
./build.sh
```

`build.sh` 会自动完成：编译 Swift 源码 → 创建 `.app` 包 → 写入 `Info.plist` → 复制图标 → ad-hoc 签名。产物输出到 `dist/`。

打包 DMG 分发包：

```bash
./build.sh --dmg    # 生成 dist/CodexLimitMeter.dmg
```

## Xcode 调试 vs build.sh 构建

| | Xcode ⌘R | build.sh |
|---|---|---|
| 运行方式 | SPM 直接运行可执行文件 | 生成完整 .app 包 |
| 自定义图标 | ❌ 不显示 | ✅ 显示 |
| Dock 图标 | ❌ 不显示 | ✅ 显示 |
| 菜单栏图标 | ✅ 显示 | ✅ 显示 |
| 悬浮窗功能 | ✅ 正常 | ✅ 正常 |
| 调试断点 | ✅ 支持 | ❌ 不支持 |
| 适用场景 | 开发调试 | 发布分发 |

**推荐工作流**：Xcode 编辑 + ⌘R 调试 → 确认功能正常 → `build.sh` 构建 .app → 复制到 /Applications 使用。

## 修改应用图标

1. 准备一张 1024×1024 的 PNG 图片，命名为 `AppIcon.png`
2. 替换 `Sources/CodexLimitMeter/AppIcon.png`
3. 运行 `./build.sh` 重新构建

## 修改菜单栏图标

1. 准备一张 PNG 图片，命名为 `appIcon2.png`
2. 替换 `Sources/CodexLimitMeter/appIcon2.png`
3. 运行 `./build.sh` 重新构建

菜单栏图标在 `AppDelegate.swift` 的 `setupStatusItem()` 方法中加载，使用 `findResource` 兼容 `build.sh` 和 Xcode SPM 两种模式：

```swift
if let iconPath = findResource("appIcon2", ext: "png"),
   let image = NSImage(contentsOfFile: iconPath) {
    image.size = NSSize(width: 18, height: 18)
    button.image = image
    button.image?.isTemplate = false  // 保持彩色
}
```

## 修改刷新频率

在 `AppDelegate.swift` 的 `applicationDidFinishLaunching` 方法中修改 `timeInterval` 参数：

```swift
timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
    // 默认 30 秒，修改 30.0 为你想要的秒数
    self.tracker.refresh()
}
```

## 清理缓存

如果 Xcode 出现奇怪的编译错误（例如文件已重命名但导航器仍显示旧文件）：

```bash
# 清理 SPM 构建缓存
rm -rf .build .swiftpm

# 清理 Xcode DerivedData 缓存
rm -rf ~/Library/Developer/Xcode/DerivedData/codex-limit-meter-*

# 重新打开项目
open Package.swift
```

> **重要**：本项目的入口文件是 `AppDelegate.swift`（使用 `@main` 属性），**不是** `main.swift`。Swift Package Manager 中 `main.swift` 文件名会被视为顶层代码入口，与 `@main` 属性冲突会导致编译错误。如果需要重命名入口文件，请确保不要使用 `main.swift` 这个文件名。
