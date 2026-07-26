# Changelog

本文件只放「当次要发布的版本」的说明（不含历史）。发布前把新版本条目写在这里，供 `release-gh.sh` 作为 Release 说明使用；完整历史见 `CHANGELOG-ALL.md`。

## v0.3.0
- **导入原生 macOS 启动台布局**：设置页「布局」新增两个互斥胶囊开关——「使用原生 macOS 启动台布局」与「使用本项目默认布局」。开启「原生」即从系统启动台数据库（只读）导入顺序与文件夹结构，覆盖前自动备份当前布局，可随时还原。
- **导入绝不丢 App**：保序重流后，自动把本机已安装、但原生库未收录的 App（如后续安装、包裹型 App）追加到末页；导入后新安装的 App 由应用监听 `/Applications` 自动补全，无需再次手动导入。
- **失败不影响现有功能**：无数据库 / 解析异常 / 空结果都只返回错误、不写入布局，搜索、拖拽、翻页等完全不受影响；sqlite 以只读方式打开，对系统数据零风险。
- **App 体积零增长**：用系统自带 `import SQLite3`（动态链接 macOS 自带的 `libsqlite3.dylib`），不打包任何第三方库、也不把 8.5MB 原生数据库打进 App。

## v0.2.1
- **分发方案修正**：未签名的 `install.command` 被 Gatekeeper 拦截（弹窗只有"完成 / 移到废纸篓"，没有"仍要打开"按钮，无法放行），改为 DMG 内附 `README.txt`，三步安装：① 拖 AppLaunchpad.app 到 /Applications；② 终端执行 `sudo xattr -r -d com.apple.quarantine /Applications/AppLaunchpad.app`；③ 首次打开点"打开"。首次启动后到 系统设置 → 隐私与安全性 → 辅助功能 中开启 AppLaunchpad（全局快捷键 ⌥+Space 必需）
