# LaunchNext 启动台实现分析

> 参考项目：`references/LaunchNext/`（开源，GPL-3 许可，基于 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) 演化）
> 分析目的：弄清 LaunchNext 的启动台（Launchpad）是如何实现的、交互用什么技术、与本项目 `AppLaunchpad`（纯 SwiftUI）有何差异，作为后续借鉴的参考。
> 关键结论先行：**LaunchNext 与本项目走的是两条技术路线**——本项目是纯 SwiftUI（`LazyVGrid` + `DragGesture` + `@Observable`），而 LaunchNext 主体是 **AppKit `NSView` + Core Animation 图层树**，通过 `NSViewRepresentable` 嵌入 SwiftUI，并且额外支持 4/5 指原生手势、游戏手柄、热角等多输入源。

---

## 1. 项目概览

LaunchNext 是 macOS Tahoe（26）移除原生 Launchpad 后的第三方替代启动器，定位是「复刻经典 Launchpad 体验」。核心能力（来自 `README.md`）：

- 一键从系统原生 Launchpad SQLite 数据库导入布局/文件夹（`/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`）
- 经典启动台网格 + 自定义行列/图标尺寸/隐藏标签
- 智能文件夹（建文件夹、分页/垂直滚动两种布局）
- 模糊搜索 + 键盘导航
- CLI / TUI 终端管理布局
- **热角、原生 4/5 指手势、拖到 Dock、游戏手柄** 等多种唤起/交互方式
- 多语言（含简/繁中文）

技术栈：**Swift + AppKit + Core Animation + SwiftUI（混合）**，数据用 **SwiftData（Data.store）** 持久化，原生手势依赖第三方 **OpenMultitouchSupport** C 框架。

---

## 2. 整体架构

### 2.1 App 生命周期与窗口

入口是 SwiftUI `App` + `NSApplicationDelegateAdaptor` 适配器，但**实际窗口完全由 AppDelegate 用 AppKit 创建**，SwiftUI 只作为内容宿主：

```swift
// LaunchpadApp.swift
@main
struct LaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings {} }   // 无 Scene 内容，纯粹由 AppDelegate 驱动
}
```

AppDelegate 创建的是一个**无边框 `NSWindow` 子类**（不是 `NSPanel`、没有 `NSWindowController`）：

```swift
class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
// setupWindow 内：
window = BorderlessWindow(contentRect: rect,
                          styleMask: [.borderless, .fullSizeContentView],
                          backing: .buffered, defer: false)
window?.collectionBehavior = [.transient, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
window?.level = .floating
window?.contentView = NSHostingView(rootView: LaunchpadView(appStore: appStore).modelContainer(container))
```

桥接只有一层：`NSHostingView` 把 SwiftUI 的 `LaunchpadView` 挂到 `contentView`；而网格本身再经 `NSViewRepresentable` 嵌进 `LaunchpadView`。

> 对比本项目：本项目用 **`NSPanel` 全屏浮层 + `LaunchpadWindowController`**（`Window("设置")` 是独立 SwiftUI Scene）。LaunchNext 用无边框 `NSWindow` + `NSHostingView`，把整个 SwiftUI 树当内容，不区分"启动台面板"和"设置窗口"两种窗口类型。

### 2.2 全屏 vs 紧凑

由 `appStore.isFullscreenMode`（UserDefaults，默认 `true`）控制：

- **全屏**：`updateWindowMode(isFullscreen:)` 把窗口 frame 设为 `screen.frame`，`applyCornerRadius()` 把圆角设为 0，`.fullScreenAuxiliary` 使它能覆盖全屏 App 之上。
- **紧凑**：窗口约为屏幕可见区域 40% 宽、3:4 比例居中。

### 2.3 两套渲染引擎

LaunchNext 在设置里提供 **Legacy Engine** 与 **Next Engine + Core Animation** 两套，由 `appStore.useCAGridRenderer`（默认 `true`）切换：

```swift
// LaunchpadView.swift
if !appStore.useCAGridRenderer {
    ScrollEventCatcher { ... }          // Legacy：SwiftUI 版（自带 ScrollView 滚动捕获）
}
// ...
if appStore.useCAGridRenderer {
    CAGridViewRepresentable(...)        // Next Engine：Core Animation 渲染
}
```

