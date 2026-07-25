# AppLaunchpad 拖拽排序交互重设计

> 状态：待实施（2026-07-22）
> 范围：启动台网格内 app 拖拽排序 / 跨页移动 / 创建文件夹 / 归入文件夹
> 不改动：文件夹内拖拽（独立 `FolderSlotFrameKey` 机制，保持可用）、设置面板、存储层

---

## 1. 当前问题（为何"完全不可用"）

网格拖拽的落点判定依赖三套相互冲突的机制：

| 机制 | 现状 | 问题 |
|------|------|------|
| 测量帧 | `GridPageView` 用 `SlotFrameKey` 偏好键实时把每个 cell 的全局坐标框写入 `viewModel.slotFrames` | 实时让位动画会把 app 视觉挪走，帧坐标随之移动 |
| 快照 | 拖拽起手把 `slotFrames` 拍成 `dragSlotFrames`，命中测试改读这份固定快照以"防止目标逃跑" | 快照几何不再等于视觉位置，下一帧重算目标时已错位 |
| 最近中心点 | `nearestSlot` 用二维直线距离找最近 cell 中心 | 二维网格里"最近中心"与"用户想放的位置"常不一致，尤其对角/换行时 |

**由此产生的具体症状：**

1. **反馈振荡 / 没法移到指定位置**：`pageItemsWithDrag` 按 `targetSlotIndex` 实时让位 → 图标移动 → 下一帧 `updateDragTarget` 又拿"原始快照几何"重算 `targetSlotIndex` → 目标槽位基于过时几何 → app 跳到错误位置。用户拖动时落点持续漂，松手位置不可控。
2. **无法排到某 app 旁边**：光标只要压在另一个 app 的格内，`updateDragTarget` 就把 `targetSlotIndex` 强制复位到源位、停止让位（为给"建文件夹"让路）。结果：用户想把一个 app 放去紧挨某 app，却只能塞进两 app 之间的间隙；而间隙→槽位用"最近中心点"判定，二维下有歧义，经常落错。
3. **跨页 off-by-one / 截断**：翻页后靠 `dragSnapshotPage` 把快照刷新为"当前页实时帧"的 hack，落点仍会被 `min(dst, count)` 截断或错位。
4. **松手二次跳变**：`endDrag` 用 `targetSlotIndex`（快照几何）落点，而视觉是让位后的顺序，两者不一致 → 松手瞬间再跳一次。

---

## 2. 设计目标

- **所见即所得**：光标位置 → 精确几何槽位，预览缺口与最终落点完全一致。
- **无反馈振荡**：落点只由"光标坐标 + 固定网格几何"决定，与图标当前视觉位置无关。
- **跨页稳定**：翻页仅切换 `currentPageIndex`，落点公式不变。
- **文件夹创建/归入**：仅当光标落在**图标 footprint（图标实际方形区域，不含 cell 间隙）**内时触发，松开判定；压在间隙=重排。
- **松手无跳变**：预览与提交共用同一 `move(from:to:)` 语义（同页 / 跨页 / `endDrag` 均统一 `insert at to`；2026-07-22 修正：曾用经典 splice `to>src?to-1` 使向右拖时 app 偏左一格 → "移动 typora 没正确落位"）。

---

## 3. 技术选型

| 关注点 | 方案 |
|--------|------|
| 落点计算 | **单一稳定几何 `GridGeometry`**：网格容器 global 原点 + `cols/rows/cellW/cellH/hSpacing/vSpacing/iconSize`。落点 `slotUnderCursor(point) = row*cols + col` 纯几何推导，**彻底移除** measured frame、`dragSlotFrames` 快照、`nearestSlot` 最近中心。 |
| 几何来源 | `LaunchpadView` 在 `pagingView` 外包一个 `GeometryReader`，把网格容器 global 框 + 已知 `cols/rows/iconSize/spacing` 写入 `viewModel.gridGeometry`。该属性标 `@ObservationIgnored`，变更不触发视图重渲染（避免设值→通知→重渲染的死循环）。 |
| 手势宿主 | 保持 `LaunchpadView` 根 `ZStack` 的 `.simultaneousGesture(globalDragGesture)`（前几轮验证：比 `GridPageView` 更稳定，翻页不中断，解决"拖到第二页卡死"）。 |
| 让位预览 | `pageItemsWithDrag` 仍返回"被拖 app 从源位移到 `cursorSlot`"的预览数组；动画 `.spring(value: dragState.cursorSlot)`。因 `cursorSlot` 来自固定几何，不再振荡。 |
| 文件夹内拖拽 | 维持现状（独立 `FolderSlotFrameKey` + `beginFolderDrag/updateFolderDragTarget/commitFolderReorder`），本次不重构。 |
| 边缘翻页 | 保留 `detectEdgeScroll` 的 `Timer`，**必须加 `.common` mode**（拖拽中 AppKit 切 `NSEventTrackingRunLoopMode`，default-mode Timer 不 fire）。 |
| 浮层图标 | 保留 `floatingDragIcon` 跟随光标 + 网格内被拖格 `opacity 0`（显示落点缺口）。 |

