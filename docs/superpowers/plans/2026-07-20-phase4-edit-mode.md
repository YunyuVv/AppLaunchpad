# Phase 4 实现计划 — 编辑模式与图标拖拽排序

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现长按进入编辑模式、图标抖动、单页内拖拽排序、布局持久化，MAS 应用显示删除按钮。

**Architecture:** 在 ViewModel 层管理 `isEditMode` 和 `DragState`，`LayoutStore` 负责 JSON 持久化。视图层通过 `WobbleModifier` 实现抖动，`AppIconView` 响应长按/拖拽手势，`GridPageView` 在拖拽时动态重排其余图标位置。

**Tech Stack:** Swift 6 · SwiftUI · AppKit · Codable JSON · macOS 26+

## Global Constraints

- 不引入第三方依赖
- 所有 UI 更新在 @MainActor
- 持久化路径：`~/Library/Application Support/AppLaunchpad/layout.json`
- 长按阈值：0.5 秒
- 拖拽仅支持单页内排序（跨页拖拽在 Phase 4 不实现，留 TODO）
- Bundle ID：com.applaunchpad.app

---

## Task 1：LayoutStore 持久化

**Files:**
- Create: `AppLaunchpad/Persistence/LayoutStore.swift`

**Interfaces:**
- Produces:
  - `actor LayoutStore`
  - `static let shared: LayoutStore`
  - `func save(_ layout: LayoutData) async`
  - `func load() async -> LayoutData?`

- [ ] **Step 1: 创建 LayoutStore**

```swift
// AppLaunchpad/Persistence/LayoutStore.swift
import Foundation

/// 将 LayoutData 以 JSON 格式持久化到本地
actor LayoutStore {
    static let shared = LayoutStore()

    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("AppLaunchpad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }

    func save(_ layout: LayoutData) async {
        do {
            let data = try JSONEncoder().encode(layout)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[LayoutStore] 保存失败: \(error)")
        }
    }

    func load() async -> LayoutData? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LayoutData.self, from: data)
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add AppLaunchpad/Persistence/LayoutStore.swift AppLaunchpad.xcodeproj
git commit -m "feat: LayoutStore JSON 持久化"
```

---

## Task 2：ViewModel 接入持久化 + DragState

**Files:**
- Modify: `AppLaunchpad/ViewModel/LaunchpadViewModel.swift`
- Create: `AppLaunchpad/Models/DragState.swift`

**Interfaces:**
- Produces:
  - `struct DragState` — isDragging, draggedBundleID, sourceIndex, targetIndex, location
  - `LaunchpadViewModel.dragState: DragState`
  - `LaunchpadViewModel.loadApps()` — 先读本地布局，再合并扫描结果
  - `LaunchpadViewModel.saveLayout()` — 异步写入 LayoutStore

- [ ] **Step 1: 创建 DragState**

```swift
// AppLaunchpad/Models/DragState.swift
import Foundation

/// 图标拖拽过程中的实时状态
struct DragState {
    var isDragging: Bool = false
    var draggedBundleID: String = ""  // 被拖拽图标的 bundleID
    var sourcePageIndex: Int = 0
    var sourceSlotIndex: Int = 0
    var targetSlotIndex: Int = 0      // 实时计算的目标槽位

    var isEmpty: Bool { !isDragging }
}
```

- [ ] **Step 2: 更新 ViewModel**

在 `LaunchpadViewModel` 中新增：
```swift
// 新增属性
var dragState: DragState = DragState()

// loadApps() 中先读本地布局
func loadApps() async {
    let scanned = await AppScanner.shared.scan()
    allApps = scanned

    if let saved = await LayoutStore.shared.load() {
        // 合并：保留已有布局，追加新 App，移除已卸载 App
        layout = mergeLayout(saved: saved, scanned: scanned)
    } else {
        layout = LayoutData.initial(from: scanned, itemsPerPage: itemsPerPage)
    }
}

// 合并布局：保留顺序，追加新 app 到末页
private func mergeLayout(saved: LayoutData, scanned: [AppInfo]) -> LayoutData {
    let scannedIDs = Set(scanned.map(\.bundleID))
    var pages = saved.pages.map { page in
        page.filter { item in
            if case .app(let id) = item { return scannedIDs.contains(id) }
            return true  // 保留文件夹
        }
    }.filter { !$0.isEmpty }

    let existingIDs = Set(pages.flatMap { $0 }.compactMap {
        if case .app(let id) = $0 { return id }
        return nil
    })
    let newItems = scanned
        .filter { !existingIDs.contains($0.bundleID) }
        .map { LayoutItem.app(bundleID: $0.bundleID) }

    if !newItems.isEmpty {
        var last = pages.last ?? []
        for item in newItems {
            if last.count < itemsPerPage { last.append(item) }
            else { pages.append(last); last = [item] }
        }
        if !last.isEmpty {
            if pages.isEmpty { pages = [last] }
            else { pages[pages.count - 1] = last }
        }
    }
    return LayoutData(pages: pages.isEmpty ? [newItems] : pages)
}

// 异步保存布局
func saveLayout() {
    let current = layout
    Task.detached { await LayoutStore.shared.save(current) }
}
```

