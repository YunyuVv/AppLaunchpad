# AppLaunchpad 长期记忆

## 构建/签名/TCC（红线）
- 构建命令（本环境可用，已验证 BUILD SUCCEEDED）：
  ```bash
  defaults write com.apple.dt.Xcode DisableBuildSystemSandbox -bool YES
  xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad -configuration Debug clean build OTHER_SWIFT_FLAGS=-disable-sandbox 2>&1 | tail -40
  defaults delete com.apple.dt.Xcode DisableBuildSystemSandbox 2>/dev/null || true
  ```
  原因：本 agent 容器禁止 `sandbox_apply`（任何进程都报 `Operation not permitted`）。需两层关沙箱：① `DisableBuildSystemSandbox` 关 xcodebuild 自身 wrapper；② `OTHER_SWIFT_FLAGS=-disable-sandbox`（= swiftc `-disable-sandbox`）关宏插件宿主 `swift-plugin-server` 的沙箱——否则 `@Observable` 等外部宏报 `malformed response`。`SWIFT_USE_SANDBOX=NO` 是**错误**开关，无效。
- 勿 ad-hoc 签名（令 TCC 失效）。`project.yml` 固化 Manual+Apple Development+TEAM `2VU69Q9CGK`。改 project.yml/新增/移动 .swift 后必 `xcodegen generate`。`project.yml` 已含 `schemes: AppLaunchpad:` 段（build/run/test/profile/analyze/archive），`xcodegen generate` 会生成共享 scheme `xcshareddata/xcschemes/AppLaunchpad.xcscheme`，命令行 `-scheme` 可用；早期版本未加此段时 xcodegen 不产出 scheme、依赖 Xcode 自动建。
- **工作流红线（用户 2026-07-25）**：改完代码必须编译确认无 error；新增/移动 .swift 必 xcodegen generate，否则 `Cannot find 'Xxx' in scope`。
- macOS 26 SDK 更名：`recycleURLs`→`recycle`；`showWindow:` 声明在 NSWindowController → `#selector(NSWindowController.showWindow(_:))`。
- TCC：Apple Development 证书绑 identifier+CN 稳定。清残留：`tccutil reset Accessibility com.biliww.applaunchpad`。改 bundle id 后辅助功能授权失效，需重授权 + ⌘Q 重启；`tccutil reset` 报 -10814 = TCC 无此记录（可忽略）。⚠️ 本环境 sandbox 限制 `tccutil` 跑不了，须用户本机跑。

## 编码坑
- Swift 6 成员初始化器不含带默认值的存储属性；`NSEvent.Phase` 是 OptionSet 用 `.isEmpty` 判无惯性。
- App 中文名：手写按 `Locale.preferredLanguages`+实际 .lproj 匹配（地区码取 `parts.last`），禁用 `Bundle.localizedString`/`localizedInfoDictionary`（en 开发语言+无 CFBundleLocalizations 时错选 en）。见 `AppScanner.localizedDisplayName`。
- 键盘 monitor 焦点门控：`isTextInputFirstResponder()` 放行必须同时要求 `!searchText.isEmpty`（聚焦空+可打印字符 return event 交 IME；聚焦有内容全交还；否则字母搜索/导航）。方向键/ESC 落入导航保翻页。
- 搜索框 `@FocusState` 上提父视图，`onChange(isVisible)` 中 `false; async true` 强制聚焦；否则 IME 分裂 + 焦点残留吞箭头。
- macOS 26 设置窗口 Toggle 视觉小：统一 `.toggleStyle(.switch).controlSize(.large)`；行内「字段-值」用 `LabeledContent("键") { 值 }` 替代 HStack+Spacer。

## 架构（同 target 不拆 framework）
- `LaunchpadData`（@Observable 共享状态）+ 4 控制器：`LayoutService`(几何/布局/扫描)、`SearchController`、`DragController`(边缘翻页 Timer.common)、`NavigationController`。根 VM 组合根+薄壳转发；依赖单向 View→根VM→控制器。
- 窗口：`LaunchpadWindowController` 管理 borderless `KeyablePanel`(NSPanel, canBecomeKey/Main)，`show()` 用 `UserPreferences.shared.targetScreen` 定位到指定显示器。设置窗 `Window("设置",id:"settings")`+NavigationSplitView；经 AppDelegate.openSettings→settingsOpener→openWindow(id:)（勿 showWindow:）。
- 显示器选择：`UserPreferences.DisplayTarget`(primary/mouse/specific(CGDirectDisplayID)) → `targetScreen` 解析 NSScreen；`DisplayPane` 枚举 `NSScreen.screens` 列出可选，单显时仅显示"主显示器"不可选。

## 已落地功能（摘要）
- 文件夹功能 2026-07-25 已彻底移除（3 文件+folders 字段强制空）。
- 背景：磨砂（`.behindWindow` ScreenBlurView）/ 液态玻璃（`NSGlassEffectView`）二选一，**默认玻璃**（backgroundStyle 默认 1）。文件夹面板 `FolderBackdropView` 跟随：玻璃 NSGlassEffectView、磨砂 `.withinWindow` 毛玻璃。
- 右键菜单：打开/在访达中显示/删除（二次确认 `.confirmationDialog`）。删除用 `NSWorkspace.shared.recycle` 保留 Put Back 元数据（禁用 FileManager.trashItem）。
- 拖拽 clamp 用 items.count，落点几何化（GridGeometry 固定几何），make-way 常驻。

## 数据/其他
- 布局：`LayoutStore`(actor)+JSON `~/Library/Application Support/AppLaunchpad/layout.json`（`folders` 字段运行时恒空）。偏好 `UserPreferences`→UserDefaults.standard（按 bundle id 分域，改 id 历史设置重置）。
- 退出：后台常驻（状态栏+全局热键+NSPanel）；设置窗红叉只关窗不退出；退出仅 ⌘Q/状态栏；Dock 左键→toggle。
- bundle id：`com.applaunchpad.app` → `com.biliww.applaunchpad`（project.yml: bundleIdPrefix=com.biliww + PRODUCT_BUNDLE_IDENTIFIER=com.biliww.applaunchpad）。