**为什么不用 measured frame / 快照**：均匀网格下每个 cell 几何完全确定，测量纯属多余且是振荡根源。几何推导是 O(1)、确定性、与动画无关，从根本上消除"落点漂移"。

---

## 4. 核心数据结构

```swift
/// 网格几何（全局坐标系，拖拽期间稳定，因网格容器不移动）
struct GridGeometry {
    let origin: CGPoint      // 网格内容区 global 原点（左上）
    let size: CGSize         // 网格内容区大小
    let columns: Int
    let rows: Int
    let cellW: CGFloat       // 单格宽 = (size.width - hSpacing*(cols-1))/cols
    let cellH: CGFloat
    let hSpacing: CGFloat
    let vSpacing: CGFloat
    let iconSize: CGFloat    // 用于 footprint 命中（图标方形区域）

    /// 光标落在哪个槽位（0..cols*rows-1），超出范围按边界 clamp
    func slotUnderCursor(_ p: CGPoint) -> Int {
        let lx = p.x - origin.x
        let ly = p.y - origin.y
        let strideX = cellW + hSpacing
        let strideY = cellH + vSpacing
        // 居中边界：间隙中点归到更近的列/行
        let col = min(max(Int((lx + hSpacing/2) / strideX), 0), columns - 1)
        let row = min(max(Int((ly + vSpacing/2) / strideY), 0), rows - 1)
        return row * columns + col
    }

    /// 槽位对应的"图标 footprint"矩形（cell 中心对齐的 iconSize 方形）
    func iconRect(forSlot slot: Int) -> CGRect {
        let col = slot % columns
        let row = slot / columns
        let cx = origin.x + CGFloat(col) * (cellW + hSpacing) + cellW/2
        let cy = origin.y + CGFloat(row) * (cellH + vSpacing) + cellH/2
        return CGRect(x: cx - iconSize/2, y: cy - iconSize/2,
                      width: iconSize, height: iconSize)
    }
}
```

`DragState` 变更：
- 新增 `var cursorSlot: Int = 0`（替代 `targetSlotIndex`，语义为"光标所在几何槽位"，同时作为 make-way 动画驱动值）。
- 保留 `folderDropTargetID: String?` / `folderHoverID: UUID?`（松手判定建文件夹/归入）。
- 移除 `targetSlotIndex` 这一命名（避免与旧快照逻辑混淆）。

`LaunchpadViewModel` 变更：
- 移除 `slotFrames` / `dragSlotFrames` / `dragSnapshotPage` / `nearestSlot` / `slotAt`。
- 新增 `@ObservationIgnored var gridGeometry: GridGeometry?`。
- 新增 `func slotUnderCursor(_:pageIndex:) -> Int?`、`func iconFootprintItemAt(_:) -> (slot:Int, item:LayoutItem)?`、`func appAtIconPoint(_:) -> String?`。

---

## 5. 交互逻辑

### 5.1 起手判定（`globalDragGesture` onChanged 首帧）
`start = appAtIconPoint(value.startLocation)`：
- 返回 bundleID ⇒ 起手在 app 图标上 → `enterEditMode()`（若非编辑态）+ `beginDrag`。
- 返回 nil（间隙/文件夹/空白）→ 不起拖，让 `pagingDragGesture` 处理翻页、点击处理打开。

### 5.2 让位预览（`pageItemsWithDrag(pageIndex)`）
```
guard dragging && grid 上下文 else { return layout.pages[pageIndex] }
if folderDropTargetID != nil || folderHoverID != nil {
    return layout.pages[pageIndex]            // 建文件夹/归入：静止高亮，无让位
}
let to = cursorSlot
if pageIndex == sourcePageIndex {
    // 同页移动：先移除源，再按标准 move 语义插入
    remove at sourceSlotIndex → insert at to   // 2026-07-22 统一为 to：经典 splice (to>src?to-1) 会向右拖偏左一格
} else {
    // 跨页目标页：把被拖 app 作为占位插入 to（预览缺口）
    insert dragged placeholder at min(to, count)
}
```
被拖格 `opacity 0`，浮动图标跟随光标 → 用户看到缺口随光标精确开合。

