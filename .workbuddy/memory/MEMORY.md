# AppLaunchpad 长期记忆

## 项目关键约定 / 坑

- **Swift 6 成员初始化器不包含带默认值的存储属性。** 本项目（Xcode 26.2 / Swift 6 / SWIFT_STRICT_CONCURRENCY: complete）下，结构体若给某个存储属性写了默认值（如 `let x: Int = 0`），其自动 memberwise initializer 中**不会**暴露该参数。调用方若传这个参数会报 `extra argument 'x' in call`。
  - 复现：`struct S { let a: Int; let b: Int = 0 }; S(a:1, b:2)` → 编译失败。
  - 解决：要么去掉默认值（变必填），要么显式写 `init(...)`。
  - 曾因此误判为 ModuleCache 缓存过期，实际根因在此。改代码即可，清缓存无效。

- **构建命令（稳定签名，重要！）**：
  `xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad -configuration Debug clean build`
  **不要再带 `CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES`** —— 那是 ad-hoc 签名，会让辅助功能等 TCC 权限每次重编译都失效。
  `project.yml` 已固化 `CODE_SIGN_STYLE: Manual` + `CODE_SIGN_IDENTITY: "Apple Development"` + `DEVELOPMENT_TEAM: 2VU69Q9CGK`（用本机已有的 Apple Development 证书，指纹 `F4171D2397EFE92485DB3B20C38456DDB0DB0A62`）。
  项目用 xcodegen 从 `project.yml` 生成 xcodeproj（改 project.yml 后需 `xcodegen generate`）。

- **TCC / 签名坑**：ad-hoc 签名的 designated requirement 含二进制哈希，重编译即变 → 辅助功能等权限失效。Apple Development 证书签名只绑 identifier + 证书 CN，稳定。若辅助功能"已开但 App 显示未授权"，多半是旧 ad-hoc 授权记录残留，执行 `tccutil reset Accessibility com.applaunchpad.app` 后用新签名 App 重新授权一次即可（之后持久）。

- **NSEvent.Phase 是 OptionSet（非 Optional）**：判断"无惯性阶段"用 `event.momentumPhase.isEmpty`，不要用 `== .none`（会被解析成 Optional.none，恒 false）。

- **退出行为约定（UX）**：App 是后台常驻工具（状态栏图标 + 全局快捷键 + 全屏 NSPanel 启动台）。**设置窗口点红叉只关窗、不退出 App**（未实现 `applicationShouldTerminateAfterLastWindowClosed`，系统默认 false）。退出仅通过 `⌘Q` 或状态栏菜单「退出 AppLaunchpad」。左键点 Dock 由 `applicationShouldHandleReopen → toggle()` 呼出/收起启动台（已落地）。后续不要"顺手"给设置窗加退出逻辑，那是预期设计。

## 架构速记
- 混合 AppKit + SwiftUI：NSPanel 全屏浮层（LaunchpadWindowController），@Observable ViewModel（LaunchpadViewModel，@MainActor）。
- 拖拽进度环状态在 DragState.folderProgress；文件夹合并触发条件是 folderTargetID != nil。
- 全局热键在 AppDelegate.setupGlobalHotkey 用 NSEvent.addGlobalMonitorForEvents 监听 keyCode + modifier。

## 设置窗口架构（当前代码状态，已编译验证）

- **使用 `Window("设置", id: "settings")` 场景**（`AppLaunchpadApp.swift`）承载设置窗口。该窗口使用 `NavigationSplitView` + `.listStyle(.sidebar)`，左侧为系统磨砂玻璃 sidebar，右侧 detail 标题栏自动生成系统 sidebar toggle 按钮，窗口标题为"设置"。
- **入口位置**：App 菜单「设置… / ⌘,」、状态栏菜单、Dock 右键菜单（各含"打开启动台"+"设置…"）统一调 `AppDelegate.openSettings()` → `NSApp.sendAction(Selector(("showWindow:")), to: nil, from: nil)`。
- 打开设置时，`AppDelegate` 的 `NSWindow.didBecomeKeyNotification` 观察者会把启动台全屏面板降到普通层级；设置窗口关闭后 `NSWindow.willCloseNotification` 恢复面板层级。
- 不要尝试用 `AppDelegate` 手动创建 `NSWindow + NSHostingController` 来承载 `NavigationSplitView`：SwiftUI 在这种窗口里不会为 `NavigationSplitView` 生成系统工具栏，导致 sidebar toggle 按钮缺失。
- ⚠️ 备注：`Settings { }` 场景虽然可用 `showSettingsWindow:` 从 AppKit 可靠打开，但会呈现系统 Settings 窗口风格（标题随当前分类变化等），与当前项目采用的普通 `Window` 场景视觉不一致，因此当前代码仍使用 `Window("设置", id: "settings")` 场景。

- 默认采用"自动撑满"策略：由 `LaunchpadView.computeIconSize(contentSize:columns:rows:)` 根据实际内容区域尺寸、行列数、间距/边距计算每个 cell，再预留标签高度后让图标尽可能填满。
- `iconSizeOverride` 语义为"图标最大尺寸"：0 表示自动撑满，非 0 时作为上限。若用户想要限制大小，调此参数即可；若嫌空白太多，设为 0 即可让图标自动变大。
- 行、列、间距、边距全部进入 `UserPreferences` 并在 `SettingsView` 外观面板用滑块实时调整；由于 `UserPreferences` 是 `@Observable`，设置面板和启动台界面会同步刷新。
- 图标视图（AppIconView / FolderThumbnailView）字体最高限制 16pt，防止图标放大后文字比例失衡。
