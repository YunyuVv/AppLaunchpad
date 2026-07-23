# AppLaunchpad 开发知识库

> 最后更新：2026-07-24 | 版本 0.1.0

本文档是 AppLaunchpad 的权威开发知识库，供 AI 助手和开发者理解项目现状、继续修改和开发。
**修改任何代码前，请先阅读本文档。**

---

## 1. 项目概览

AppLaunchpad 是一个 macOS 启动台替代品，macOS 26.0 (Tahoe)，Swift 6.0，SwiftUI + AppKit 混合。

- **仓库**：`/Users/wangpenglong/projects/swift/macos/AppLaunchpad/`
- **源码根**：`AppLaunchpad/AppLaunchpad/`（多一层目录）
- **工程**：`project.yml` → XcodeGen 生成 → `AppLaunchpad.xcodeproj`
- **签名**：Apple Development, TEAM `2VU69Q9CGK`, Manual, 非 ad-hoc（TCC 权限需要）
- **零第三方依赖**：纯 Swift 标准库 + SwiftUI + AppKit

---

## 2. 目录结构与职责

```
AppLaunchpad/AppLaunchpad/
├── App/
│   ├── AppDelegate.swift            # 菜单栏图标、Dock 菜单、全局快捷键、FSEvents
│   └── AppLaunchpadApp.swift        # @main 入口，SwiftUI Settings 场景
├── Models/
│   ├── AppInfo.swift                # 应用数据（bundleID, displayName, icon, isMASApp）
│   ├── DragState.swift              # 拖拽状态机（isDragging/draggedBundleID/sourceSlotIndex/cursorSlot/dragLocation）
│   ├── FolderInfo.swift             # 文件夹数据（保留未用，扩展点）
│   ├── GridGeometry.swift           # 网格几何：slotUnderCursor, iconRect 纯几何推导
│   ├── LayoutData.swift             # LayoutItem 枚举 + LayoutData 布局（pages + folders）
│   └── UserPreferences.swift        # @Observable 单例：外观/快捷键/多屏偏好
├── Persistence/
│   └── LayoutStore.swift            # actor：JSON 原子读写 ~/Library/Application Support/AppLaunchpad/layout.json
├── Services/
│   ├── AppScanner.swift             # actor：扫描 /Applications 等目录
│   ├── FSEventsWatcher.swift        # actor：DispatchSource 监听目录变化（2s debounce）
│   ├── FuzzySearch.swift            # 模糊搜索打分器
│   └── IconCache.swift              # actor：NSCache 图标缓存（50MB）
├── Utils/
│   └── Array+Chunked.swift          # Array 扩展：按大小分块
├── ViewModel/
│   ├── LaunchpadViewModel.swift     # 组合根 + 薄壳转发（View ↔ Controller/Data）
│   ├── Core/
│   │   └── LaunchpadData.swift      # @Observable 共享状态：allApps/layout/search/drag/pageIndex
│   └── Controllers/
│       ├── DragController.swift     # 拖拽状态机 + 边缘翻页 + pageItemsWithDrag 让位
│       ├── LayoutService.swift      # 几何密度/重分页/扫描合并/持久化加载
│       ├── NavigationController.swift # 键盘方向键导航 + 回车启动
│       └── SearchController.swift   # 模糊搜索过滤 + 打分排序
├── Views/
│   ├── AppIconView.swift            # 单应用图标（hover/按压/删除）
│   ├── BackgroundView.swift         # 全屏模糊背景
│   ├── GridPageView.swift           # 单页网格（VStack+HStack + 弹簧动画）
│   ├── LaunchpadView.swift          # 启动台根视图（全局手势宿主 + GeometryReader）
│   ├── PageIndicatorView.swift      # 底部页码圆点
│   ├── SearchBarView.swift          # 顶部搜索框
│   ├── WobbleModifier.swift         # 编辑模式抖动动画
│   └── Settings/
│       ├── SettingsView.swift        # NavigationSplitView + 侧栏
│       ├── AppearancePane.swift      # 透明度/密度/尺寸/间距
│       ├── DisplayPane.swift         # 多屏模式
│       ├── HotkeyPane.swift          # 快捷键录制
│       └── AboutPane.swift           # 关于
└── Window/
    └── LaunchpadWindowController.swift # NSPanel 浮层窗口 + 键盘/滚轮监听
```

---

## 3. 架构设计

### 3.1 依赖方向（单向，无循环）

```
View → ViewModel(组合根+薄壳转发) → Controller → LaunchpadData(单一数据源)
                                      ↓
                                  Services
```

### 3.2 核心组件

