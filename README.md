# Codex Limit Meter — Mac 桌面 Codex 额度悬浮窗

> Track Codex 5-hour and weekly usage limits.

一个常驻 Mac 桌面的悬浮窗，通过 Codex App Server JSON-RPC 接口**实时自动获取** Codex 5 小时窗口和周用量数据，支持拖拽到任意位置。

## 效果预览

- 深色圆角卡片风格（参考 iOS 天气小组件）
- **自动实时同步** — 通过 Codex App Server JSON-RPC 获取官方配额数据
- 始终置顶，可拖拽到桌面任意位置
- 标题行显示「剩余 XX%」+ 下次重置时间
- 绿色/橙色/红色进度条预警
- 显示套餐类型（Plus/Pro 等）
- 每 30 秒自动刷新 + 支持手动刷新
- Dock + 菜单栏双显示，随时可退出
- 自定义图标

## 工作原理

悬浮窗启动时会在后台运行 `codex app-server` 子进程，通过 stdin/stdout 传输 JSON-RPC 消息：

1. 发送 `initialize` 请求建立连接
2. 发送 `initialized` 通知完成握手
3. 调用 `account/rateLimits/read` 获取配额数据
4. 监听 `account/rateLimits/updated` 通知实现实时更新
5. 每 60 秒主动刷新一次防止漏通知

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
- 不需要手动配置百分比，全部自动获取

## 安装方式

### 方式一：拖拽安装（推荐）

1. 在 Finder 中定位到 `CodexLimitMeter.app`
2. 将其拖拽到左侧「应用程序」文件夹
3. 在 Launchpad 或 Applications 中双击启动

> 首次打开可能被 Gatekeeper 拦截（因为使用 ad-hoc 签名），前往 **系统设置 → 隐私与安全性**，点击「仍要打开」即可，之后不会再弹。

### 方式二：命令行安装

```bash
# 将应用复制到 Applications 目录
cp -R CodexLimitMeter.app /Applications/

# 启动
open /Applications/CodexLimitMeter.app
```

### 方式三：直接运行（不安装）

```bash
open CodexLimitMeter.app
```

### 方式四：从源码编译

适合需要修改源码或自定义功能的用户。

**前提条件**：
- macOS 13.0+
- Xcode Command Line Tools（`xcode-select --install`）
- Swift 5.9+
- 已安装 Codex CLI（`codex` 命令可用）

```bash
cd codex-limit-meter
chmod +x build.sh
./build.sh
open dist/CodexLimitMeter.app
```

编译脚本会自动完成：编译 Swift 源码 → 生成 .app 包 → 设置 Info.plist → 复制图标 → ad-hoc 签名。