当 `performanceMode == .full`（兼容模式）时 `useCAGridRenderer` 会被强制置 `false`。官方推荐 Next Engine。

---

## 3. 启动台网格渲染实现（CAGridView）

这是 LaunchNext 的核心，也是与本项目最大的差异点：**用 Core Animation 的 `CALayer` 层级渲染网格，而不是 SwiftUI 的 `LazyVGrid` 子视图。**

### 3.1 图层结构

```swift
// CAGridView.swift
final class CAGridView: NSView, CALayerDelegate, NSDraggingSource {
    var containerLayer: CALayer!        // 根容器
    var pageContainerLayer: CALayer!    // 整页容器，靠 transform 平移实现翻页
    var iconLayers: [[CALayer]] = []    // [page][item]，每个 item 一个 CALayer 容器
}
```

每个 item 的容器 `CALayer` 内部分层：

- `iconLayer: CALayer`（`contentsGravity = .resizeAspect`，`shouldRasterize = true`）——图标位图
- `textLayer: CATextLayer`——标签文字（含 `contentsScale`、深浅色 `foregroundColor`）
- 文件夹额外有 `glassLayer`——玻璃背景
- App 额外有 `batchSelectionCheckbox`（`CAShapeLayer` 勾选标记，批量选择用）

翻页就是平移整页容器，不是重建视图：

```swift
pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
```

### 3.2 布局算法

布局参数：`columns` / `rows` / `iconSize` / `columnSpacing` / `rowSpacing` / `contentInsets` / `pageSpacing`，`itemsPerPage = columns * rows`，`pageCount = ⌈items / itemsPerPage⌉`。

核心坐标计算（macOS 原点在左下，自上而下排布）：

```swift
let usableWidth  = availableWidth  - totalColumnSpacing
let usableHeight = availableHeight - totalRowSpacing
let cellWidth  = usableWidth  / CGFloat(max(columns, 1))
let cellHeight = usableHeight / CGFloat(max(rows, 1))
let col = localIndex % columns
let row = localIndex / columns
// 自上而下（macOS y 轴向上）：
let cellOriginY = pageHeight - contentInsets.top
                - CGFloat(row + 1) * cellHeight - CGFloat(row) * rowSpacing
```

`gridCenterForGlobalIndex(_:)` / `iconCenter(for:)` / `itemAt(_:)` / `gridPositionAt(_:)` 这几个方法把"全局索引 / 点击坐标"互相换算，是后续拖拽落点判定、命中测试的基础。

### 3.3 SwiftUI 桥接

```swift
// CAGridViewRepresentable.swift
struct CAGridViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> CAGridView { CAGridView(frame: .zero) }
    func updateNSView(_ nsView: CAGridView, context: Context) { /* 同步参数 */ }
}
```

回调（`onCreateFolder` / `onMoveToFolder` / `onReorderItems` / `onRequestNewPage` 等）把 CA 层发生的事件转交 `AppStore`（数据层），由 Representable 的 `Coordinator` 承接 `NSView` 的闭包并桥回 SwiftUI 环境。

### 3.4 高刷新率

```swift
displayLink = window.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
displayLink?.add(to: .main, forMode: .common)
```

用 `CADisplayLink` 驱动滚动/拖拽动画，目标 120Hz ProMotion，仅在 `isScrollAnimating || isDraggingItem` 时更新，空闲时重置帧计数省电。

---

## 4. 交互与输入技术（重点）

LaunchNext 的交互是**多输入源**设计，按输入设备分四类。网格本身**完全没有用 `NSGestureRecognizer`**，而是直接用 `NSView` 的 `mouseDown/Dragged/Up` 重写 + `NSEvent` 本地监视器 + `NSTrackingArea`。

### 4.1 鼠标 / 触控板（CAGridView + Input.swift）

**点击与拖拽**：

```swift
override func mouseDown(with event: NSEvent) {
    if let (item, index) = itemAt(location) {
        if event.clickCount == 1 {
            pressedIndex = index
            animatePress(at: index, pressed: true)
            dragStartPoint = location
            // 长按 0.5s 触发拖拽（Timer 必须加 .common，否则拖拽中 runloop 模式切换会失效）
            let timer = Timer(timeInterval: longPressDuration, repeats: false) { [weak self] _ in
                self?.startDragging(item: item, index: index, at: location)
            }
            RunLoop.main.add(timer, forMode: .common)
            longPressTimer = timer
        }
    } else {
        isPageDragging = true   // 点空白 → 进入"页面拖拽"模式
    }
}
```