| 组件 | 类型 | 职责 |
|------|------|------|
| `LaunchpadData` | `@Observable class` | 单一数据源：`allApps`, `layout`, `searchText`, `isEditMode`, `currentPageIndex`, `dragState`, `gridGeometry`(@ObservationIgnored), `pendingAppsRefresh`(@ObservationIgnored) |
| `LaunchpadViewModel` | `@Observable class` | 组合根：组合 `data` + 4 个 Controller，薄壳转发属性/方法 |
| `LayoutService` | `@Observable class` | 布局计算 + 应用扫描合并 + 持久化加载 |
| `SearchController` | `@Observable class` | 模糊搜索过滤 + 搜索结果 |
| `DragController` | `@Observable class` | 拖拽全生命周期（开始/更新/结束/边缘翻页/让位预览） |
| `NavigationController` | `@Observable class` | 键盘方向键导航 + 回车启动 |

**控制器之间互不引用**。新增功能放入对应 Controller，不要回塞根 VM。

### 3.3 @Observable 关键规则

- `gridGeometry` 标 `@ObservationIgnored`：在 GeometryReader 中写入会触发布局循环
- `pendingAppsRefresh` 标 `@ObservationIgnored`：仅作为延迟标志位，不需要 UI 观察
- 拖拽中频繁触发 body 重算（`@Observable` 特征）→ 手势闭包内的局部 `var` 会被重置 → **必须用 `@State` / `@GestureState` 跨重算保留状态**

---

## 4. 拖拽系统 — 核心子系统

拖拽是 AppLaunchpad 最复杂的子系统。以下是完整的设计和执行细节。

### 4.1 几何落点方案（替代 measured frame）

```
光标坐标 → GridGeometry.slotUnderCursor(location) → cursorSlot (Int)
```

- `GridGeometry` 存储网格原点、列数、行数、cellW、cellH、间距、iconSize
- `slotUnderCursor` 用 `(location - origin) / (cellW + hSpacing)` 求行列号 → `row * cols + col`
- `iconRect(forSlot:)` 返回槽位内图标 footprint，区分"压图标"和"间隙"
- **红线：绝对不用 measured frame / 快照 / 最近中心点推算落点**

### 4.2 网格固定尺寸约束（红线）

```swift
// GridPageView.iconCell — 每个格子必须固定为 cellW × cellH
ZStack { ... }
.frame(width: cellWidth, height: cellHeight)  // ← 必须！否则视觉格点与 GridGeometry 错位
```

**去掉这行 → 布局乱 / 不全屏 / 拖拽落点对不上。**

### 4.3 手势架构

所有拖拽手势**挂在 LaunchpadView 根 ZStack**，不挂回单个 app 或 GridPageView。

```
根 ZStack
  ├── .simultaneousGesture(globalDragGesture)   # 图标拖拽（minDistance: 5）
  └── .simultaneousGesture(pagingDragGesture)   # 翻页手势（minDistance: 30）
```

**仲裁逻辑**：`globalDragGesture` 用 `appAtIconPoint(startLocation)` 判断起点是否在图标上 → 在图标上则启动拖拽 → `pagingDragGesture` 的起点检查 `appAtIconPoint == nil` 放行翻页。

**勿挂回 GridPageView**：翻页时 items 变 → 手势取消 → 跨页卡死。

### 4.4 手势状态与 `@GestureState`（关键）

```swift
// LaunchpadView
@GestureState private var dragStart: (checked: Bool, bundleID: String?) = (false, nil)

var globalDragGesture: some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .global)
        .updating($dragStart) { value, state, _ in
            if !state.checked {
                state.checked = true
                if let bundleID = viewModel.appAtIconPoint(value.startLocation) {
                    state.bundleID = bundleID
                    if !viewModel.isEditMode { viewModel.enterEditMode() }
                    viewModel.beginDrag(bundleID: bundleID, ...)
                }
            }
            guard state.bundleID != nil else { return }
            viewModel.updateDragTarget(location: value.location)
        }
        .onEnded { value in
            // ⚠️ @GestureState 在 onEnded 调用前已被 SwiftUI 复位为初始值
            // 必须读 viewModel.dragState.draggedBundleID，不能读 dragStart.bundleID！
            guard viewModel.dragState.draggedBundleID != nil,
                  viewModel.dragState.isDragging else { return }
            viewModel.updateDragTarget(location: value.location)
            withAnimation(.easeOut(duration: 0.28)) {
                viewModel.endDrag()
            }
        }
}
```

