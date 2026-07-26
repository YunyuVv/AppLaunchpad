# AppLaunchpad 长期记忆

## 构建/签名/TCC（红线）
- 构建命令（本环境可用，已验证 BUILD SUCCEEDED）：
  ```bash
  defaults write com.apple.dt.Xcode DisableBuildSystemSandbox -bool YES
  xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad -configuration Debug clean build OTHER_SWIFT_FLAGS=-disable-sandbox 2>&1 | tail -40
  defaults delete com.apple.dt.Xcode DisableBuildSystemSandbox 2>/dev/null || true
  ```
  原因：本 agent 容器禁 `sandbox_apply`。需两层关沙箱：①`DisableBuildSystemSandbox` 关 xcodebuild wrapper；②`OTHER_SWIFT_FLAGS=-disable-sandbox`（=swiftc `-disable-sandbox`）关宏插件宿主 `swift-plugin-server`。`SWIFT_USE_SANDBOX=NO` 无效。
- 勿 ad-hoc 签名（令 TCC 失效）。`project.yml` 固化 Manual+Apple Development+TEAM `2VU69Q9CGK`。改 project.yml/新增/移动 .swift 后必 `xcodegen generate`。`project.yml` 已含 `schemes:` 段，`xcodegen generate` 产共享 scheme。
- **工作流红线**：改完代码必须编译确认无 error；新增/移动 .swift 必 xcodegen generate（否则 `Cannot find 'Xxx' in scope`）。
- macOS 26 SDK 更名：`recycleURLs`→`recycle`；`showWindow:` 声明在 NSWindowController。
- TCC：清残留 `tccutil reset Accessibility com.biliww.applaunchpad`；本环境 sandbox 跑不了须用户本机跑。App 启动后实际调用辅助功能 API 即自动进设置页列表，**勿写 `AXIsProcessTrustedWithOptions(prompt:true)` 弹多余框**；设置页"打开辅助功能"按钮直接 `NSWorkspace.shared.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")`（InteractionPane）。

## 编码坑
- Swift 6 成员初始化器不含带默认值存储属性；`NSEvent.Phase` OptionSet 用 `.isEmpty` 判无惯性。
- App 中文名：`AppScanner.localizedDisplayName` 手写按 `Locale.preferredLanguages`+实际 .lproj 匹配（禁 `Bundle.localizedString`）。第一方 App（Photos/Music）自身 lproj 为空，需 Spotlight 公开 API `NSMetadataItem(url:).value(forAttribute: NSMetadataItemDisplayNameKey)` 兜底（Photos→照片），结果按 path memo。⚠️ macOS 26 私有 `LSCopyApplicationName` 符号已移除，禁用。
- 键盘 monitor：`isTextInputFirstResponder()` 放行须同时 `!searchText.isEmpty`；方向键/ESC 落导航。搜索框 `@FocusState` 上提父视图。macOS 26 设置 Toggle 统一 `.toggleStyle(.switch).controlSize(.large)`；行内字段用 `LabeledContent`。
- 包裹型 app（外层无 Info.plist，内层 `Wrapper/*.app`）：`AppScanner.resolveBundle` 递归解析返回实际 `plistURL`，`launchURL` 用最外层；`isMASApp` 查 `Contents/_MASReceipt` 与顶层。

## 架构（同 target 不拆 framework）
- `LaunchpadData`(@Observable 共享状态)+4 控制器：`LayoutService`(几何/布局/扫描)、`SearchController`、`DragController`(边缘翻页)、`NavigationController`。根 VM 组合根+薄壳转发；依赖单向 View→根VM→控制器。
- 窗口：`LaunchpadWindowController` 管 borderless `KeyablePanel`；`show()` 用 `UserPreferences.shared.targetScreen` 定位。`LaunchpadData` 在主线（写布局须回 @MainActor）。
- 显示器选择：`UserPreferences.DisplayTarget`(primary/mouse/specific)→`targetScreen`。

## 已落地功能（摘要）
- 文件夹：`FolderInfo`+`FolderController`+`FolderThumbnailView`+`FolderExpandedView`(改名)+`DragController` 拖入拖出。`layout.json` 的 `folders` 运行期非空。
- 背景：磨砂/液态玻璃二选一，默认玻璃。
- 右键菜单：打开/在访达显示/删除（`NSWorkspace.recycle` 保 Put Back）。
- 搜索框：液态玻璃 `GlassHostingView`；图标/文字语义色。

## 数据/其他
- 布局：`LayoutStore`(actor)+JSON `~/Library/Application Support/AppLaunchpad/layout.json`。`LayoutData(pages:[[LayoutItem]], folders:[UUID:FolderInfo], version:1)`，`version` 是数据格式版本非 app 版本。
- 版本号真源=`AppLaunchpad/AppLaunchpad/Info.plist`(CFBundleShortVersionString+CFBundleVersion)。CI 产物 DMG 恒名 `AppLaunchpad.dmg`，固定链接 `.../releases/latest/download/AppLaunchpad.dmg`。发版：改 Info.plist→`./scripts/release/release-gh.sh <ver>`。流程见 `scripts/release/RELEASE.md`。
- bundle id=`com.biliww.applaunchpad`。
- 分发：用户选**开源发布(GPL v3)**，可发未签名包（`xattr -r -d com.apple.quarantine`）；`project.yml` 当前 Apple Development 签名，开源分发前须改未签名。

## 原生 Launchpad 布局导入（Tahoe 可行）
- 路径 `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`，legacy 三表 apps/groups/items，type:1=root 2=page 3=folder 4=app。macOS 26 实测存在、含中文标题。
- 用系统 `import SQLite3`（动态链 `/usr/lib/libsqlite3.dylib`，app 体积零增长），运行时只读；db 文件(8.5MB)不打包。
- 映射：`Cell`(app/folder) 序列按本机 itemsPerPage 重流→`LayoutData`；folder→`FolderInfo`；未安装 bundleID 跳过。导入前 `layout.backup.json` 备份。参考 `references/LaunchNext/NativeLaunchpadImporter.swift`。
- **落地功能（2026-07-26）**：`NativeLaunchpadImporter.swift` + `LayoutService.importNativeLayout()`/`restoreDefaultLayout()` + `LayoutStore.backup()` + 设置页「布局」Section（Toggle 导入原生布局 + 恢复默认布局 + 结果文案）。失败只报错误、绝不写 `data.layout`，保现有功能。设计稿 `docs/技术实现/07-导入原生启动台布局设计.md`。

## 权威文档
- 功能/进度：`docs/产品文档.md`、`docs/待办事项.md`；坑/红线/架构：`docs/开发指南.md`；分发：`docs/分发流程.md`。改代码前以**当前代码事实**为准。