`mouseDragged` 中：移动超过 **10pt** 立即 `startDragging`（取消长按计时器，马上进入拖拽）；点空白区域拖动则是整页横移（带橡皮筋 `rubberBand` 边界阻力）。

**滚轮 / 翻页**用了两种机制叠加：

1. `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)` 本地监视器（`setupScrollEventMonitor`），只在窗口可见且为 key window、且事件落在视图范围内时处理，并 `return nil` 消费事件，防止双重处理；
2. `override func scrollWheel(with:)` 作为兜底（当没有本地监视器时）。

触控板精确滚动（`hasPreciseScrollingDeltas`）按 `phase`（began/changed/ended）做橡皮筋 + 翻页；鼠标滚轮用 `handleWheelPaging` 累积阈值翻页。

**悬停放大**：`updateTrackingAreas` 注册 `NSTrackingArea`（`.mouseMoved, .activeInKeyWindow, .inVisibleRect`），`mouseMoved` 中根据 `itemAt` 命中更新 `hoveredIndex` 并 `applyScaleForIndex`。

> 注：AppDelegate 才是 `NSGestureRecognizerDelegate`，但只用于背景点击关闭（`handleBackgroundClick`）。**网格交互完全绕开了 `NSGestureRecognizer`。**

### 4.2 原生多点触控手势（OpenMultitouchSupport）

这是 LaunchNext 的"实验性"卖点：4/5 指张开/捏合/轻点唤起启动台。底层走第三方 **OpenMultitouchSupport** C 框架（封装在 `OMSManager`）。

识别管线（Swift Concurrency + 状态机）：

```swift
// GestureMonitor.swift
gestureMonitor holds GestureTouchProvider + 每设备一个 GestureStateMachine
Task {
    for await frame in provider.touchDataStream {   // 原始手指坐标流
        stateMachine.process(frame)
        if stateMachine.state == .triggered { onTrigger(...) }  // 回主线程
    }
}
```

`GestureTouchProvider` 封装 `OMSManager.shared`，监听底层 `OpenMTEvent`，暴露为 `AsyncStream<OMSTouchFrame>`；`activeDeviceID` 锁实现设备路由（可选外部触控板）。

**状态机**（`GestureStateMachine.swift`）：`idle → arming → tracking → triggered → cooldown`。

- 进入 `arming` 需手指数 == `requiredFingerCount`（默认 4）；
- `tracking` 计算：手指间两两距离**中位数**作为 `scale`、质心 `centroid`、每指相对质心半径求 `perFingerRadialRatios`；
- **张开（open）**：`scaleRatio <= 0.84` 且参与张开手指 ≥ 3；
- **捏合（close）**：`scaleRatio >= 1.06` 且 leading 指半径比与 gap 达标；
- **轻点（tap）**：`tapMaxDuration 0.20s` 内抬起、移动 < `0.045`、缩放偏差 < `0.10` → `.toggle` / `.open`；
- 需连续 `requiredConsecutiveMatches(2)` 帧匹配才触发。

`AppDelegate.handleGestureTrigger` 把 `.open/.close/.toggle` 映射到 `showWindow / hideWindow / toggleWindow`。含 sleep/wake 恢复逻辑。

### 4.3 游戏手柄（ControllerInputManager.swift）

用系统 `GameController` 框架：

- `GCController.startWirelessControllerDiscovery`、`GCControllerDidConnect/Disconnect` 通知；
- `extendedGamepad`（双摇杆）与 `microGamepad`（Siri Remote 类）分别配置：dpad + 左摇杆 → 方向；`buttonA → .select`、`buttonB/Menu → .cancel`、`buttonOptions → .menu`；
- 方向轴 `axisThreshold = 0.6` 离散化，带 `DispatchSourceTimer` 长按重复（0.25s 后每 0.14s `.moveRepeat`）；
- `.menu` 命令 → `toggleWindow()`。

### 4.4 热角（HotCornerMonitor.swift）

