# Mac App Store 上架准备

当前状态：**尚未达到可提交状态**。

## 已完成

- Apple Distribution 证书已安装：团队标识 `4BHPD976HX`
- 浮窗启动和尺寸变化时均居中
- 当前源码可通过 Swift 测试和代码签名校验

## 当前阻塞项

1. 本机已安装 Xcode 26.6（Build 17F113），并已生成 Xcode 工程；当前系统 `xcode-select` 仍指向 Command Line Tools，命令行需使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
2. 本机当前未发现可用的 Mac App Store provisioning profile；还需要在 Xcode 登录开发者团队并完成 Bundle ID / App Store Connect 配置。
3. 当前 App 会启动用户电脑外部的 `codex app-server`，并读取 `~/.codex`。Mac App Store 要求 App Sandbox 和自包含安装包，这条路径需要重新设计，不能只添加一个签名证书。
4. Xcode application target、App Sandbox entitlements 和 archive 所需工程骨架已加入；尚未完成可提交的 archive/export。

## 下一步顺序

1. 在 Xcode 中登录同一开发者团队，注册 `com.codex.limit-meter` Bundle ID，并生成 Mac App Store provisioning profile。
2. 重新设计 Codex 数据来源：将需要的 helper 放入 App bundle，或改为受沙盒允许的 IPC/服务方案；不能依赖任意外部 `codex` 路径和宿主目录。
3. 在 App Store Connect 创建应用记录，配置产品名称、隐私和出口合规信息。
4. 通过 archive、validation、upload 后再提交审核。

如果保持当前架构，推荐走 Developer ID + Hardened Runtime + notarization 的 GitHub/官网分发路线，而不是 Mac App Store。
