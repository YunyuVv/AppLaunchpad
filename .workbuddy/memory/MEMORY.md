# AppLaunchpad 长期记忆

## 关键约定 / 坑

- **Swift 6 成员初始化器不含带默认值的存储属性**：`struct S { let a: Int; let b: Int = 0 }` → `S(a:1,b:2)` 编译失败。解决：去默认值或显式写 `init`。曾误判为 ModuleCache 过期，清缓存无效。
- **构建命令**：`xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad -configuration Debug clean build`。**不要**带 `CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES`（ad-hoc 签名让 TCC 权限每次重编译失效）。`project.yml` 固化 Manual + Apple Development + TEAM `2VU69Q9CGK`（证书指纹 `F4171D2397EFE92485DB3B20C38456DDB0DB0A62`）。改 `project.yml` 后需 `xcodegen generate`。
- **TCC**：ad-hoc designated requirement 含二进制哈希，重编译即变 → 辅助功能等权限失效。Apple Development 证书只绑 identifier + 证书 CN，稳定。残留授权用 `tccutil reset Accessibility com.applaunchpad.app` 清后重新授权一次即持久。
- **NSEvent.Phase 是 OptionSet**：判「无惯性阶段」用 `event.momentumPhase.isEmpty`，非 `== .none`（会被解析成 Optional.none 恒 false）。
- **退出行为**：后台常驻工具（状态栏 + 全局热键 + 全屏 NSPanel）。**设置窗点红叉只关窗不退出**：`AppLaunchpadApp.swift` 的 `Window("设置",id:)` 加 `.defaultLaunchBehavior(.suppressed)`；`AppDelegate` 显式实现 `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`（默认 false 在单一 Window 场景拦不住）。退出仅 ⌘Q / 状态栏菜单；Dock 左键 → `applicationShouldHandleReopen → toggle()`。

## 架构速记
- 混合 AppKit + SwiftUI：NSPanel 全屏浮层（LaunchpadWindowController），@Observable ViewModel（LaunchpadViewModel @MainActor）。
- 全局热键：`NSEvent.addGlobalMonitorForEvents`（keyCode + modifier）。

## 设置窗口架构
- `Window("设置", id:"settings")` + `NavigationSplitView` + `.listStyle(.sidebar)`，左侧系统磨砂 sidebar，右侧 detail 自动生成 sidebar toggle，标题「设置」。
- 入口：菜单 / 状态栏 / Dock 右键菜单 → `AppDelegate.openSettings()` → `settingsOpener` 闭包 → `openWindow(id:)`。**必须用 `openWindow(id:)`，绝不用 `showWindow:`**（响应者链对 SwiftUI 场景不可靠，Dock 菜单下直接失效）。AppDelegate 经 `appDelegate.setSettingsOpener { self.openWindow(id:"settings") }` 注入。
- 打开设置时 `NSWindow.didBecomeKeyNotification` 把启动台面板降层级；关闭后 `willCloseNotification` 恢复。勿用手动 `NSWindow+NSHostingController` 承载 `NavigationSplitView`（SwiftUI 不会生成系统 toolbar 的 sidebar toggle）。
- 外观：列/行/间距/边距/图标尺寸全进 `UserPreferences`，滑杆实时调整。`UserPreferences` 必须**存储属性 + didSet/init 写回 UserDefaults**（曾误写成计算属性 → `@Observable` 完全失效）。列/行/图标尺寸/水平垂直间距/四边距统一 `0=自动`，0 时由 `LaunchpadView.auto*Spacing()/auto*Padding()` 按屏比例推算；`resetAppearanceToDefault()` 归 0 / 透明度 0.10（2026-07-21 由 0.45 改）。图标字体 ≤16pt。

