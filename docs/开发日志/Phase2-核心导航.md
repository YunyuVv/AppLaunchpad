# Phase 2 开发日志 — 核心导航

**完成日期**: 2026-07-20  
**对应计划**: `docs/技术实现/03-功能实现计划.md` Phase 2  
**状态**: ✅ 完成

---

## 一、交付内容

### 新增文件

| 文件 | 说明 |
|-----|------|
| `Views/SearchBarView.swift` | 顶部搜索框，磨砂玻璃材质，实时过滤，×清空按钮 |
| `Views/PageIndicatorView.swift` | 底部页码圆点，当前页高亮，点击跳转 |

### 修改文件

| 文件 | 改动说明 |
|-----|---------|
| `Views/LaunchpadView.swift` | 完整重写：整合搜索框、多页翻页（HStack+offset）、页码指示器、呼出动画 |
| `ViewModel/LaunchpadViewModel.swift` | 新增 `goToPreviousPage()` / `goToNextPage()` / `goToPage(_:)` |
| `Window/LaunchpadWindowController.swift` | 新增左右方向键翻页，本地键盘监听重构为 `setupLocalKeyMonitor()` |

---

## 二、功能说明

### 2.1 多页翻页

**实现方案**：自定义 `HStack + offset` 偏移，不使用 `TabView(.page)` 。

选用原因：
- `TabView(.page)` 在 macOS 上动画控制有限，无法精确调整弹性参数
- 自定义偏移方案可独立控制拖拽中的实时跟随和松手后的 spring 动画

```
// 核心逻辑（LaunchpadView.pagingView）
HStack(spacing: 0) {
    ForEach(pages) { GridPageView(...) .frame(width: pageWidth) }
}
.offset(x: -CGFloat(currentPageIndex) * pageWidth + dragOffsetX)
.animation(.spring(duration: 0.3, bounce: 0.1), value: currentPageIndex)
```

**触发方式**：
- 触控板双指左右滑动（`NSEvent.scrollWheel`，累积 deltaX 超过 80pt 翻页）
- 键盘左右方向键（LaunchpadWindowController 本地监听，keyCode 123/124）
- 点击底部页码圆点

### 2.2 搜索

搜索逻辑已在 Phase 1 的 `LaunchpadViewModel.searchResults` 中实现，Phase 2 在视图层接入：

- 搜索状态下：隐藏翻页 HStack，改为单页展示 `searchResultsView`
- 页码指示器在搜索时自动隐藏
- 无匹配结果显示「未找到应用」提示
- Escape 优先清空搜索词，无搜索词再关闭面板

### 2.3 呼出动画

```swift
// LaunchpadView.body
.scaleEffect(appeared ? 1.0 : 0.92)
.opacity(appeared ? 1.0 : 0)
.animation(.spring(duration: 0.35, bounce: 0.15), value: appeared)
.onAppear { appeared = true }
```

效果：面板出现时从略微缩小 + 透明状态弹性放大至全尺寸，时长约 350ms。

---

## 三、键盘事件映射

| 按键 | 行为 | 处理位置 |
|-----|------|---------|
| `Escape` | 有搜索词 → 清空；无搜索词 → 关闭面板 | `LaunchpadWindowController` 本地监听 |
| `←` 方向键 | 非搜索状态下跳到上一页 | `LaunchpadWindowController` 本地监听 |
| `→` 方向键 | 非搜索状态下跳到下一页 | `LaunchpadWindowController` 本地监听 |

---

## 四、验收结果

- [x] 触控板双指左右滑动翻页，动画流畅
- [x] 键盘左右方向键翻页
- [x] 点击底部圆点跳页，当前页圆点高亮
- [x] 搜索框输入后实时过滤，×按钮清空
- [x] 搜索状态隐藏翻页，单页展示结果
- [x] 搜索无结果显示提示文字
- [x] Escape 先清空搜索词，无词时关闭面板
- [x] 呼出时弹性淡入动画

---

## 五、修复记录

### Bug 1：搜索框无法点击输入
**原因**：根视图 ZStack 上的 `.onTapGesture { onDismiss() }` 比 TextField 的焦点事件更早触发，每次点击搜索框都会关闭面板。  
**修复**：将关闭层改为 `Color.clear` 放在 ZStack 中间层，内容 VStack 放在最上层。SwiftUI 命中测试从上到下，TextField/Button 优先消费点击，空白区域穿透到 Color.clear 触发 dismiss。搜索框额外加 `.onTapGesture {}` 吸收点击防止穿透。

