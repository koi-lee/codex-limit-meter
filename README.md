# Codex Meter

macOS 桌宠与菜单栏工具：查看 Codex 个人额度，关注公开重置消息。

[English](README_EN.md) · [额度星盘网站](https://www.starshoreai.com/quota-orbit/)

## 当前发布范围

这是新版客户端的 **AGPL-3.0 源码发布**，包含 Swift 源码、测试和本地桌宠资源。网站、服务器、浏览器扩展、开发者配置和凭据不在此仓库中。旧 Codex Limit Meter v1.1.3 及更早标签保留原 MIT 许可，已停止维护，界面与新版不同。

本次未发布已签名或公证的安装包，也不代表 Mac App Store 已上架。

## 本地构建

需要 macOS 13+、Xcode Command Line Tools 和 Swift 5.9 或更高版本。此次在 Apple Silicon Mac 验证；Intel 尚未实机验证。

```sh
swift test --disable-sandbox
./build-local.sh
open "dist/Codex Meter Open Source.app"
```

构建脚本创建独立 Bundle ID 的本地 App，使用 ad-hoc 签名，不需要开发者证书。它不会安装或覆盖已有 App；重复构建请使用新的 `CODEX_BUILD_DIR`。公开源码版通过本机 Codex CLI 读取额度，需要自行安装并登录 Codex；不包含商店版捆绑的 CLI helper。首次打开按使用指南操作；通知由用户主动开启。

## 能做什么

- 桌宠与菜单栏展示额度、重置时间和本机额度变化。
- 星盘中查看额度与公开消息，可切换角色及演示数据。
- App 运行并联网时检查公开消息；消息来自公开源或第三方转录，需核对原帖，不能代表每个账号已到账。

账号凭据与使用数据留在本机；不上传至此仓库。额度可用性取决于 Codex 实际返回内容。无数据、失败或过期时不应视为重置完成。

## 许可

本次及后续客户端项目代码采用 GNU Affero General Public License v3.0，见 [LICENSE](LICENSE)。既有 MIT 授权仍然有效，原声明保留于 [LICENSE-MIT-legacy](LICENSE-MIT-legacy)。第三方组件保留自己的许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。项目名称与标识不表示 OpenAI 官方出品或背书。

## 验证边界

源码测试和本地构建已验证；真实通知横幅、不同系统/硬件及首次账号连接仍取决于使用环境。源码发布不替代签名、公证或商店审核。
