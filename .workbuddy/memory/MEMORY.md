# AppLaunchpad 长期记忆

## 构建 / 签名 / TCC
- 构建：`xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad -configuration Debug clean build`。**勿**带 ad-hoc 签名（令 TCC 失效）。`project.yml` 固化 Manual+Apple Development+TEAM `2VU69Q9CGK`。改 `project.yml`/新增 `.swift` 后需 `xcodegen generate`。
- TCC：Apple Development 证书只绑 identifier+CN，稳定；ad-hoc designated requirement 含二进制哈希，重编译即变→权限失效。残留授权用 `tccutil reset Accessibility com.applaunchpad.app` 清后重授权一次。

## 编码坑
- Swift 6 成员初始化器不含带默认值的存储属性：`struct S{let a:Int;let b:Int=0}` → `S(a:1,b:2)` 编译失败。去默认值或显式写 `init`。
- `NSEvent.Phase` 是 OptionSet：判「无惯性阶段」用 `event.momentumPhase.isEmpty`，非 `== .none`。

## 架构（模块化，同 target 不拆 framework）
- 巨型 `LaunchpadViewModel` 拆为 `LaunchpadData`（@Observable 共享状态：layout/allApps/isVisible/currentPageIndex/searchText/isEditMode/dragState/gridGeometry/翻页/load-save/pendingAppsRefresh/totalPages）+ 4 个 @Observable Controller：`LayoutService`（几何+布局+扫描）、`SearchController`、`DragController`（边缘翻页 Timer .common，`stopEdgeScrollTimer()` 供 exitEditMode）、`NavigationController`。根 VM 组合根+薄壳转发，View 零改动。
- 依赖单向：View→根VM→Controller/Data；Controller 之间互不引用。新增功能进对应 Controller，勿回塞根 VM。
- `Utils/Array+Chunked.swift` 收敛重复 `chunked`。

## 文件夹功能（2026-07-23 已彻底移除）
- **移除**：`FolderController.swift` / `Views/FolderThumbnailView.swift` / `Views/FolderExpandedView.swift` 三个文件 + `DragState.folderHoverID`/`DragContext` 字段 + `DragController` 的 folders 依赖 + 所有文件夹 UI/手势/方法转发。
- **保留（惰性数据骨架，仅为将来扩展）**：`LayoutItem.folder` 枚举项、`LayoutData.folders` 字典、`FolderInfo` 类型。运行时 `LayoutService.mergeLayout` 把遗留 `.folder` 槽位展开为内部 app 并将 `folders` 置空 → 运行时永远不出现文件夹，兼容旧 `layout.json`。
- **未来恢复**（如需）：重建上述 3 个文件 + `DragController` 加回 folders 依赖 + 改回 `mergeLayout` 保留 folders + `endDrag` 加回 `folderHoverID` 归入分支即可，数据格式与持久化层无需动。