**三条关键规则**：
1. `@GestureState dragStart.checked` 仅用于 `.updating` 内部防重复调用 `beginDrag`——它**不能**在 `.onEnded` 中读取（已被复位）
2. `.onEnded` 必须用 `viewModel.dragState.draggedBundleID` 判落主体责任
3. **绝对不能**在手势闭包内用局部 `var` 保存状态——`@Observable` 重算 body 会重建手势→局部变量丢失→`endDrag` 不执行

### 4.5 松手落点精度

```swift
.onEnded { value in
    viewModel.updateDragTarget(location: value.location)  // 重新计算 cursorSlot
    // ... endDrag 内再用 geo.slotUnderCursor(dragLocation) 兜底重算
}
```

**原因**：SwiftUI 不保证松手前再发一次 `onChanged`→最后一段位移会让 `cursorSlot` 落后一格。

### 4.6 make-way 让位机制

`DragController.pageItemsWithDrag(pageIndex:)` 返回视觉排列（让位预览数据源）：

```swift
if pageIndex == sourcePageIndex {
    // 源页：从 src 拔出 app，插到 cursorSlot → 其余 app 让位推开
    var items = layout.pages[pageIndex]
    let item = items.remove(at: src)
    items.insert(item, at: min(max(cursorSlot, 0), items.count))
    return items
} else if currentPageIndex == pageIndex {
    // 翻页后目标页：占位插入 cursorSlot → 目标页 app 让位
    var items = layout.pages[pageIndex]
    items.insert(.app(bundleID: draggedBundleID), at: min(max(cursorSlot, 0), items.count))
    return items
}
```

- **让位常驻、不弹回**：被拖 app 始终在 `cursorSlot`，其余 app 让开不归位
- **落点统一 `insert at to`**：不用 `to > src ? to - 1`（会导致偏左一格）
- 翻页后目标页也有让位效果（2026-07-24 修复）

### 4.7 边缘翻页

- Timer 必须加到 `.common` mode（拖拽中 RunLoop 在 tracking mode，`.default` 不 fire）
- `flipPageWhileDragging` 重置 `cursorSlot = sourceSlotIndex` 再翻页
- `stopEdgeScrollTimer()` 供 `exitEditMode` 调用

### 4.8 拖拽中禁止重建 layout.pages

`LayoutService.refreshApps` 检测 `isDragging` 时：
- 设置 `data.pendingAppsRefresh = true`
- 立即 return，不重建 `pages`（否则 `sourceSlotIndex`/`cursorSlot` 失效）
- `endDrag` 复位 `dragState` 后，若 `pendingAppsRefresh` 则补执行

### 4.9 松手落地动画

- **不使用**两阶段滑入动画（尝试过弹簧滑入 → 有过冲/V形轨迹 → 已回退）
- 当前使用 `.easeOut(duration: 0.28)`：浮动图标 `transition(.opacity)` 渐隐 + 格子图标入位
- `GridPageView` 用 `.animation(.spring(0.45, 0.8), value: items)` 弹簧重排
- 根视图 `.animation(.interactiveSpring(0.35, 0.82), value: isDragging)` 统一驱动让位回位

---

## 5. 搜索系统

- `SearchController.searchResults` 返回 `[AppInfo]`，按 `FuzzySearch.score` 降序
- `SearchController.isSearching` 绑定 `!searchText.isEmpty`
- 搜索结果网格用独立 `GridPageView`（一页展示所有结果，无分页）
- 键盘导航：`NavigationController.moveSearchSelection` 支持上下左右 + 回车启动

---

## 6. 键盘导航 / 滚动翻页

- `NavigationController` 处理方向键 + 回车 + ESC（退出搜索）
- `LaunchpadWindowController` 处理触控板/滚轮翻页（`scrollMonitor .local` + `phase` 累积）
- 键盘吞字：`keyDown` 追加 `searchText` 前先 `isTextInputFirstResponder()` 放行

---

## 7. 布局持久化

- `LayoutStore`（actor）原子读写 `~/Library/Application Support/AppLaunchpad/layout.json`
- 格式：`LayoutData { pages: [[LayoutItem]], folders: [String: FolderInfo], version: Int }`
- `folders` 字段运行时永远为空（兼容保留），`LayoutService.mergeLayout` 展开遗留 `.folder`
- `UserPreferences`（@Observable 单例）存在 `UserDefaults`，didSet 直接写盘
- App 信息（`AppInfo`）不持久化，每次启动重新扫描

---

## 8. 设置窗口

```swift
Window("设置", id: "settings")
// 入口：AppDelegate.openSettings() → settingsOpener → openWindow(id:)
// 绝对不用 showWindow: —— Dock 菜单下失效
```

