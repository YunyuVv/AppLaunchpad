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
- 文件夹功能仍在：`FolderInfo`(name/isUserNamed/appIDs) + `FolderController`(create/add/remove/delete/rename) + `FolderThumbnailView`(网格缩略图) + `FolderExpandedView`(展开面板，标题可点按改名→`renameFolder`+saveLayout) + `DragController` 拖入拖出。`layout.json` 的 `folders` 字段运行时非空（之前"彻底移除"记录有误）。
- 背景：磨砂（`.behindWindow` ScreenBlurView）/ 液态玻璃（`NSGlassEffectView`）二选一，**默认玻璃**（backgroundStyle 默认 1）。文件夹面板 `FolderBackdropView` 跟随：玻璃 NSGlassEffectView、磨砂 `.withinWindow` 毛玻璃。
- 右键菜单：打开/在访达中显示/删除（二次确认 `.confirmationDialog`）。删除用 `NSWorkspace.shared.recycle` 保留 Put Back 元数据（禁用 FileManager.trashItem）。
- 拖拽 clamp 用 items.count，落点几何化（GridGeometry 固定几何），make-way 常驻。

## 数据/其他
- 布局：`LayoutStore`(actor)+JSON `~/Library/Application Support/AppLaunchpad/layout.json`（`folders` 字段运行期非空，文件夹功能完整实现）。偏好 `UserPreferences`→UserDefaults.standard（按 bundle id 分域，改 id 历史设置重置）。
- 退出：后台常驻（状态栏+全局热键+NSPanel）；设置窗红叉只关窗不退出；退出仅 ⌘Q/状态栏；Dock 左键→toggle。
- **版本号唯一真源 = `AppLaunchpad/AppLaunchpad/Info.plist`**（注意是两层同名 `AppLaunchpad/`：项目根下还有个源码文件夹）：`CFBundleShortVersionString`（对外，如 0.1.0，对应 git tag `vX.Y.Z`）+ `CFBundleVersion`（内部构建号，每发版 +1）。`project.yml` 未写死版本（仅 `SWIFT_VERSION: 6.0`），故版本完全来自 Info.plist。自动派生方（无需手改）：`AboutPane.swift` 运行时读 `Bundle.main` 的 `CFBundleShortVersionString` 显示"版本 X"（nil 兜底 "0.1.0" 非真源）；CI `build-dmg.yml` 由 xcodebuild 读 Info.plist 构建、产物名固定 `AppLaunchpad.dmg`（不带版本号）；`scripts/release/release-local.sh` 读+写 Info.plist 自动升版并据 `CFBundleShortVersionString` 打 tag；`scripts/release/release-gh.sh` 现**自动升版本并写回 Info.plist**（默认 BUMP=minor 不传参时自动加一；传 `0.2.0` 则按指定）、`CFBundleVersion`+1、自动 git 提交推送后建 tag `vX.Y.Z` 触发 CI 云端打包（彻底替代本地 `release-local.sh`）。唯一仍**人工**的是 `scripts/release/CHANGELOG.md` 段落与 tag 同号。⚠️ `LayoutData.swift` 的 `version: Int = 1` 是 `layout.json` **数据格式版本**，非 app 版本；`references/LaunchNext/` 是第三方参考副本（其 2.4.1 与本项目无关）。
- **固定下载地址（2026-07-26 用户决策）**：CI 产物 DMG 恒名 `AppLaunchpad.dmg`（不带版本号，见 `build-dmg.yml` Package DMG 步）。对外只给一个稳定链接 `https://github.com/YunyuVv/AppLaunchpad/releases/latest/download/AppLaunchpad.dmg`，GitHub 自动解析到「最新非预发布 Release」的同名资产，点击直接下载最新 DMG，永远不用换链接。前提：① 仓库公开（私有仓该 URL 需鉴权）；② Release 不得标 pre-release；③ DMG 名保持不变；④ 版本号递增。发版不再本地跑 `release-local.sh`（占本机资源），改为：手动升 `Info.plist` 的 `CFBundleShortVersionString`+`CFBundleVersion` 并 commit → `./scripts/release/release-gh.sh <ver>` 建 tag+Release（触发 CI 云端打包）；CI 把 `AppLaunchpad.dmg` 上传到该 Release，`latest/download` 链接即生效。**AI 发版标准流程文档：`scripts/release/RELEASE.md`**（含改哪些文件、执行什么命令、红线坑，后续 AI 照此升级版本并触发打包）。
- bundle id：`com.applaunchpad.app` → `com.biliww.applaunchpad`（project.yml: bundleIdPrefix=com.biliww + PRODUCT_BUNDLE_IDENTIFIER=com.biliww.applaunchpad）。
- **TCC 辅助功能弹窗红线（2026-07-26）**：App 启动后**实际调用了**需要辅助功能的 API（`NSEvent.addGlobalMonitorForEvents` 全局快捷键、`CGEventTapCreate` 等）时，系统**自动把 App 登记到设置页"辅助功能"列表里**，不需要任何弹窗。`AXIsProcessTrustedWithOptions(prompt: true)` 显式申请才会弹"X 想要使用辅助功能"系统级授权框——但它本身**不会**让 App 进列表（App 早已在列表里）。**设页"打开辅助功能"按钮直接 `NSWorkspace.shared.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")` 即可**；别再写 `AXIsProcessTrustedWithOptions(prompt: true)`，那个弹窗多此一举。设置页代码：`InteractionPane.swift`（按钮内联 + 删除 `requestAccessibility()` 函数）。