- `start()` 安装**本地 + 全局** `NSEvent` 鼠标移动监视器；
- `handlePointerActivity` 取 `NSEvent.mouseLocation`，用 `hotCornerIdentifier(at:)` 检测是否落进某屏四角的 `hitboxRect`（size = `hitboxSize`）；
- 停留 `triggerDelay` 后触发 → `show/hideWindow`，含 1s 冷却。

### 4.5 全局热键（Carbon）

唤起启动台用 Carbon `RegisterEventHotKey`（`LaunchpadApp.swift`）：

```swift
RegisterEventHotKey(configuration.keyCodeUInt32,
                    configuration.carbonModifierFlags,
                    hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
```

`handleHotKeyEvent → toggleWindow()`。隐藏窗口时 0.25s 淡出后 `orderOut`。

### 4.6 拖拽重排与拖入文件夹（自研 CALayer 逻辑）

这是交互里最复杂的部分，全部在 `CAGridView+Input.swift`：

- **开始拖拽** `startDragging`：隐藏原图标（`opacity = 0`），创建 `draggingLayer`（CALayer 容器，放大 1.1 倍、跟随光标），并预渲染高分辨率图标位图（`IconStore`）；
- **实时重排** `updateDragging` → `gridPositionAt` 求悬停格，`isPointInFolderDropZone` 判断落点是否在文件夹中心区（中心矩形 = `iconSize * folderDropZoneScale`）；延迟 0.15s（`hoverUpdateDelay`）后 `applyIconPositionUpdate` 用 `CATransaction`（0.45s，`controlPoints(0.25,1,0.35,1)`）做弹簧位移，把目标位前后的图标推开/合拢；
- **边缘翻页** `checkEdgeDrag` + `startEdgeDragTimer`：距边缘 60pt、停留 0.4s 自动翻页（`Timer` 同样加 `.common`）；
- **落点判定** `endDragging`：
  - app + app → `onCreateFolder?`（建文件夹）
  - app + folder → `onMoveToFolder?`（移入已有文件夹）
  - 其余 → `onReorderItems?`（含跨页 `moveItemAcrossPagesWithCascade`）
- **拖到 Dock**：`shouldStartExternalDockDrag` / `startExternalDockDrag` 用 `NSDraggingSession` + `NSDraggingItem` 发起系统级拖拽，`AppDelegate.beginExternalSystemDragSession()` 防止窗口在拖出时自动隐藏。

---

## 5. 文件夹实现

文件夹有两条平行路径（与网格的 Legacy / CA 双引擎一致）：

**CA 引擎** `CAFolderGridView`（NSView + CALayer）：

```swift
final class CAFolderGridView: NSView {
    var layoutMode: AppStore.FolderLayoutMode = .paged { didSet { ... } }
    private var contentLayer = CALayer()
    private var appLayers: [CALayer] = []
}
```

- 自动按可用区域算列数（paged 限 8 列 / 5 行，vertical 按需行数）；
- **paged**：`contentLayer.transform` 横向平移 + 边缘翻页定时器（`pageFlipEdgeWidth=60, pageFlipDelay=0.4`）；
- **vertical**：`verticalOffset` 垂直滚动，标题随滚动淡出；
- 拖出文件夹边界触发 `onDragAppOut`，由 Representable 接力到外层。

**SwiftUI 引擎** `FolderView`：当 `useCAGridRenderer` 时用 `CAFolderGridViewRepresentable`，否则 `ScrollView { LazyVGrid { LaunchpadItemButton... } }` + 自管 `DragGesture`。打开/关闭用 `.transition(LNAnimations.folderOpenTransition)` + `.liquidGlass` 玻璃背景；支持双击名称内联重命名、键盘导航（`setupKeyHandlers` 本地 keyDown）、手柄导航（`.onReceive(ControllerInputManager.shared.commands)`）。

---

## 6. 动画技术

三层动画并存：

| 层级 | 技术 | 用途 |
|---|---|---|
| SwiftUI 层 | `Animation` / `.transition` | UI 元素 hover/选中/按压/文件夹开合 |
| Core Animation 层 | `CATransaction` / `CATransform3D` | 网格翻页、图标实时重排弹簧位移 |
| 窗口层 | `NSAnimationContext` | 窗口淡入淡出（0.25s） |