- [ ] **Step 3: 提交**

```bash
git add AppLaunchpad/Models/DragState.swift AppLaunchpad/ViewModel/LaunchpadViewModel.swift
git commit -m "feat: DragState + LayoutStore 合并布局逻辑"
```

---

## Task 3：编辑模式 + 图标抖动

**Files:**
- Create: `AppLaunchpad/Views/WobbleModifier.swift`
- Modify: `AppLaunchpad/Views/AppIconView.swift`
- Modify: `AppLaunchpad/ViewModel/LaunchpadViewModel.swift`

**Interfaces:**
- Produces:
  - `struct WobbleModifier: ViewModifier` — 随机相位抖动动画
  - `AppIconView` 支持 `isEditMode` 参数，长按触发进入编辑模式
  - `LaunchpadViewModel.enterEditMode()` / `exitEditMode()`

- [ ] **Step 1: 创建 WobbleModifier**

```swift
// AppLaunchpad/Views/WobbleModifier.swift
import SwiftUI

/// 图标编辑模式抖动动画，每个图标随机相位防止同步摆动
struct WobbleModifier: ViewModifier {
    let isWobbling: Bool
    @State private var angle: Double = 0
    private let amplitude: Double = 2.2
    private let duration: Double

    init(isWobbling: Bool) {
        self.isWobbling = isWobbling
        self.duration = Double.random(in: 0.10...0.13)
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isWobbling ? angle : 0))
            .onChange(of: isWobbling) { _, wobble in
                if wobble {
                    let delay = Double.random(in: 0...0.25)
                    withAnimation(
                        .easeInOut(duration: duration)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                    ) { angle = amplitude }
                } else {
                    withAnimation(.easeOut(duration: 0.1)) { angle = 0 }
                }
            }
            .onAppear {
                if isWobbling {
                    let delay = Double.random(in: 0...0.25)
                    withAnimation(
                        .easeInOut(duration: duration)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                    ) { angle = amplitude }
                }
            }
    }
}

extension View {
    func wobble(_ isWobbling: Bool) -> some View {
        modifier(WobbleModifier(isWobbling: isWobbling))
    }
}
```

- [ ] **Step 2: ViewModel 新增编辑模式方法**

```swift
// 在 LaunchpadViewModel 中新增
func enterEditMode() {
    isEditMode = true
}

func exitEditMode() {
    isEditMode = false
}
```

- [ ] **Step 3: 更新 AppIconView 支持编辑模式和长按**

```swift
// AppLaunchpad/Views/AppIconView.swift
struct AppIconView: View {
    let app: AppInfo
    let isEditMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void        // 触发进入编辑模式
    let onDelete: (() -> Void)?        // MAS 应用才有

    @State private var icon: NSImage? = nil
    @State private var isHovering: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: { if !isEditMode { onTap() } }) {
                VStack(spacing: 6) {
                    iconImage
                        .frame(width: 80, height: 80)
                        .scaleEffect(isHovering && !isEditMode ? 1.08 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: isHovering)
                    Text(app.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                }
                .frame(width: 100)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .onLongPressGesture(minimumDuration: 0.5) {
                onLongPress()
            }
            .wobble(isEditMode)
            .task(id: app.id) {
                icon = await IconCache.shared.icon(for: app)
            }
            .animation(.easeIn(duration: 0.15), value: icon != nil)

            // MAS 应用删除按钮（仅编辑模式显示）
            if isEditMode, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: isEditMode)
    }

    @ViewBuilder
    private var iconImage: some View {
        if let icon {
            Image(nsImage: icon).resizable()
                .interpolation(.high).antialiased(true)
                .transition(.opacity)
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.12))
                .transition(.opacity)
        }
    }
}
```

- [ ] **Step 4: 更新 GridPageView 传递编辑模式参数**

