# Quota Orbit 1.3.0-beta.1

- Bundle: com.starshoreai.codexmeter；version 1.3.0 / build 60；arm64 / macOS 13+。
- 包含最新桌宠、额度读取恢复，以及预告/完成/重置卡分类通知与详情跳转修复。
- 非商店构建，个人额度依赖本机已安装并登录的Codex CLI；不捆绑helper。
- 回归：83项Swift Testing与2项XCTest通过；签名公证和运行验收结果记录在Release说明。
- 从本标签运行build-release.sh生成app；Apple接受后staple app，再封装DMG并单独公证、staple及Gatekeeper核验。
- 公开试用不是App Store上架；不同硬件/系统和真实首次账号连接需继续收集反馈。