## 拖拽排序链路（2026-07-21）
- 「直接拖动即进编辑」：`AppIconView`/`FolderThumbnailView` 上挂常驻 `.highPriorityGesture`（minDistance 5），`onChanged` 首帧无编辑态先 `onLongPress()` 进编辑再 `onBeginDrag`。
- **手势竞争**：Button 上不可加 `DragGesture(minimumDistance:0)` 拿按压态（与 `onLongPressGesture` 抢识别）。按压态用 `onLongPressGesture` 的 `onPressingChanged: isPressed = pressing && !isEditMode`。
- **拖拽手势必须 `.highPriorityGesture` 且宿主在 `GridPageView` 容器**（`.simultaneousGesture(gridDragGesture())`），据 `startLocation` 查 `slotFrames` 找起点 app，拖动查最近槽位，松手按 `currentPageIndex` 落点；`pagingDragGesture` 加 `!dragState.isDragging` 防竞争。**把拖拽手势挂回单个 app 视图会复现跨页卡死，勿改。**（早期修法「翻页加 `.id(currentPageIndex)` 去掉」已被推翻，真正根因是手势宿主位置。）
- 编辑态左上角 X 已移除（仅 FolderExpandedView 保留真实删除）。Folder 不参与网格拖拽（只点击打开 / 长按进编辑）。
- **Timer 必须加 `.common`**：文件夹创建(0.7s)/边缘翻页(0.8s) 的 Timer 在拖拽中 AppKit 切 `NSEventTrackingRunLoopMode`，`Timer.scheduledTimer` 默认 `.default` 不 fire → 功能失效。改用 `Timer(timeInterval:)+RunLoop.main.add(...,forMode:.common)`（`LaunchpadViewModel.startFolderProgressTimer/startEdgeScrollTimer`）。任何「拖拽/手势/滚动期间靠计时器触发」的逻辑都须加 `.common`。
- **键盘吞字**：`LaunchpadWindowController.keyDown` 任意可打印字符追加 `searchText` 前先 `isTextInputFirstResponder()` 放行 TextField（SwiftUI 可输入控件须靠此放行）。

## 文件夹行为（2026-07-21）
- 内 app 从左上角：`LazyVGrid(alignment:.leading)`（非 `.topLeading`，那是两轴 `Alignment` 会编译错）。`FolderExpandedView` 内 `highPriorityGesture(folderDragGesture)`，复用同一 `DragState` 状态机 + `floatingDragIcon`；松手在 `folderGlobalFrame` 外则 `moveAppOutOfFolder`，否则 `commitFolderReorder`。`FolderSlotFrameKey` 收集 cell 坐标。重命名内联编辑 → `renameFolder`。
- 缩略图：`FolderThumbnailView` 3×3 `LazyVGrid(alignment:.leading)` + frame `.topLeading`。
- 编辑态不晃动（`WobbleModifier.swift` 保留不删，便于恢复）。

## 跨页拖拽卡死根因（2026-07-21，关键）
- 手势宿主必须比被切换的页面内容更稳定。把网格拖拽手势挂在单个 `AppIconView` 或 `GridPageView`（会因 items 变化被重建）→ 进行中的 `DragGesture` 随视图销毁而取消 → 「拖到第二页卡死、浮动图标冻结」。
- 最终解：手势放到 `LaunchpadView` body 最外层 `ZStack`（`.simultaneousGesture(globalDragGesture())`），该视图身份在启动台显示期间绝对稳定。`GridPageView` 只负责渲染 + 收集 `slotFrames`，不再处理拖拽。`globalDragGesture` 按 `startLocation` 判起点 app，空白/文件夹则忽略让 `pagingDragGesture` 翻页。`flipPageWhileDragging` 只切 `currentPageIndex`（不搬移 app）；`endDrag` 从 `sourcePageIndex` 移除、插入 `currentPageIndex` 目标槽位并修正同页移除后索引偏移。

## 数据存储架构（2026-07-21 确认）
- 布局：`LayoutStore`（`actor`）+ `JSONEncoder/Decoder` 原子写 `~/Library/Application Support/AppLaunchpad/layout.json`，全量快照（`LayoutData`：分页 `[[LayoutItem]]` + `folders:[UUID:FolderInfo]`）。
- 偏好：`UserPreferences`（`@Observable`）存储属性 `didSet` 写 `UserDefaults.standard`。
- App 信息不持久化，运行时扫码只存 bundleID 引用。
- SwiftData 评估：部署目标 macOS 26 满足最低 14，但不推荐迁移——`LayoutItem` 是带关联值枚举（SwiftData 无法原生持久化）、嵌套数组+字典需拆实体图、当前全 struct 需改 class @Model；布局本质是「全量有序快照」，JSON 最契合。仅当大量独立可查询记录或文件夹套文件夹时才划算；结构化查询优先 GRDB 而非 SwiftData。