```swift
// GridPageView 新增参数
let isEditMode: Bool
let onLongPress: () -> Void
let onDeleteApp: ((AppInfo) -> Void)?

// itemView 调用 AppIconView 时传入
AppIconView(
    app: app,
    isEditMode: isEditMode,
    onTap: { onTapApp(app) },
    onLongPress: onLongPress,
    onDelete: app.isMASApp ? { onDeleteApp?(app) } : nil
)
```

- [ ] **Step 5: 更新 LaunchpadView 中的 GridPageView 调用**

```swift
GridPageView(
    items: pageItems,
    apps: viewModel.allApps,
    columns: cols,
    isEditMode: viewModel.isEditMode,
    onTapApp: { viewModel.launch($0) },
    onLongPress: { viewModel.enterEditMode() },
    onDeleteApp: { app in /* Phase 4.9 */ }
)
```

- [ ] **Step 6: 编译验证**

```bash
xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：BUILD SUCCEEDED

- [ ] **Step 7: 提交**

```bash
git add AppLaunchpad/Views/WobbleModifier.swift \
        AppLaunchpad/Views/AppIconView.swift \
        AppLaunchpad/Views/GridPageView.swift \
        AppLaunchpad/Views/LaunchpadView.swift \
        AppLaunchpad/ViewModel/LaunchpadViewModel.swift
git commit -m "feat: 编辑模式 - 长按进入，图标抖动，MAS 应用删除按钮"
```

---

## Task 4：图标拖拽排序（单页内）

**Files:**
- Modify: `AppLaunchpad/Views/GridPageView.swift`
- Modify: `AppLaunchpad/ViewModel/LaunchpadViewModel.swift`

**Interfaces:**
- Produces:
  - `LaunchpadViewModel.beginDrag(bundleID:pageIndex:slotIndex:)`
  - `LaunchpadViewModel.updateDragTarget(slotIndex:)`
  - `LaunchpadViewModel.endDrag()`
  - `GridPageView` 支持拖拽排序

- [ ] **Step 1: ViewModel 新增拖拽方法**

```swift
// 在 LaunchpadViewModel 中新增

func beginDrag(bundleID: String, pageIndex: Int, slotIndex: Int) {
    dragState = DragState(
        isDragging: true,
        draggedBundleID: bundleID,
        sourcePageIndex: pageIndex,
        sourceSlotIndex: slotIndex,
        targetSlotIndex: slotIndex
    )
}

func updateDragTarget(slotIndex: Int) {
    guard dragState.isDragging else { return }
    dragState.targetSlotIndex = slotIndex
}

func endDrag() {
    guard dragState.isDragging else { return }
    let src = dragState.sourceSlotIndex
    let dst = dragState.targetSlotIndex
    let page = dragState.sourcePageIndex

    if src != dst, page < layout.pages.count {
        var items = layout.pages[page]
        let item = items.remove(at: src)
        let insertAt = dst < items.count ? dst : items.count
        items.insert(item, at: insertAt)
        layout.pages[page] = items
        saveLayout()
    }
    dragState = DragState()
}

/// 计算拖拽时的显示顺序（其他图标让位）
func pageItemsWithDrag(pageIndex: Int) -> [LayoutItem] {
    guard dragState.isDragging, dragState.sourcePageIndex == pageIndex,
          pageIndex < layout.pages.count else {
        return pageIndex < layout.pages.count ? layout.pages[pageIndex] : []
    }
    var items = layout.pages[pageIndex]
    let src = dragState.sourceSlotIndex
    let dst = dragState.targetSlotIndex
    guard src < items.count else { return items }
    let item = items.remove(at: src)
    let insertAt = min(dst, items.count)
    items.insert(item, at: insertAt)
    return items
}
```

- [ ] **Step 2: GridPageView 实现拖拽**

```swift
// GridPageView 改造：每个图标支持拖拽手势
// 使用 @State 追踪拖拽位置和 dragOffset

struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]
    let columns: Int
    let pageIndex: Int
    let isEditMode: Bool
    let onTapApp: (AppInfo) -> Void
    let onLongPress: () -> Void
    let onDeleteApp: ((AppInfo) -> Void)?
    let onDragUpdate: (Int, CGPoint) -> Void   // (slotIndex, location)
    let onDragEnd: () -> Void
    let dragState: DragState

    // 每个槽位的 frame，通过 PreferenceKey 收集
    @State private var slotFrames: [Int: CGRect] = [:]

    var body: some View {
        let rows = items.chunked(into: columns)
        return VStack(spacing: 30) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, rowItems in
                HStack(spacing: 20) {
                    ForEach(Array(rowItems.enumerated()), id: \.offset) { colIdx, item in
                        let slotIdx = rowIdx * columns + colIdx
                        itemView(for: item, slotIndex: slotIdx)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: SlotFrameKey.self,
                                        value: [slotIdx: geo.frame(in: .global)]
                                    )
                                }
                            )
                            .scaleEffect(dragState.isDragging && dragState.draggedBundleID == bundleID(item) ? 1.15 : 1.0)
                            .zIndex(dragState.isDragging && dragState.draggedBundleID == bundleID(item) ? 1 : 0)
                            .animation(.spring(duration: 0.2), value: dragState.targetSlotIndex)
                    }
                    // 补齐最后一行
                    ForEach(0..<(columns - rowItems.count), id: \.self) { _ in
                        Color.clear.frame(width: 100)
                    }
                }
            }
        }
        .padding(.horizontal, 60)
        .onPreferenceChange(SlotFrameKey.self) { slotFrames = $0 }
        .gesture(isEditMode ? dragGesture : nil)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                // 找到最近的槽位
                let loc = value.location
                if let nearest = nearestSlot(to: loc) {
                    onDragUpdate(nearest, loc)
                }
            }
            .onEnded { _ in onDragEnd() }
    }

    private func nearestSlot(to point: CGPoint) -> Int? {
        slotFrames.min { a, b in
            let da = hypot(a.value.midX - point.x, a.value.midY - point.y)
            let db = hypot(b.value.midX - point.x, b.value.midY - point.y)
            return da < db
        }?.key
    }

    private func bundleID(_ item: LayoutItem) -> String {
        if case .app(let id) = item { return id }
        return ""
    }
}

/// PreferenceKey：收集各槽位的全局 frame
private struct SlotFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
```

- [ ] **Step 3: 编译验证 + 提交**

```bash
xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
git add AppLaunchpad/Views/GridPageView.swift AppLaunchpad/ViewModel/LaunchpadViewModel.swift
git commit -m "feat: 图标拖拽排序（单页内）"
```

---

## Task 5：退出编辑模式 + 验收

**Files:**
- Modify: `AppLaunchpad/Window/LaunchpadWindowController.swift`
- Modify: `AppLaunchpad/Views/LaunchpadView.swift`

- [ ] **Step 1: Escape 键在编辑模式优先退出编辑（而非关闭面板）**

```swift
// LaunchpadWindowController.setupKeyMonitor 中
case 53: // Escape
    if viewModel.isEditMode {
        viewModel.exitEditMode()      // 先退出编辑模式
    } else if !viewModel.searchText.isEmpty {
        viewModel.searchText = ""
    } else {
        hide()
    }
    return nil
```

- [ ] **Step 2: 点击背景退出编辑模式**

```swift
// LaunchpadView 的背景关闭层
Color.clear
    .contentShape(Rectangle())
    .onTapGesture {
        if viewModel.isEditMode {
            viewModel.exitEditMode()  // 编辑模式下点背景只退出编辑，不关闭面板
        } else {
            onDismiss()
        }
    }
```

- [ ] **Step 3: 面板关闭时自动退出编辑模式（hide 里已调用 viewModel.hide() → isEditMode=false，已满足）**

- [ ] **Step 4: 验收**

运行后验证：
- [ ] 长按任意图标 0.5s → 所有图标开始抖动（随机相位）
- [ ] MAS 应用左上角显示 × 按钮
- [ ] 拖拽图标到其他位置松开 → 顺序变化 + 弹性动画
- [ ] 重启 App → 排列顺序保留（LayoutStore 持久化）
- [ ] Escape 键 → 先退出编辑模式（不关闭面板）
- [ ] 再次 Escape → 关闭面板
- [ ] 点击空白区域 → 退出编辑模式

- [ ] **Step 5: 提交**

```bash
git add AppLaunchpad/Window/LaunchpadWindowController.swift \
        AppLaunchpad/Views/LaunchpadView.swift
git commit -m "feat: Phase 4 完成 - 编辑模式完整交互"
```

---

## Self-Review

- [x] PRD §3.7.1 长按进入编辑：Task 3 中 `onLongPressGesture(minimumDuration: 0.5)`
- [x] PRD §3.7.2 图标抖动随机相位：Task 3 WobbleModifier 中 `Double.random(in: 0...0.25)` 延迟
- [x] PRD §3.7.3 拖拽排序：Task 4 DragGesture + nearestSlot + pageItemsWithDrag
- [x] PRD §3.7.4 MAS 应用删除按钮：Task 3 AppIconView 中 `app.isMASApp` 判断
- [x] PRD §5 持久化：Task 1 LayoutStore + Task 2 saveLayout()
- [x] 跨页拖拽未实现 → 留 TODO，Phase 6 处理