`Animations.swift`（`LNAnimations`）集中管理：

```swift
static var springFast: Animation {
    .spring(response: AnimationPreferences.springResponse, dampingFraction: 0.8)
}
static var folderOpenTransition: AnyTransition {
    .scale(scale: 0.95).combined(with: .opacity)
}
```

由 `enableAnimations` / `animationDuration`（UserDefaults）统一开关与调速。CALayer 侧：图标缩放 0.12s、实时重排 0.45s、翻页用指数收敛 + 带过冲阻尼弹簧（`springEaseOut` 自实现贝塞尔求解）。

---

## 7. 数据源与布局持久化

- **AppInfo**：`NSWorkspace.shared.icon(forFile:)` 取系统图标；名称优先本地化（`CFBundleDisplayName`）；`id` 用 `url.path`。
- **缓存**：`AppCacheManager`（LRU，`iconCache` max 200 / `gridLayoutCache`）、`IconStore`（`NSCache`，countLimit 200）。`isLeanMode`（Next Engine）下跳过图标缓存省内存。
- **原生 Launchpad 导入** `NativeLaunchpadImporter`：直接用 **SQLite3 C API**（非 FMDB）只读打开系统库，校验 `apps`/`groups`/`items` 三张表；层级模型 `Root(type=1) → TopContainers(3) → Pages(2) → Slots(3) → Apps(4)`，文件夹由 `type=2` 页表示；`findLocalApp` 用 `absolutePathForApplication(withBundleIdentifier:)` 反查本机 .app 路径写回。注意：注释明确"目前仅支持 legacy schema"，遇 Z* 新架构会报错。
- **持久化**：`Data.store`（SwiftData），路径 `~/Library/Application Support/LaunchNext/Data.store`。`ModelContainer` 配置 `PageEntryData`（按 `pageIndex`/`position`/`kind`/`appPath`/`folderId`/`appPaths`），`saveAllOrder()` 清空后逐 item 写入，`modelContext.save()`；隐藏/退出前持久化。旧版 `TopItemData` 保留用于迁移。

---

## 8. 搜索（模糊匹配）

`LaunchpadSearchEngine.filter` 在 `searchQuery` 变化时对 `items` 过滤；模糊算法在 `FuzzyMatcher`，索引结构 `SearchIndexEntry` 做归一化/分词/首字母缩写：

```swift
// SearchIndexEntry
normalizedName = Self.normalize(displayName)  // 去变音符/大小写/宽度，仅留字母数字
tokens       = Self.tokenize(displayName)     // 分词
acronym      = tokens.compactMap(\.first).map(String.init).joined()  // 首字母缩写
```

`FuzzyMatcher` 打分（越高越靠前）：完全相等 **1000** → `hasPrefix` **700−** → token 前缀 **520−** → 首字母缩写前缀 **470−** → 子序列匹配 **300+**（按前导位置 + 紧凑度 + 连续相邻加成）→ 仅 `contains` **180** → 否则 `nil`（不出现）。所以 "sf" 对 "Safari" 优于靠后的匹配。

---

## 9. 与本项目 AppLaunchpad 的对比

| 维度 | LaunchNext | AppLaunchpad（本项目） |
|---|---|---|
| 网格渲染 | AppKit `NSView` + `CALayer` 图层树 | 纯 SwiftUI `LazyVGrid` 子视图 |
| SwiftUI 桥接 | `NSViewRepresentable`（`CAGridView`） | 原生 SwiftUI View |
| 翻页 | `pageContainerLayer.transform` 平移 + `CADisplayLink` 120Hz | `pagingDragGesture` + 就地切页（去 `.id` 防手势销毁） |
| 点击/拖拽 | `NSView.mouseDown/Dragged/Up` 重写 + `NSEvent` 本地监视器 | SwiftUI `.highPriorityGesture(DragGesture)` |
| 多输入 | 触控板手势（OpenMultitouchSupport）、游戏手柄、热角、Carbon 热键、拖到 Dock | 全局快捷键（`NSEvent.addGlobalMonitorForEvents`）、状态栏、Dock 菜单 |
| 文件夹 | CA 引擎 `CAFolderGridView`（paged/vertical）+ SwiftUI `FolderView` | `FolderExpandedView`（`LazyVGrid` + `DragGesture`） |
| 动画 | `CATransaction` + `CAFrameRateRange` + SwiftUI `Animation` | SwiftUI `Animation` / 系统转场 |
| 数据来源 | `NSWorkspace` 扫描 + 读原生 SQLite + SwiftData `Data.store` | 系统 App 扫描 + `UserDefaults`/文件持久化 |
| 搜索 | 自研 `FuzzyMatcher`（归一化/缩写/子序列打分） | 搜索框 + 过滤 |
| 许可 | GPL-3（含传染性，复用代码需注意） | 自有 |