## 拖拽落点几何化（关键）
- 纯几何 `GridGeometry`（origin/cols/rows/cellW/cellH/spacing/iconSize）：落点 `slotUnderCursor` 由光标坐标 `row*cols+col` 推导；`iconRect(forSlot:)` 得图标 footprint 区分「压图标」vs「间隙」。`LaunchpadView.pagingView` 用 `GeometryReader` 写 `viewModel.gridGeometry`（标 `@ObservationIgnored` 防死循环）。
- `DragState.cursorSlot` 驱动 make-way 弹簧（来自固定几何、不漂移）。`appAtIconPoint`(起手/翻页)、`slotUnderCursor`(落点) 取代 measured frame/`nearestSlot`。
- **预览与落点统一 `insert at to`**（`to`=光标几何槽位）。曾用 `to>src?to-1` 致向右拖偏左一格，已统一为 `to`。
- 手势宿主在 `LaunchpadView` 根 `ZStack`（`.simultaneousGesture(globalDragGesture+pagingDragGesture)`）；勿挂回单个 app 或 `GridPageView`（items 变→手势取消→跨页卡死）。
- **make-way 常驻、不弹回（2026-07-23）**：`DragController.pageItemsWithDrag` 不再因任何 target 标记返回原始排列。被拖图标从源位移到 `cursorSlot`（同页），其余 app 让位推开不弹回；仅 `cursorSlot` 变化（被拖 app 拖离）时其它 app 才归位。`endDrag` 一律按 `cursorSlot` 重排。
- **app 重排 = 光标落点（2026-07-23）**：拖拽只做"app 在网格内重排"一件事。`updateDragTarget` 用 `slotUnderCursor` 算 `cursorSlot`；`endDrag` 一律 `insert at to`。已无任何"建文件夹/归入"入口与蓝圈/白环高亮——该功能彻底移除（见上节"文件夹功能"）。
- 红线：落点绝不用 measured frame/快照/最近中心；新增落点需求走 `gridGeometry`。
- **松手落点必须用松手瞬间精确坐标（2026-07-23）**：`globalDragGesture.onEnded` 先 `updateDragTarget(location: value.location)` 再 `endDrag()`；`endDrag` 重排分支再以 `geo.slotUnderCursor(dragState.dragLocation)` 兜底重算 `to`。原因：SwiftUI `onEnded` 不保证松手前再发一次 `onChanged`，最后一段位移会让 `cursorSlot` 落后一格→"落不到正位/有点偏离"。
- **拖拽中禁止重建 layout.pages（2026-07-23，审计报告 4.5）**：`LayoutService.refreshApps` 在 `data.dragState.isDragging` 时置 `data.pendingAppsRefresh` 并 `return`，不重建 `pages`（否则 `sourceSlotIndex`/`cursorSlot` 失效→落点错乱/被冲掉）。`DragController` 新增 `layoutService` 依赖，`endDrag` 复位 `dragState` 后若 `pendingAppsRefresh` 则补 `Task{await layoutService.refreshApps()}`，保留刚排好顺序。`LaunchpadData.pendingAppsRefresh` 标 `@ObservationIgnored`。
- **拖拽手势状态必须放 `@State` / `@GestureState`，绝不可放计算属性闭包的 `var`（2026-07-23 关键 bug）**：`LaunchpadView.globalDragGesture` 曾用闭包内 `var hasCheckedStart / var startBundleID`，`@Observable` 拖拽中频繁重算 `body` → 手势每次重建 → 局部变量被重置 → `onEnded` 跑在新实例上 `startBundleID=nil` → `guard` 失败 → `endDrag()` 未执行 → ①app 弹回原位（"没有正确落位"）②`dragState.isDragging` 卡 true → 后续点击被守卫挡掉（"松手后无法点击，需先点别处"）。修法：起手判定状态用 `@GestureState private var dragStart: (checked: Bool, bundleID: String?)`，通过 `.updating($dragStart) { value, state, _ in ... }` 写入，`onEnded` 读 `dragStart.bundleID`。`@GestureState` 是视图级状态、跨 body 重算保留，且为拖拽设计、写它不会中断手势。
- **松手 transition 残影（2026-07-23）**：`floatingDragIcon` 用了 `.transition(.opacity)`，配合 `GridPageView.body` 的 `.animation(.spring, value: cursorSlot)` 在松手时（cursorSlot 从让位值 → 0）触发整网 spring → transition 渐隐期间浮动图标仍渲染在光标位置（"松开就停留在这个地方了, 没有落在正中心"）。修法：①根视图加 `.animation(.interactiveSpring(response: 0.35, dampingFraction: 0.82), value: dragState.isDragging)` 让松手时 transition 与让位回位用同一段 spring 驱动；②`globalDragGesture.onEnded` 用 `withAnimation(.interactiveSpring(...))` 包裹 `viewModel.endDrag()`；③`GridPageView.body` 的 `.animation(_, value: cursorSlot)` 改为 `.animation(_, value: items)`（让位布局与最终布局顺序一致 = insert at to，松手瞬间 items 数组不变 → spring 不触发 → 无残影）。
- **`GridPageView.iconCell` 每个格子必须固定为 `cellW × cellH`（2026-07-23 红线）**：否则视觉格点与 `gridGeometry` 错位 → 布局乱 / 不全屏 / 拖拽落点对不上。

## 设置窗口
- `Window("设置",id:"settings")`+`NavigationSplitView`+`.listStyle(.sidebar)`；入口经 `AppDelegate.openSettings()`→`settingsOpener`→`openWindow(id:)`（**绝不用 `showWindow:`**，Dock 菜单下失效）。打开降面板层级、关闭恢复。
- 外观参数全进 `UserPreferences`（存储属性+didSet 写 UserDefaults，勿写计算属性否则 @Observable 失效）；`0=自动`。透明度默认 0.10。

## 数据/其他
- 布局：`LayoutStore`(actor)+JSON 原子写 `~/Library/Application Support/AppLaunchpad/layout.json`（全量快照 `LayoutData`：分页 `[[LayoutItem]]`+`folders`，**folders 字段运行时永远为空**，仅作兼容字段保留）。偏好：`UserPreferences`→UserDefaults。App 信息不持久化。
- 退出：后台常驻（状态栏+全局热键+NSPanel）。设置窗红叉只关窗不退出（`defaultLaunchBehavior(.suppressed)`+`applicationShouldTerminateAfterLastWindowClosed`→false）。退出仅 ⌘Q/状态栏；Dock 左键→`applicationShouldHandleReopen→toggle()`。
- 键盘吞字：`LaunchpadWindowController.keyDown` 追加 searchText 前先 `isTextInputFirstResponder()` 放行。
