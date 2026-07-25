# Changelog

本文件只放「当次要发布的版本」的说明（不含历史）。发布前把新版本条目写在这里，供 `release-gh.sh` 作为 Release 说明使用；完整历史见 `CHANGELOG-ALL.md`。

## v0.2.1
- **分发方案修正**：未签名的 `install.command` 被 Gatekeeper 拦截（弹窗只有"完成 / 移到废纸篓"，没有"仍要打开"按钮，无法放行），改为 DMG 内附 `README.txt`，三步安装：① 拖 AppLaunchpad.app 到 /Applications；② 终端执行 `sudo xattr -r -d com.apple.quarantine /Applications/AppLaunchpad.app`；③ 首次打开点"打开"。首次启动后到 系统设置 → 隐私与安全性 → 辅助功能 中开启 AppLaunchpad（全局快捷键 ⌥+Space 必需）
