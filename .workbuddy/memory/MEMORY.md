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

- **退出行为约定（UX）**：App 是后台常驻工具（状态栏图标 + 全局快捷键 + 全屏 NSPanel 启动台）。**设置窗口点红叉只关窗、不退出 App**。
  - 关键坑：`AppLaunchpadApp.swift` 的 `body` 只有唯一 `Window("设置", id: "settings")` 场景 → SwiftUI 把它当主窗口，①启动会自动打开设置窗；②关掉它按"单一主窗口"逻辑直接退出。
  - 修复（已落地，BUILD SUCCEEDED）：该 Scene 加 `.defaultLaunchBehavior(.suppressed)`（启动不自动开设置窗，仅 ⌘, / 菜单按需开）；`AppDelegate` 显式实现 `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`（关设置窗不退出）。**默认 false 在单一 `Window(id:)` 场景下拦不住退出，须显式写。**
  - 退出仅通过 `⌘Q` 或状态栏菜单「退出 AppLaunchpad」。左键点 Dock 由 `applicationShouldHandleReopen → toggle()` 呼出/收起启动台（已落地）。

## 架构速记
- 混合 AppKit + SwiftUI：NSPanel 全屏浮层（LaunchpadWindowController），@Observable ViewModel（LaunchpadViewModel，@MainActor）。
- 拖拽进度环状态在 DragState.folderProgress；文件夹合并触发条件是 folderTargetID != nil。
- 全局热键在 AppDelegate.setupGlobalHotkey 用 NSEvent.addGlobalMonitorForEvents 监听 keyCode + modifier。

## 设置窗口架构（当前代码状态，已编译验证）

- **使用 `Window("设置", id: "settings")` 场景**（`AppLaunchpadApp.swift`）承载设置窗口。该窗口使用 `NavigationSplitView` + `.listStyle(.sidebar)`，左侧为系统磨砂玻璃 sidebar，右侧 detail 标题栏自动生成系统 sidebar toggle 按钮，窗口标题为"设置"。
- **入口位置**：App 菜单「设置… / ⌘,」、状态栏菜单、Dock 右键菜单（各含"打开启动台"+"设置…"）统一调 `AppDelegate.openSettings()` → `settingsOpener` 闭包 → SwiftUI 环境 `openWindow(id: "settings")`。
  - ⚠️ **打开 `Window(id:)` 场景必须用 `openWindow(id:)`，绝不能用 `showWindow:` 选择器**（`showWindow:` 依赖响应者链，对 SwiftUI 场景不可靠，Dock 菜单等上下文下直接失效）。桥接方式：`AppLaunchpadApp.body` 里 `appDelegate.setSettingsOpener { self.openWindow(id: "settings") }` 把环境动作注入 AppDelegate。
- 打开设置时，`AppDelegate` 的 `NSWindow.didBecomeKeyNotification` 观察者会把启动台全屏面板降到普通层级；设置窗口关闭后 `NSWindow.willCloseNotification` 恢复面板层级。
- 不要尝试用 `AppDelegate` 手动创建 `NSWindow + NSHostingController` 来承载 `NavigationSplitView`：SwiftUI 在这种窗口里不会为 `NavigationSplitView` 生成系统工具栏，导致 sidebar toggle 按钮缺失。
- ⚠️ 备注：`Settings { }` 场景虽然可用 `showSettingsWindow:` 从 AppKit 可靠打开，但会呈现系统 Settings 窗口风格（标题随当前分类变化等），与当前项目采用的普通 `Window` 场景视觉不一致，因此当前代码仍使用 `Window("设置", id: "settings")` 场景。

- 默认采用"自动撑满"策略：由 `LaunchpadView.computeIconSize(contentSize:columns:rows:)` 根据实际内容区域尺寸、行列数、间距/边距计算每个 cell，再预留标签高度后让图标尽可能填满。
- `iconSizeOverride` 语义为"图标最大尺寸"：0 表示自动（受 `autoMaxIcon = 96` 上限约束，贴近原生 Launchpad 60~90pt 观感，避免大屏/少列数时撑到 130pt+），非 0 时作为上限（56~200 手动可调）。若用户想要更大，调「图标最大尺寸」滑块即可；若嫌太大，设为 0 即回落到 ≤96pt 自动值。
- 行、列、间距、边距全部进入 `UserPreferences` 并在 `SettingsView` 外观面板用滑块实时调整；`UserPreferences` 现为**存储属性 + `didSet`/init 写回 UserDefaults**，被 `@Observable` 真正追踪，设置面板与启动台界面（LaunchpadView / BackgroundView）改动即同步刷新。
- **外观参数"自动"约定一致化**：列数/行数/图标尺寸原本 `0 = 自动`；现**水平/垂直间距、左右/顶部/底部边距也统一为 `0 = 自动`**（默认值改为 0，去掉了原先的 nonZero 钳制）。`0` 时由 `LaunchpadView` 的 `auto*Spacing()/auto*Padding()` 按目标屏幕尺寸比例推算（如水平间距 = 屏宽×0.018）。新增 `UserPreferences.resetAppearanceToDefault()`（布局类归 0=自动、透明度归 0.10）与设置面板「恢复默认外观」按钮。透明度不参与自动、默认 0.10（2026-07-21 由 0.45 改为 0.10）。
- ⚠️ 坑：曾把 `UserPreferences` 的所有属性写成"计算属性 + 直接读 UserDefaults"，`@Observable` 完全不生效（只追踪存储属性），导致「恢复默认」当前页不刷新、外观滑块不实时变化。务必保持属性为存储属性，持久化放在 `didSet`/`init`，不要退回计算属性。
- 图标视图（AppIconView / FolderThumbnailView）字体最高限制 16pt，防止图标放大后文字比例失衡。
