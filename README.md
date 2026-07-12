# Codex Limit Meter

> Mac 桌面 Codex 额度悬浮窗 — 实时监控 5 小时窗口和周用量

一个常驻 Mac 桌面的悬浮窗，自动获取 Codex 官方配额数据，支持拖拽、颜色预警、套餐显示。

![Codex Limit Meter 悬浮窗截图](docs/screenshot.png)

## 系统要求

- macOS 13.0+（Ventura 及以上）
- 已安装 Codex CLI 并完成登录（`codex` 命令可用）
- Codex 使用 ChatGPT 账号登录（非 API Key 登录）

## 下载使用

### 方式一：下载 DMG 安装（推荐）

1. 前往 [Releases](../../releases) 下载最新的 `CodexLimitMeter.dmg`
2. 双击挂载，将 `CodexLimitMeter.app` 拖到 `Applications` 文件夹
3. 在 Launchpad 或 Applications 中双击启动
4. 首次打开如被 Gatekeeper 拦截，二选一：
   - **终端命令**（推荐）：`xattr -cr /Applications/CodexLimitMeter.app`
   - **系统设置**：前往 **系统设置 → 隐私与安全性** → 点击「仍要打开」

   两种方式均仅需操作一次。

### 方式二：从源码编译

```bash
git clone https://github.com/koi-lee/codex-limit-meter.git
cd codex-limit-meter
chmod +x build.sh
./build.sh          # 编译，产物在 dist/
open dist/CodexLimitMeter.app
```

如需打包 DMG 分发给他人：

```bash
./build.sh --dmg    # 生成 dist/CodexLimitMeter.dmg
```

## 使用方式

应用启动后：

1. Dock 和菜单栏出现应用图标
2. 深色圆角悬浮窗出现在桌面，可拖拽到任意位置
3. 启动后 2-3 秒内自动连接 Codex App Server 并获取数据
4. 底部显示 **已同步** 表示连接成功

| 操作 | 说明 |
|------|------|
| 拖拽窗口 | 点击深色背景区域拖拽到任意位置 |
| 刷新按钮 | 右上角 ↻ 立即刷新 |
| 菜单栏图标 | 显示窗口 / 刷新 / 退出 |
| ⌘Q | 快捷键退出 |

进度条颜色基于**剩余比例**：绿色（>40% 正常）/ 橙色（20-40% 接近上限）/ 红色（<20% 即将耗尽）。

## 常见问题

**Q：首次打开提示「无法验证开发者」？**
A：应用使用 ad-hoc 签名，非 App Store 分发。两种解决方式（任选其一，仅需一次）：
- 终端运行：`xattr -cr /Applications/CodexLimitMeter.app`
- 或前往 系统设置 → 隐私与安全性，点击「仍要打开」

**Q：悬浮窗显示「更新失败」？**
A：请检查：① `codex` 命令是否可用 ② Codex 是否已登录 ③ 是否使用 ChatGPT 账号登录（非 API Key）。

**Q：App Server 会一直后台运行吗？**
A：悬浮窗退出时会自动终止 app-server 子进程，不会残留。

---

想要修改源码、调试功能或参与贡献？请阅读 [开发指南](DEVELOPMENT.md)。