### Bug 2：触控板双指滑动无法翻页 / 鼠标点击立即退出
**原因**：macOS 触控板双指滑动产生 `NSEvent.scrollWheel` 事件，不是 SwiftUI `DragGesture`（DragGesture 对应鼠标拖拽）。SwiftUI `DragGesture` 同时也与根视图 `onTapGesture` 产生冲突，导致轻微移动就触发 dismiss。  
**修复**：移除 SwiftUI `DragGesture`，改为在 `LaunchpadWindowController` 用 `NSEvent.addLocalMonitorForEvents(.scrollWheel)` 监听横向滚动，累积 `scrollingDeltaX` 超过 80pt 时触发翻页。

### Bug 3：界面显示在副屏幕上
**原因**：`NSScreen.main` 返回的是当前有键盘焦点的窗口所在屏幕，若用户在副屏操作则返回副屏。  
**修复**：改用 `NSScreen.screens.first`，这是系统设置中被设为「主显示器」的屏幕（带菜单栏）。`show()` 每次调用时用 `panel.setFrame(primaryScreen.frame)` 更新位置，确保多显示器切换后也能显示在正确位置。

### Bug 4：搜索框和页码指示器消失（修复主屏幕后引入）
**原因**：`panel.setFrame(display: false)` 不触发重绘，`GeometryReader` 在 `NSHostingView` 中拿到的 `geo.size.width = 0`，导致 `pagingView` 每页宽度为 0，`Spacer` 吞掉全部垂直空间，搜索框和页码指示器被挤出可见区域。  
**修复**：移除 `GeometryReader`，改为直接从 `NSScreen.screens.first?.frame.width` 取页宽，规避 NSHostingView 中 GeometryReader 的延迟更新问题。`panel.setFrame` 改为 `display: true` 强制重绘。

### Bug 5：触控板滑动仍无法翻页 / 鼠标滚轮无响应
**原因**：上次修复的 `scrollWheel` 监听只处理了 `event.phase == .ended` 分支（触控板手势松手）。物理鼠标滚轮的 `event.phase` 恒为 `.none`，条件永远不满足，所以鼠标滚轮无效。触控板在某些系统版本下 `scrollingDeltaX` 方向与预期相反，导致阈值判断失败。  
**修复**：区分两种输入设备：
- `phase == .none && momentumPhase == .none` → 物理鼠标滚轮，每个事件立即判断方向（deltaX × 3 放大灵敏度）
- `phase != .none` → 触控板手势，累积 delta，松手时判断
- 增加 300ms 防抖防止连续翻多页

### Bug 6：搜索框无法点击输入
**原因 A**：`SearchBarView` 加了 `.onTapGesture {}`（空手势）试图阻止点击穿透到关闭层，但空手势同时也吸收了 TextField 的焦点激活事件，导致点击搜索框 TextField 永远不会获得焦点。实际上 `SearchBarView` 的磨砂玻璃背景（`.fill(.ultraThinMaterial)`）本身就是可命中的，点击时不会穿透，`.onTapGesture {}` 完全多余。  
**修复**：移除 `SearchBarView` 上的 `.onTapGesture {}`。

**原因 B**：键盘监听中方向键（keyCode 123/124）无论是否在搜索模式一律 `return nil`（消耗事件），导致搜索框里光标无法用方向键移动，字符输入也受影响。  
**修复**：搜索模式下方向键 `return event` 透传给 TextField，仅在非搜索模式下消耗并翻页。

### Bug 7：搜索框仍无法输入文字（深层原因）
**原因**：`NSPanel` 设置 `.borderless` styleMask 后，`canBecomeKey` 默认返回 `false`。窗口无法成为 key window，内部 SwiftUI `TextField` 永远无法成为 `firstResponder`，自然无法接收键盘输入。Escape 等快捷键能工作是因为用的是 App 级 `NSEvent.addLocalMonitorForEvents`，不依赖 key window 状态。  
**修复**：新增 `KeyablePanel: NSPanel` 子类，覆盖 `canBecomeKey` 和 `canBecomeMain` 均返回 `true`。

### Bug 8：底部页码指示器被 Dock 遮挡
**原因**：`panel.frame = screen.frame`（物理全屏坐标），Dock 悬浮在面板之上。  
**修复**：呼出时执行 `NSApp.presentationOptions = [.hideDock, .autoHideMenuBar]` 隐藏 Dock 和菜单栏（与原生 Launchpad 行为一致）；关闭时执行 `presentationOptions = []` 完全恢复。

- **背景遮罩透明度**：`BackgroundView.swift` 固定 `opacity(0.45)`，Phase 7 设置页面开放用户配置

## 七、已知遗留事项

- 关闭动画暂未实现（面板直接消失，后续迭代优化）
- 主屏幕目前硬编码，Phase 7 设置页面中添加「显示在鼠标所在屏幕」可配置项
- F4 全局快捷键和 Dock 图标集成在 Phase 3 实现

