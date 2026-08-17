# 发布说明

## 发布方式

Codex Limit Meter 是独立 macOS 应用，通过 GitHub Releases 分发 DMG，不使用服务器、Docker、数据库或运行时环境变量。

```bash
./build.sh --dmg
```

发布前确认：

- `TESTING.md` 中的编译、单元测试和本机功能验证通过。
- 使用 Developer ID Application 签名时启用 Hardened Runtime 并完成公证。
- Release 说明包含 macOS 最低版本、安装方式和权限/拦截提示。
- 不把 `.env`、证书、私钥或本地用户配置上传到 GitHub。

## 回滚

保留上一版 GitHub Release；新版本出现问题时，将产品入口恢复到上一版 Release，不删除历史安装包。

