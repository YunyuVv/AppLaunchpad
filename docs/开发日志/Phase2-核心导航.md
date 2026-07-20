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