### 5.3 落点判定（`updateDragTarget(location:)`）
```
dragState.dragLocation = location
detectEdgeScroll(location)                     // 边缘翻页（.common Timer）
guard let slot = slotUnderCursor(location, currentPageIndex) else { return }
dragState.cursorSlot = slot
if let (_, item) = iconFootprintItemAt(location) {
    switch item {
    case .app(let tid) where tid != draggedBundleID:
        folderDropTargetID = tid; folderHoverID = nil   // 松手建文件夹
    case .folder(let fid):
        folderHoverID = fid; folderDropTargetID = nil   // 松手归入
    default:
        folderDropTargetID = nil; folderHoverID = nil   // 压在自己格上
    }
} else {
    folderDropTargetID = nil; folderHoverID = nil       // 间隙 → 重排
}
```
关键：hover 到别的 app **只标蓝圈、不复位 `cursorSlot`**。让位继续以 `cursorSlot` 进行（缺口开在被拖 app 与目标的间隙），松手时若仍压在图标 footprint 内才建文件夹，否则按 `cursorSlot` 落位。→ 用户可把 app 排到目标 app 旁（缺口在目标右侧），也可压在目标上建文件夹，二者不再互斥。

### 5.4 文件夹创建 / 归入
- `iconFootprintItemAt` 要求光标在图标方形内（含 cell 间隙则判为间隙→重排），与"最近中心点"彻底不同。
- 松手：`folderDropTargetID` → `createFolder`；`folderHoverID` → `addAppToFolder`。

### 5.5 跨页（`flipPageWhileDragging`）
仅 `goToNextPage()/goToPrevPage()`，不搬移被拖 app（手势宿主稳定，无需搬）。`cursorSlot` 每次 `updateDragTarget` 基于"当前页几何"重算，天然适配。

### 5.6 松手提交（`endDrag`）
```
switch context {
case .grid(let sourcePage):
    if folderDropTargetID != nil { createFolder(...) }
    else if folderHoverID != nil { addAppToFolder(...) }
    else {
        let to = cursorSlot
        remove item at sourceSlotIndex from layout.pages[sourcePage]
        if sourcePage == currentPageIndex {
            insert at to   // 与预览同公式（2026-07-22 统一 to，修复向右拖偏左一格 bug）
        } else {
            insert at min(to, count) into layout.pages[currentPageIndex]
        }
        saveLayout()
    }
case .folder: break   // 文件夹内由 commitFolderReorder 提交
}
dragState = DragState()
```
预览与提交用**完全相同**的 `move` 公式 → 松手零跳变。

---

## 6. 与现有架构衔接

- 手势宿主 `LaunchpadView` 根 ZStack：`globalDragGesture` + `pagingDragGesture` 维持，仅内部调用换成几何方法。
- 边缘翻页 `Timer`：保留 `.common` mode 约束（记忆库红线）。
- `moveAppOutOfFolder`：原用 `nearestSlot`，改为 `slotUnderCursor(dropLocation, pageIndex:)`（同一几何，落点一致）。
- 文件夹内拖拽（`FolderExpandedView`）：独立机制，不改。
- 设置面板实时调行列/间距：触发 `reflowLayout`，几何随之（几何每帧从 `gridGeometry` 读取，自动跟随）。

---

## 7. 实施改动清单

| 文件 | 改动 |
|------|------|
| `Models/DragState.swift` | `targetSlotIndex` → `cursorSlot`；保留 `folderDropTargetID/folderHoverID` |
| `Models/GridGeometry.swift`（新） | 几何结构体 + `slotUnderCursor` + `iconRect` |
| `ViewModel/LaunchpadViewModel.swift` | 移除 `slotFrames/dragSlotFrames/dragSnapshotPage/nearestSlot/slotAt`；新增 `gridGeometry`(@ObservationIgnored)、`slotUnderCursor`、`iconFootprintItemAt`、`appAtIconPoint`；重写 `beginDrag/updateDragTarget/endDrag/pageItemsWithDrag/moveAppOutOfFolder`；`flipPageWhileDragging` 不再复位 `targetSlotIndex` |
| `Views/GridPageView.swift` | 移除 `SlotFrameKey`/`slotFrameTracker`/`.onPreferenceChange`/本地 `nearestSlot`；动画驱动值改 `cursorSlot` |
| `Views/LaunchpadView.swift` | `pagingView` 外包 `GeometryReader` 写 `gridGeometry`；`globalDragGesture`/`pagingDragGesture` 改用 `appAtIconPoint`/`iconFootprintItemAt`/`slotUnderCursor` |

---

## 8. 验证清单

- [ ] 拖 app 到任意间隙，缺口精确开在光标所在槽位，松手落点 == 缺口位置（无跳变）。
- [ ] 把一个 app 排到另一个 app 紧邻右侧：光标放目标右侧间隙，松手即在目标右侧。
- [ ] 光标压在另一 app 图标上停住 → 蓝圈；松手建文件夹；压在间隙则只重排。
- [ ] 拖到文件夹图标上 → 白框；松手归入。
- [ ] 拖到屏幕边缘停留 0.8s → 自动翻页，翻页后可继续拖到目标页任意位置落定。
- [ ] 跨页落点准确（无 off-by-one / 末尾截断）。
- [ ] 间隙左右滑仍可翻页；app 上起手拖不动（只拖）。
- [ ] `xcodebuild … Debug build` → BUILD SUCCEEDED。
