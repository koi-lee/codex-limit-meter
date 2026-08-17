# 测试指南

## 编译与单元测试

```bash
swift test
./build.sh
```

## 本机功能验证

1. 确认 `codex` 命令可用并已使用 ChatGPT 账号登录。
2. 打开 `dist/CodexLimitMeter.app`。
3. 验证配额读取、30 秒刷新、实时更新、窗口拖拽、菜单栏操作和退出清理。
4. 当服务端只返回周额度时，确认界面不会虚构短期额度。

## 发布前检查

```bash
./build.sh --dmg
codesign --verify --deep --strict dist/CodexLimitMeter.app
```

没有 Developer ID 证书时，构建结果仅适合本地测试；不能把 ad-hoc 签名当作正式公证发布验证。

