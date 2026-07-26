# Changelog

本文件只放「当次要发布的版本」的说明（不含历史）。发布前把新版本条目写在这里，供 `release-gh.sh` 作为 Release 说明使用；完整历史见 `CHANGELOG-ALL.md`。

## v0.4.1
- **根除冷启动首屏 / 翻页卡顿**：`IconCache.cachedIcon` 改为纯查询缓存——未命中返回 `nil`，绝不在主线程同步取图标 / 离屏缩放；未命中项改由 `AppIconView.task`（`await IconCache.shared.icon`）与 `FolderThumbnailView` 的异步 loader 后台补齐。图标预热 `prewarm` 优先级由 `.utility` 提升到 `.userInitiated`，并去掉 `loadApps` / `refreshApps` 外层冗余的 `Task.detached(.utility)` 包裹，缩短冷启动到图标就绪的窗口。代价：极端情况下（冷启动且预热未完成即翻页）极少数图标先显示占位、后淡入，优于「卡一下」。

## v0.4.0
- **扫描阶段跳过同步 Spotlight**：App 显示名先用 bundle 本地化名即时显示，系统中文名（Photos→「照片」等）在后台异步补查就绪后自动刷新。
- **图标预缩放后缓存**：首屏与翻页直接命中缓存、不在主线程做磁盘 IO。

## v0.3.0
- **导入原生 macOS 启动台布局**：设置页「布局」新增两个互斥胶囊开关——「使用原生 macOS 启动台布局」与「使用本项目默认布局」。开启「原生」即从系统启动台数据库（只读）导入顺序与文件夹结构，覆盖前自动备份当前布局，可随时还原。
- **导入绝不丢 App**：保序重流后，自动把本机已安装、但原生库未收录的 App（如后续安装、包裹型 App）追加到末页；导入后新安装的 App 由应用监听 `/Applications` 自动补全，无需再次手动导入。
- **失败不影响现有功能**：无数据库 / 解析异常 / 空结果都只返回错误、不写入布局，搜索、拖拽、翻页等完全不受影响；sqlite 以只读方式打开，对系统数据零风险。
- **App 体积零增长**：用系统自带 `import SQLite3`（动态链接 macOS 自带的 `libsqlite3.dylib`），不打包任何第三方库、也不把 8.5MB 原生数据库打进 App。

## v0.2.1
- **分发方案修正**：未签名的 `install.command` 被 Gatekeeper 拦截（弹窗只有"完成 / 移到废纸篓"，没有"仍要打开"按钮，无法放行），改为 DMG 内附 `README.txt`，三步安装：① 拖 AppLaunchpad.app 到 /Applications；② 终端执行 `sudo xattr -r -d com.apple.quarantine /Applications/AppLaunchpad.app`；③ 首次打开点"打开"。首次启动后到 系统设置 → 隐私与安全性 → 辅助功能 中开启 AppLaunchpad（全局快捷键 ⌥+Space 必需）
