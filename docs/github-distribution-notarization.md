# GitHub 分发与 macOS 安全认证流程

本文记录 Codex Limit Meter 从本地构建到 GitHub Release 分发的完整流程。

## 1. 为什么不走 Mac App Store

当前 App 通过 `Process` 启动用户电脑上的 Codex CLI / `codex app-server`，并读取用户的 Codex 配置目录。Mac App Store 的 App Sandbox 和自包含安装要求不适合当前架构，因此项目采用 GitHub Release 分发。

## 2. 本地安全检查

上传前检查以下内容：

```bash
git ls-files | rg -i '(\.env|\.pem|\.key|\.p12|\.p8|\.cer|\.csr|credentials|secret|password|token)'
rg -n -i '(BEGIN .*PRIVATE KEY|api[_-]?key|password|secret|token)' .
```

不要提交以下内容：

- 私钥、证书签名请求（CSR）和 `.p12` 文件
- Apple App 专用密码、API Key、Token
- `.env`、本机路径、调试产物和 `dist/` 构建目录

项目的 `.gitignore` 已忽略 `dist/`、`.build/`、Xcode 用户数据和系统文件。GitHub Actions 还会运行 Gitleaks。

## 3. 创建 Developer ID Application 证书

1. 在 Apple Developer 的 Certificates 页面选择 `Developer ID Application`。
2. 选择 `G2 Sub-CA`。
3. 在“钥匙串访问”中打开：
   `证书助理 → 从证书颁发机构请求证书…`
4. 请求类型选择“保存到磁盘”，生成 `.certSigningRequest`。
5. 上传 CSR，下载 `.cer` 文件。
6. 将证书添加到“登录”钥匙串，并确认它与 CSR 创建的私钥配对。

检查证书：

```bash
security find-identity -v -p codesigning
```

应看到类似：

```text
Developer ID Application: QIQI LI (4BHPD976HX)
```

## 4. 构建和签名

```bash
./build.sh --dmg
```

`build.sh` 的行为：

- 自动查找 `Developer ID Application` 证书
- 使用 Hardened Runtime 签名
- 写入可信时间戳
- 清理 App 内构建来源扩展属性
- 创建拖拽安装用 DMG
- 如果没有 Developer ID 证书，则退回 ad-hoc 签名，仅适合本地测试

签名检查：

```bash
codesign --verify --deep --strict dist/CodexLimitMeter.app
codesign -dv --verbose=4 dist/CodexLimitMeter.app 2>&1
```

## 5. Apple notarization

先在 Apple 账户中生成 App 专用密码。它不是 Apple 主密码，也不要写入代码或 Git。

将凭据保存到钥匙串：

```bash
xcrun notarytool store-credentials codex-limit-meter \
  --apple-id "你的 Apple Developer 邮箱" \
  --team-id "4BHPD976HX"
```

凭据保存后运行：

```bash
./notarize.sh
```

脚本会提交 DMG、等待 Apple 审核、装订 notarization ticket，并执行 `stapler validate`。

## 6. 发布 GitHub Release

```bash
git add README.md Sources build.sh AppStore docs project.yml notarize.sh
git commit -m "Prepare notarized GitHub distribution"
git push origin main
gh release create v1.1.3 dist/CodexLimitMeter.dmg \
  --title "v1.1.3" \
  --notes "Developer ID signed and notarized GitHub distribution."
```

## 7. 发布后验证

先从 GitHub Release 下载 DMG，再验证校验值：

```bash
shasum -a 256 CodexLimitMeter.dmg
hdiutil attach -nobrowse -readonly CodexLimitMeter.dmg
spctl -a -vvv --type execute "/Volumes/Codex Limit Meter/CodexLimitMeter.app"
codesign --verify --deep --strict "/Volumes/Codex Limit Meter/CodexLimitMeter.app"
hdiutil detach "/Volumes/Codex Limit Meter"
```

期望看到：

```text
source=Notarized Developer ID
origin=Developer ID Application: QIQI LI (4BHPD976HX)
```

用户安装方式是：打开 DMG，将 App 拖入 `Applications`，再从“应用程序”文件夹启动。通过公证后通常不需要执行 `xattr` 或关闭 Gatekeeper。

## 8. 本次完成记录

- Release：`v1.1.3`
- Git 提交：`ba4b233`
- Developer ID Team ID：`4BHPD976HX`
- 最终 DMG 已完成签名、公证和远程下载验证

不要在文档、Issue、Release 或 Git 历史中记录 App 专用密码、私钥、CSR 内容或钥匙串导出文件。
