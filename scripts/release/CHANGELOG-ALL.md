# Changelog（完整历史）

本文件记录所有已发布版本的累计变更。每个新版本发布时，把对应条目追加到本文件顶部（最新在上）。

## v0.2.1
- **分发方案修正**：未签名的 `install.command` 被 Gatekeeper 拦截（弹窗只有"完成 / 移到废纸篓"，没有"仍要打开"按钮，无法放行），改为 DMG 内附 `README.txt`，三步安装：① 拖 AppLaunchpad.app 到 /Applications；② 终端执行 `sudo xattr -r -d com.apple.quarantine /Applications/AppLaunchpad.app`；③ 首次打开点"打开"。首次启动后到 系统设置 → 隐私与安全性 → 辅助功能 中开启 AppLaunchpad（全局快捷键 ⌥+Space 必需）

## v0.2.0
- **搜索结果分页**：仿系统启动台，搜索结果超过一页时可翻页；支持触控板/鼠标滚轮滑动、方向键（←→跨列、↑↓跨行、到页边界自动翻页）、底部圆点导航，解决之前 app 显示不全、翻不到的问题
- **一键安装脚本 `install.command`**：DMG 内新增安装脚本，挂载后双击即可自动安装到 `/Applications/AppLaunchpad.app` 并去除隔离属性（需输入管理员密码）；装完按提示首次启动右键「仍要打开」即可（未签名 app 的必经步骤）
- **设置窗口入口优化**：Dock 图标、状态栏菜单、⌘, 三种方式均可稳定打开并前置设置窗口
- **固定下载地址**：`https://github.com/YunyuVv/AppLaunchpad/releases/latest/download/AppLaunchpad.dmg` 永远指向最新版，发版后无需更换链接

## v0.1.0
- 搜索结果分页（仿系统启动台，解决超过一页无法翻页 / app 显示不全）
- GitHub Actions 未签名 DMG 自动打包工作流
- 开源发布（GPL v3）