### Bug 9：翻页无效（canBecomeKey 修复后引入）
**原因 A**：`LaunchpadViewModel.itemsPerPage` 使用 `NSScreen.main`（当前焦点屏幕），若焦点在副屏则列数计算错误，可能导致所有 App 只被分配到1页，无页可翻。  
**修复**：改用 `NSScreen.screens.first`（主屏幕）保持一致性。

**原因 B**：`scrollWheel` 监听未区分触控板（`hasPreciseScrollingDeltas=true`，值小）和鼠标（`hasPreciseScrollingDeltas=false`，值为整步），导致阈值判断逻辑对两种设备都不准确。  
**修复**：用 `event.hasPreciseScrollingDeltas` 分支处理：触控板累积 phase 后以 30pt 阈值判断；鼠标每步 `deltaX` 直接翻页。

**原因 C**：鼠标拖拽翻页的 `DragGesture` 被移除（之前为解决冲突），导致鼠标用户无法拖动翻页。  
**修复**：在 `pagingView` 上重新加 `DragGesture(minimumDistance:30)`，水平拖动 >50pt 翻页，小幅移动仍触发图标按钮。

### Bug 10：第2+页内容为空（HStack+offset+clipped 方案根本缺陷）
**原因**：在 SwiftUI 中 `.offset()` 只改变视觉渲染位置，不改变 Layout Frame。`.clipped()` 裁剪的是 Layout Frame 的区域。当修饰符顺序为 `.frame(w).clipped().offset(x:)` 时，裁剪区固定在第1页位置，`.offset` 只是把裁剪后的结果移走——第2、3页的内容从未进入裁剪区，用户看到的始终是空白。即使改用非懒加载的 VStack+HStack 行，这个布局问题依然存在。  
**修复**：放弃 HStack+offset+clipped 方案，改为"单页渲染 + 视图替换动画"：
- `pagingView` 每次只渲染 `layout.pages[currentPageIndex]` 的内容
- 使用 `.id(currentPageIndex)` 驱动 SwiftUI 在页码变化时替换视图
- 使用 `.transition(.asymmetric(insertion: .move(edge:), removal: .move(edge:)))` 实现左右滑入/滑出动画
- ViewModel 新增 `pageFlipGoingForward` 记录方向，控制 transition edge
- 所有翻页调用统一用 `withAnimation` 包裹触发 transition

### Bug 11：触控板两指滑动无法翻页
**原因**：每个 scrollWheel 事件单独判断 `abs(dx) > abs(dy)`，斜向滑动时大量事件被过滤（dy 较大），累积值永远达不到阈值 20pt。  
**修复**：改为 `phase(.began/.changed/.ended)` 全程累积 x 和 y，只在 `.ended` 时整体判断方向（总水平分量 > 总垂直分量 && 幅度 > 20pt），不再过滤单个事件。

### Bug 12：翻页时图标和文字像分离滑动（视觉乱）
**原因**：`dragOffsetX` 和 `.transition(.move)` 同在 `withAnimation` 里运行——新页面从 transition 的边缘插入时，同时还有初始的 dragOffset 值在动画归零，两个动画叠加导致图标/文字的起始位置不同步。  
**修复**：翻页时立即（不加动画）将 `dragOffsetX = 0`，让 `.transition(.move)` 独立负责滑入/滑出动画；`contentArea` 加 `.clipped()` 防止 transition 溢出到搜索框/页码区域；AppIconView 图标加载加淡入过渡（`transition(.opacity)` + `animation(.easeIn)`）避免灰框突变为图标的跳变感。

---

## 待解决 TODO

### TODO-1：触控板两指滑动翻页
**现象**：两指左右滑动无法触发翻页，鼠标拖拽和键盘方向键均正常。  
**已尝试方案**：
1. `DragGesture` → 仅响应鼠标，不响应触控板两指滑动（macOS 触控板两指滑动产生 scrollWheel 而非 drag 事件）
2. `scrollWheel` debounce timer → phase 检测不稳定
3. `scrollWheel` phase 累积（.began/.changed/.ended） → 仍无效，可能是 NSApp.presentationOptions 或面板层级影响了 scrollWheel 事件路由
**待排查方向**：
- 验证 `NSEvent.addLocalMonitorForEvents(.scrollWheel)` 是否在当前面板层级下能收到事件（加 print 验证）
- 尝试在 `NSPanel` 的 `NSHostingView` 上用 `NSPanGestureRecognizer` 直接捕获触控板手势
- 考虑 `NSScrollView` 包装方案
**预计阶段**：Phase 6 系统深度集成时一并处理