**关键差异洞察**：

1. **性能取向不同**。LaunchNext 用 CALayer 直接操作矩阵、120Hz DisplayLink，避免了 SwiftUI 在数百图标重排时的视图重建开销；本项目用 SwiftUI 声明式重建（靠"松手才提交重排 + 不翻页 `.id`"规避卡死）。图标数量极大时 CA 路线更稳。
2. **输入覆盖度**。LaunchNext 显著领先：原生 4/5 指手势、手柄、热角都是本项目没有的。本项目目前仅全局快捷键 + 状态栏 + Dock 唤起，以及鼠标拖拽。
3. **拖拽落点判定**。LaunchNext 在 CA 层用 `gridPositionAt` 纯几何换算 + 延迟 0.15s 提交，本项目用 `SlotFrameKey` preference 收集槽位 frame 后查最近。思路一致，但 LaunchNext 的"拖拽手势宿主在容器、按 startLocation 反查"正是本项目 2026-07-21 修跨页卡死时采用的同一方案——说明两条路线在这个坑上殊途同归。
4. **Timer/runloop 坑一致**。LaunchNext 在 `mouseDown` 长按计时器、`startEdgeDragTimer` 都显式 `RunLoop.main.add(timer, forMode: .common)`；本项目同样在 `startFolderProgressTimer/startEdgeScrollTimer` 踩过 `.common` 的坑。拖拽中 runloop 切 `NSEventTrackingRunLoopMode` 是 AppKit 通病，两条路线都绕不开。

---

## 10. 可借鉴点（给本项目）

1. **多输入唤起**：若想增强唤起方式，可参考 `HotCornerMonitor`（NSEvent 鼠标位置 + hitbox 判定）与 `GestureMonitor`+`GestureStateMachine`（OpenMultitouchSupport 4/5 指）；手势识别用"中位数距离/质心/半径比 + 连续 N 帧匹配"的状态机范式很稳，值得移植思路（注意 OpenMultitouchSupport 是第三方 C 依赖，需评估引入成本与 GPL 传染）。
2. **模糊搜索**：`FuzzyMatcher` 的"归一化 + 分词 + 首字母缩写 + 子序列打分"算法可直接借鉴到本项目的搜索框，体验明显优于纯 `contains`。
3. **拖拽实时重排的弹簧动画**：`applyIconPositionUpdate` 用 `CATransaction`(0.45s, controlPoints 0.25,1,0.35,1) 推开/合拢邻近图标，配合"延迟 0.15s 提交防抖"，手感顺滑；本项目目前是松手才重排，可参考加入拖动中实时让位动画。
4. **批量选择 + 拖到 Dock**：`batchSelectionMode` 与 `startExternalDockDrag`（`NSDraggingSession`）是本项目缺失的能力，若要做"多选批量整理 / 拖到 Dock"可参考。
5. **原生布局导入**：`NativeLaunchpadImporter` 读系统 Launchpad SQLite 一键迁移用户已有布局，是极强的"零配置上手"卖点，本项目可考虑实现同类导入。
6. **120Hz 滚动**：如未来本项目因图标多出现滚动卡顿，可参考 `CADisplayLink` + `CAFrameRateRange` 的 CA 路线（但需权衡改造成本——当前纯 SwiftUI 方案更易于维护）。

> 许可提醒：LaunchNext 为 **GPL-3**。本项目若直接复制其代码需遵守 GPL（可能要求开源本项目），因此**建议只借鉴架构思路与算法，不直接拷贝源码**（尤其 `Gesture/`、模糊搜索、拖拽逻辑等核心模块）。