> 如需修改源码或使用 Xcode 调试，请参考[开发指南](#开发指南)章节。

## 首次使用

应用启动后：

1. **Dock** 中会出现应用图标
2. **菜单栏** 出现自定义图标，点击可操作
3. 深色圆角悬浮窗出现在桌面，可拖拽到任意位置
4. 启动后 2-3 秒内自动连接 Codex App Server 并获取数据
5. 底部显示 **● 已同步** 表示连接成功

### 退出应用

三种方式任选：
- Dock 图标右键 → 退出
- 菜单栏图标 → 退出
- 快捷键 ⌘Q

## 界面说明

```
┌──────────────────────────────────────┐
│ Codex Limit Meter  Plus         ↻    │  ← 标题 + 套餐 + 刷新
├──────────────────────────────────────┤
│ 5小时额度                   剩余 33% │  ← 窗口名 + 剩余%
│ ████████████░░░░░░░░░░░░░░░░░░░░░░  │  ← 进度条（绿色=剩余可用）
│ 已用 67%               重置于 15:03  │  ← 已用% + 重置时间
├──────────────────────────────────────┤
│ 1周额度                     剩余 69% │
│ ████████████████████████░░░░░░░░░░░  │
│ 已用 31%              重置于 7月15日  │
├──────────────────────────────────────┤
│ ● 已同步 · 11:30:05                   │  ← 点击可刷新
└──────────────────────────────────────┘
```

### 底部状态指示

| 颜色 | 文字 | 含义 |
|------|------|------|
| 🔵 蓝色 | 正在更新… | 正在连接 / 刷新数据 |
| 🟢 绿色 | 已同步 · HH:mm:ss | 已连接 Codex App Server，数据最新 |
| 🔴 红色 | 更新失败 · 点击重试 | 无法连接 App Server，点击重试 |

## 界面操作

| 操作 | 说明 |
|------|------|
| 拖拽窗口 | 点击深色背景区域拖拽到任意位置 |
| 刷新按钮 | 右上角 ↻ 立即刷新数据 |
| 菜单栏图标 | 显示窗口 / 刷新 / 退出 |
| ⌘Q | 快捷键退出 |

## 颜色预警

进度条颜色基于**剩余比例**（绿色填充 = 可用量）：

| 剩余比例 | 颜色 | 含义 |
|----------|------|------|
| > 40% | 绿色 | 正常 |
| 20% ~ 40% | 橙色 | 接近上限 |
| < 20% | 红色 | 即将耗尽 |

## 系统要求

- macOS 13.0+（Ventura 及以上）
- Apple Silicon (arm64) 或 Intel
- 已安装 Codex CLI 并完成登录（`codex` 命令可用）
- Codex 使用 ChatGPT 账号登录（非 API Key 登录）

## 技术细节

- **数据源**：Codex App Server JSON-RPC 接口（`codex app-server`）
- **通信方式**：stdin/stdout 逐行 JSON-RPC 2.0
- **初始化流程**：`initialize` → `initialized` → `account/rateLimits/read`
- **实时更新**：监听 `account/rateLimits/updated` 通知
- **刷新频率**：30 秒自动刷新 + 通知驱动更新
- **技术栈**：Swift + SwiftUI + AppKit + Process/Pipe

## 命名约定

| 用途 | 名称 |
|------|------|
| 应用显示名 | Codex Limit Meter |
| GitHub 仓库 | codex-limit-meter |
| 代码内部名称 | CodexLimitMeter |
| 中文名 | Codex 额度表 |
| Bundle ID | com.codex.limit-meter |

## 文件结构

```
codex-limit-meter/
├── dist/                          # 构建产物（.gitignore 已排除）
│   ├── CodexLimitMeter.app/       # 编译好的应用包
│   │   └── Contents/
│   │       ├── Info.plist          # 应用配置（图标、Dock 显示等）
│   │       ├── MacOS/CodexLimitMeter  # 可执行文件
│   │       └── Resources/
│   │           ├── AppIcon.png     # Dock/Launchpad 图标
│   │           └── appIcon2.png    # 菜单栏图标
│   └── CodexLimitMeter.dmg        # DMG 分发包（--dmg 构建时生成）
├── Sources/CodexLimitMeter/
│   ├── AppDelegate.swift          # App 入口（@main）、浮动窗口、菜单栏
│   ├── UsageTracker.swift        # App Server JSON-RPC 通信 + 数据管理
│   ├── ContentView.swift         # SwiftUI 界面
│   ├── AppIcon.png               # Dock 图标（SPM 资源 + build.sh 共用）
│   └── appIcon2.png              # 菜单栏图标（SPM 资源 + build.sh 共用）
├── build.sh                      # 一键编译脚本
├── Package.swift                 # SPM 包配置
├── .gitignore                    # Git 忽略规则
├── LICENSE                       # MIT 许可证
└── README.md                     # 本文件
```

## 开发指南

适合想要修改源码、调试功能或参与贡献的开发者。

### 前提条件

- macOS 13.0+
- **Xcode 15+**（从 App Store 安装，非仅 Command Line Tools）
- Swift 5.9+
- 已安装 Codex CLI 并完成登录

### 用 Xcode 打开项目

本项目使用 Swift Package Manager（SPM）管理，没有 `.xcodeproj` 文件，直接用 Xcode 打开 `Package.swift` 即可：

```bash
cd codex-limit-meter
open Package.swift
```

Xcode 会自动识别 SPM 项目并解析依赖。首次打开可能需要几秒钟等待索引完成。

### 编辑与调试

1. 在 Xcode 左侧导航器中展开 `Sources → CodexLimitMeter`，可以看到三个源文件：
   - `AppDelegate.swift` — App 入口（`@main`）、浮动窗口创建、菜单栏设置
   - `UsageTracker.swift` — Codex App Server JSON-RPC 通信、数据模型
   - `ContentView.swift` — SwiftUI 界面布局

2. 修改源码后，按 **⌘R** 运行调试。Xcode 会通过 SPM 直接编译运行，悬浮窗会出现在桌面上。

3. 底部控制台会输出日志（前缀 `[CodexLimitMeter]`），可用于调试 JSON-RPC 通信和数据更新。

> **注意**：Xcode 的 ⌘R 是通过 SPM 直接运行可执行文件，**不会**生成 `.app` 包，因此不会显示自定义图标、不会出现在 Dock 中（以命令行工具方式运行）。这是正常的调试行为，不影响功能验证。

### 构建可分发的 .app

调试完成后，使用项目自带的 `build.sh` 脚本生成完整的 `.app` 包：

```bash
cd codex-limit-meter
chmod +x build.sh
./build.sh
```

`build.sh` 会自动完成：
1. 编译 Swift 源码（release 配置）
2. 创建 `.app` 包目录结构
3. 写入 `Info.plist`（应用名、Bundle ID、Dock 显示等）
4. 复制 `AppIcon.png` 到 Resources
5. 执行 ad-hoc 代码签名（`codesign --force --deep --sign -`）

构建完成后，`dist/` 目录下会生成 `CodexLimitMeter.app`，可以直接双击运行或复制到 `/Applications`。

### 打包 DMG 分发包

如果要将应用发给其他用户使用，可以打包成 DMG 安装镜像：

```bash
./build.sh --dmg
```

会在 `dist/` 目录生成 `CodexLimitMeter.dmg`（约 1MB），包含：
- `CodexLimitMeter.app`
- `Applications` 文件夹快捷方式（拖拽安装）

**用户使用方式**：
1. 双击 `.dmg` 文件挂载
2. 将 `CodexLimitMeter.app` 拖到 `Applications` 文件夹
3. 在 Launchpad 或 Applications 中双击启动
4. 首次打开如被 Gatekeeper 拦截：前往 **系统设置 → 隐私与安全性** → 点击「仍要打开」（ad-hoc 签名，非 App Store 分发，仅需一次）

> **注意**：构建产物统一输出到 `dist/` 目录，已被 `.gitignore` 排除，不会上传到 GitHub。`dist/` 中的 `.app` 不会被 Spotlight 索引（因为不在 /Applications 中），不会导致 Launchpad 出现重复图标。

### Xcode 调试 vs build.sh 构建的区别

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

### 修改应用图标

1. 准备一张 1024×1024 的 PNG 图片，命名为 `AppIcon.png`
2. 替换 `Sources/CodexLimitMeter/AppIcon.png`
3. 运行 `./build.sh` 重新构建

图标会自动复制到 `.app` 包的 Resources 目录，并在 Dock 和 Launchpad 中显示。

### 修改菜单栏图标

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

### 清理缓存

如果 Xcode 出现奇怪的编译错误（例如文件已重命名但导航器仍显示旧文件），尝试：

```bash
# 清理 SPM 构建缓存
rm -rf .build .swiftpm

# 清理 Xcode DerivedData 缓存
rm -rf ~/Library/Developer/Xcode/DerivedData/codex-limit-meter-*

# 重新打开项目
open Package.swift
```

> **重要**：本项目的入口文件是 `AppDelegate.swift`（使用 `@main` 属性），**不是** `main.swift`。Swift Package Manager 中 `main.swift` 文件名会被视为顶层代码入口，与 `@main` 属性冲突会导致编译错误。如果需要重命名入口文件，请确保不要使用 `main.swift` 这个文件名。

### 修改刷新频率

在 `AppDelegate.swift` 的 `applicationDidFinishLaunching` 方法中修改 `timeInterval` 参数：

```swift
timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
    // 默认 30 秒，修改 30.0 为你想要的秒数
    self.tracker.refresh()
}
```

## 常见问题

**Q：首次打开提示「无法验证开发者」怎么办？**
A：前往 系统设置 → 隐私与安全性，点击「仍要打开」。这是因为应用使用 ad-hoc 签名，非 App Store 分发。之后不会再弹。

**Q：悬浮窗显示「更新失败」怎么办？**
A：请检查：
1. `codex` 命令是否可用（终端运行 `codex --version`）
2. Codex 是否已登录（终端运行 `codex` 看是否正常启动）
3. Codex 使用的是 ChatGPT 账号登录，而非 API Key 登录
4. 在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中允许 CodexLimitMeter

**Q：数据显示不对？**
A：本版本通过 Codex App Server 自动获取官方配额数据，与 Codex 桌面应用显示的完全一致。如果数据不一致，尝试点击刷新按钮，或重启应用。

**Q：App Server 会一直后台运行吗？**
A：悬浮窗退出时会自动终止 app-server 子进程，不会残留。

更多开发相关问题（修改刷新频率、自定义图标、清理缓存等）请参考上方[开发指南](#开发指南)章节。