- `NavigationSplitView` + `.listStyle(.sidebar)`
- 外观参数全进 `UserPreferences`：存储属性 + `didSet` 写 UserDefaults
- `0 = 自动`：透明度默认 0.10，行列数/间距/边距默认自动推算

---

## 9. 功能状态一览

| 功能 | 状态 | 备注 |
|------|------|------|
| 基本启动台展示 | ✅ 完成 | 多页网格、搜索、键盘导航 |
| 拖拽排序（同页） | ✅ 完成 | 几何落点 + make-way 让位 |
| 拖拽排序（跨页） | ✅ 完成 | 边缘翻页 + 目标页让位（2026-07-24） |
| 编辑模式 | ✅ 完成 | 长按进入、图标抖动、删除按钮 |
| 全局快捷键 | ✅ 完成 | HotkeyRecorder + Carbon Event |
| 多显示器 | ✅ 完成 | 主屏 / 鼠标所在屏 |
| 设置面板 | ✅ 完成 | 外观、显示器、快捷键、关于 |
| 触控板/滚轮翻页 | ✅ 完成 | phase 累积防误触 |
| FSEvents 自动刷新 | ✅ 完成 | 2s debounce + 拖拽中挂起 |
| 文件夹功能 | ❌ 已移除 | 数据骨架保留（`LayoutItem.folder`、`FolderInfo`），UI/手势已删 |
| 触摸板拖拽排序 | ❌ 未实现 | 当前仅支持鼠标拖拽 |

---

## 10. 文件夹功能（已移除—扩展点）

**保留的惰性骨架**：
- `LayoutItem.folder` 枚举项
- `LayoutData.folders: [String: FolderInfo]` 字典
- `FolderInfo` 类型

**运行时行为**：`LayoutService.mergeLayout` 展开遗留 `.folder` 为内部 app → `folders` 置空 → 永远不出现文件夹。

**未来恢复步骤**：
1. 重建 3 个文件：`FolderController.swift` / `FolderThumbnailView.swift` / `FolderExpandedView.swift`
2. `DragController` 加回 `folders` 依赖
3. `mergeLayout` 改回保留 `folders`
4. `endDrag` 加回 `folderHoverID` 归入分支
5. 数据格式 + 持久化层无需改动

---

## 11. 构建与开发工作流

### 11.1 编译命令

```bash
cd /Users/wangpenglong/projects/swift/macos/AppLaunchpad
xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad -configuration Debug build
```

### 11.2 新增/删除文件

```bash
# 1. 修改 project.yml 中的 sources
# 2. 运行
xcodegen generate
# 3. 重新编译
xcodebuild ... build
```

### 11.3 签名与 TCC 权限

- `project.yml` 固化：Manual + Apple Development + TEAM `2VU69Q9CGK`
- **勿用 ad-hoc 签名**：designated requirement 含二进制哈希 → 重编译后 TCC 失效
- 残留授权清理：`tccutil reset Accessibility com.applaunchpad.app` 后重授权一次

### 11.4 运行应用

```bash
# 从终端启动（可捕获 print 输出）
/Users/wangpenglong/Library/Developer/Xcode/DerivedData/AppLaunchpad-*/Build/Products/Debug/AppLaunchpad.app/Contents/MacOS/AppLaunchpad

# 或用 open（普通启动）
open /Users/wangpenglong/Library/Developer/Xcode/DerivedData/AppLaunchpad-*/Build/Products/Debug/AppLaunchpad.app

# 杀旧进程
pkill -f "AppLaunchpad.app/Contents/MacOS/AppLaunchpad"
```

---

## 12. 编码规范与常见陷阱

### 12.1 Swift 6 专属

```swift
// ❌ 成员初始化器不含带默认值的存储属性
struct S { let a: Int; let b: Int = 0 }
S(a: 1, b: 2)  // 编译错误！

// ✅ 去掉默认值或显式写 init
struct S { let a: Int; let b: Int }
```

```swift
// ❌ NSEvent.Phase 是 OptionSet
event.momentumPhase == .none  // 错误！

// ✅
event.momentumPhase.isEmpty
```

### 12.2 @Observable 陷阱

```swift
// ❌ 计算属性 + didSet：@Observable 不观察计算属性
var value: Int {
    didSet { UserDefaults.standard.set(value, forKey: "value") }  // 不触发！
}

// ✅ 存储属性 + didSet
var value: Int = 0 {
    didSet { UserDefaults.standard.set(value, forKey: "value") }
}
```

### 12.3 @GestureState 陷阱