## 暂缓 / 已知难点
- **设置窗口浮于启动台上方 + 背景虚化（2026-07-25 已决策不做，相关 hack 已彻底移除）**：启动台面板 `level = screenSaverWindow-1`（极高，盖 Dock/菜单栏/一切）。多方案尝试均判"不行"，用户于 20:19 回滚并**彻底移除**最早的"降面板 hack"（`lowerPanelForSettings`/`restorePanelLevel`/`setupWindowObservers` 全套已删）。当前设置窗口 = 普通独立 SwiftUI `Window(id:"settings")` 场景（经 `AppDelegate.openSettings`→`settingsOpener`→`openWindow(id:)`），启动台可见时开设置会落在面板之后（用户接受）。**沉淀坑（勿重复踩，详见 `docs/开发指南.md` §6.6 / `docs/待办事项.md` C1）**：
  ① 跨窗口层级时序竞态（先降启动台再开设置，becomeKey 之前压不住）；
  ② macOS SwiftUI `.contextMenu` 与同视图 `.simultaneousGesture(DragGesture)` 冲突→右键菜单弹不出（绕过：用 `NSView` `hitTest` 只拦右键/control+左键、左键拖拽透传）；
  ③ `Window(id:)` 场景被关闭后 `openWindow(id:)` 重开不可靠（SwiftUI 已知 bug）→ 改手动托管 `NSWindow`（`isReleasedWhenClosed=false`, `orderFront`）可解重开，但方案整体被否；
  ④ `NSViewRepresentable` 的 `.background` 子视图 `makeNSView` 时 `view.window == nil` → 想在那设 `window.level` 拿不到窗口（须改 `updateNSView` 等挂载后再设）；
  ⑤ 设置窗口打开时启动台键盘 monitor 仍在跑 → ESC 误关启动台/字母误入搜索，须 monitor 顶部 `guard panel?.isKeyWindow == true`。
  取舍：独立不透明窗口浮层→虚化只在窗口四周边缘外可见（非整屏虚化）；overlay 浮层需丢系统标题栏（样式变化）。若未来重做，要么接受样式变化（overlay 进 `LaunchpadView` ZStack + `FolderBackdropView` 虚化），要么手动托管半透明窗口。

## 权威文档（后续 AI 必读）
- 已完成功能：`docs/产品文档.md`　未完成/已放弃：`docs/待办事项.md`　技术知识库（坑/红线/架构）：`docs/开发指南.md`　分发流程步骤：`docs/分发流程.md`
- 本文是上述文档的精简红线版（自动注入上下文）；改代码前务必核对三文档，以**当前代码事实**为准（旧 `docs/` 下 30+ 历史文档可能过时，且多处误述"文件夹已移除"，实际已实现）。
- **分发决策（2026-07-25 更新）**：用户最终选择**开源发布（GPL v3 兼容）**。→ LaunchNext 外观三卡片 HEIC（GPL v3）因整体开源而**合规，无需替换资源**（`docs/分发流程.md` §0.1 选项 B 落地）。分发方式二选一：①**闭源/商业**→ Developer ID Application 签名 + 公证（`docs/分发流程.md` 第 1–7 步）；②**开源（当前选定主路线）**→ 可发**未签名**包，技术用户执行 `xattr -r -d com.apple.quarantine /Applications/AppLaunchpad.app`（必要时 `sudo spctl --master-disable` 或右键打开→"仍要打开"）后即可运行，首次需在系统设置授权 **Accessibility**（全局快捷键 ⌥+Space 核心依赖）。⚠️ **当前 `project.yml` 是 `Apple Development` 签名，发给他人会因对方无证书而签名验证失败——开源分发前必须改成分发未签名版本**（archive 不带 Developer ID 签名 / `CODE_SIGN_IDENTITY` 置空或 ad-hoc），否则比不签名更糟。MAS 不可行（非沙盒 + 全局快捷键/Accessibility/FSEvents）。**LaunchNext 外观图来源性质（已确认）**：三张 `*.heic` 是设计工具（Sketch/Figma）手绘"仿真 macOS 系统设置窗口"缩略图导出的**静态资源**，工程 grep 无 `ImageRenderer`/`CGImageDestination`/HEIC 编码逻辑，**非运行时生成，不可复用其生成脚本**；自制等效图走：①设计工具 + `sips -s format heic`；②SwiftUI 绘制 + `NSHostingView`/`ImageRenderer` 取位图 + ImageIO 编码（纯命令行 ImageRenderer 易空白）。