```swift
// ❌ onEnded 中读取 @GestureState
@GestureState var state = false
// .onEnded { state 已被复位为 false！}

// ✅ onEnded 中读 ViewModel 的状态
viewModel.dragState.draggedBundleID
```

### 12.4 Timer 陷阱

```swift
// ❌ default mode Timer 在拖拽中不 fire
Timer.scheduledTimer(...)

// ✅ 必须 .common mode
let timer = Timer(timeInterval: 0.8, repeats: false) { ... }
RunLoop.main.add(timer, forMode: .common)
```

### 12.5 GeometryReader 陷阱

```swift
// ❌ GeometryReader 中写 @Observable 属性 → 死循环
viewModel.gridGeometry = GridGeometry(...)  // 如果 gridGeometry 是 @Observable

// ✅ 标 @ObservationIgnored
@ObservationIgnored var gridGeometry: GridGeometry?
```

### 12.6 Dock 菜单陷阱

```swift
// ❌ Dock 菜单下 showWindow: 不工作
windowController.showWindow(nil)

// ✅ 使用 openWindow(id:)
NSApp.sendAction(Selector(("openSettings")), to: nil, from: nil)
```

---

## 13. 关键代码索引

需修改特定功能时，按以下索引定位：

| 需求 | 文件 | 关键方法/属性 |
|------|------|-------------|
| 修改拖拽落点逻辑 | `DragController.swift` | `updateDragTarget`, `endDrag`, `pageItemsWithDrag` |
| 修改网格几何 | `GridGeometry.swift` | `slotUnderCursor`, `iconRect` |
| 修改网格渲染 | `GridPageView.swift` | `body`, `iconCell` |
| 修改手势行为 | `LaunchpadView.swift` | `globalDragGesture`, `pagingDragGesture` |
| 修改让位动画 | `GridPageView.swift` L56 | `.animation(.spring, value: items)` |
| 修改落地动画 | `LaunchpadView.swift` L191 | `withAnimation(.easeOut) { endDrag() }` |
| 修改搜索行为 | `SearchController.swift` | `searchResults`, `FuzzySearch.swift` |
| 修改布局持久化 | `LayoutStore.swift` | `save`, `load` |
| 修改设置项 | `UserPreferences.swift` | 对应存储属性 + `AppearancePane.swift` |
| 添加新 Controller | `LaunchpadViewModel.swift` | `init()` 注入 + 薄壳转发 |
| 修改边缘翻页 | `DragController.swift` | `detectEdgeScroll`, `flipPageWhileDragging` |
| 修改拖拽中刷新挂起 | `LayoutService.swift` | `refreshApps` 的 `pendingAppsRefresh` 分支 |

---

## 14. 最近的重大修改（2026-07-20 ~ 07-24）

### 模块化重构（07-22）
- 巨型 `LaunchpadViewModel` → `LaunchpadData` + 4 个 Controller
- View 层零改动

### 拖拽系统重写（07-23）
- 几何落点方案取代 measured frame
- `GridPageView.iconCell` 固定 `cellW × cellH`
- `@GestureState` 取代手势闭包局部 `var`
- make-way 常驻不弹回
- `.animation(value: items)` 取代 `value: cursorSlot`

### 文件夹移除（07-23）
- UI/手势/Controller 全部移除
- 数据骨架保留为扩展点

### @GestureState 复位时序 bug（07-23）
- 发现 `@GestureState` 在 `onEnded` 调用前已被复位
- `onEnded` 改读 `viewModel.dragState.draggedBundleID`

### 落地动画迭代（07-23 ~ 07-24）
- 尝试两阶段弹簧滑入 → 有过冲/V形轨迹 → 已回退
- 当前方案：`easeOut 0.28s` + `transition(.opacity)` 纯融合

### 跨页让位修复（07-24）
- `pageItemsWithDrag` guard 移除 `sourcePageIndex == pageIndex` 限制
- 翻页后目标页也有 make-way 效果

---

## 15. 修改原则（给 AI 助手）

1. **先读本文档**，再读相关代码，最后修改
2. **修改后必须编译**：`xcodebuild ... build`
3. **新增 .swift 文件后必须 `xcodegen generate`**
4. **落点逻辑只走 `GridGeometry`**，不用 measured frame/快照
5. **Controller 之间互不引用**，新功能进对应 Controller
6. **手势状态不放闭包局部 `var`**，用 `@State`/`@GestureState`/ViewModel
7. **修改完记录到** `.workbuddy/memory/YYYY-MM-DD.md`
8. **涉及 `@Observable` 循环的风险时**：标 `@ObservationIgnored`
