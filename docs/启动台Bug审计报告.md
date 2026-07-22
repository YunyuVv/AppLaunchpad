# AppLaunchpad 启动台交互 Bug 审计报告

> 审计时间：2026-07-21  
> 范围：`LaunchpadView` / `GridPageView` / `AppIconView` / `LaunchpadViewModel` / `DragState` / `LayoutData` / `FolderExpandedView` / `FolderThumbnailView` / `FuzzySearch` / `AppDelegate` / `LaunchpadWindowController` 及周边辅助文件。

---

## 一、用户截图问题：单 app 拖拽时，被拖 app 自身出现蓝色进度环

### 1.1 现象
拖动一个 app（如 News）时，被拖 app 的原位置出现一个蓝色圆环，看起来像「环套在自己身上」。用户期望：只有悬停到另一个 app 上、准备建文件夹时，才在目标 app 上出现进度环。

### 1.2 根因
蓝色圆环是 `GridPageView` 里的 `folderProgressRing`（使用 `Color.accentColor`，系统默认蓝色）。它出现在被拖 app 身上，是两套问题叠加：

**根因 A：`.opacity(0.0)` 无法隐藏后面的 `.overlay(...)`**

`GridPageView` 原代码顺序：

```swift
AppIconView(...)
    .opacity(isDragged ? 0.0 : 1.0)          // 想隐藏被拖 app
    .overlay(folderProgressRing(...))        // 加在 opacity 之后
```

在 SwiftUI 中，`.overlay(...)` 是加在被修饰视图之外的兄弟层。**放在 `.opacity` 之后的 overlay 不会受前面 opacity 影响**。于是被拖 app 虽然本体隐藏了，但它的进度环仍以完全不透明度画出来，看起来就像「自己被蓝色环套住」。

**根因 B：实时让位动画导致目标 app 位移**

P1 的实时让位会把被拖 app 插入到目标槽位，其余图标弹簧让位。这导致「鼠标正下方的目标 app」被挤到旁边，而进度环仍按目标 app 的 bundleID 绘制，于是环可能出现在邻居位置，视觉上也会误以为是「旁边不该出现的环」。

### 1.3 已修复
- `GridPageView`：
  - 进度环 overlay 现在放在 `.opacity` **之前**，确保被拖 app 隐藏时环一起消失。
  - `folderProgressValue` 与 `isFolderTarget` 都增加 `!isDragged` 守卫，即使状态机异常也不会在被拖 app 上画环。
- `LaunchpadViewModel.pageItemsWithDrag`：当 `folderCandidateID != nil`（即已悬停在另一个 app 上准备建文件夹）时，**不再让位**，目标 app 保持原位，进度环会准确套在目标 app 上。

---

## 二、本次已一并修复的 P1 Bug

### 2.1 `mergeLayout` 解散空文件夹后残留悬空 `.folder` 槽位
**文件**：`LaunchpadViewModel.swift:512-522`  
**现象**：当某个文件夹内所有 app 都被卸载，代码只从 `folders` 字典里删除了 folder 数据，但 `pages` 数组里还留着 `.folder(id)`。网格会渲染成一个空白槽位，页面计数也会错位。  
**修复**：清理 `folders` 后，再遍历 `pages` 移除所有指向已删除 folder 的槽位，并过滤掉空页。

---

## 三、当前仍存在的 Bug / 体验问题清单

### P0（必须尽快修）

| # | 问题 | 根因 | 建议修复 |
|---|------|------|----------|
| 3.1 | 跨页拖拽落点坐标错配（**2026-07-22 已修复**） | `flipPageWhileDragging` 翻页后只改 `currentPageIndex`，`nearestSlot` 仍用源页快照 `dragSlotFrames`；若目标页 app 数量/行列更少，悬停下方区域会映射到源页高位索引，松手被 `min(dst,count)` 截断到末尾 | 新增 `dragSnapshotPage`；`nearestSlot` 在 `currentPageIndex != dragSnapshotPage` 时把 `dragSlotFrames` 刷新为当前页 `slotFrames`（当前页无让位动画，几何稳定）；`endDrag` 落点改用 `nearestSlot` 实时重算；翻页时 `targetSlotIndex` 复位为源位 |
| 3.2 | 拖拽到已有文件夹无悬停反馈（**2026-07-22 已修复**） | `updateDragTarget` 对 `.folder` 目标直接 return，没设高亮态 | `DragState` 新增 `folderHoverID`；`updateDragTarget` 命中 `.folder` 时设置；`GridPageView` 给 `FolderThumbnailView` 加悬停高亮环 + 缩放；`onEnded` 文件夹分支兜底重置 `dragState` |

### P1（建议近期修）

| # | 问题 | 根因 | 建议修复 |
|---|------|------|----------|
| 4.1 | 编辑模式图标不抖动 | `WobbleModifier.swift` 已实现，但全工程没有调用点 | 在 `AppIconView` 最外层加 `.wobble(isEditMode)` |
| 4.2 | 网格编辑模式无删除 X 按钮 | `GridPageView` 传 `onDelete: nil` 给 `AppIconView` | 传入 `onDelete: { viewModel.removeAppFromLaunchpad(bundleID) }` 并在 ViewModel 实现移除 |
| 4.3 | 全局拖拽与分页手势冲突 | `pagingDragGesture` 和 `globalDragGesture` 都作为 `.simultaneousGesture` 挂在外层，`pagingDragGesture` 的 `!isEditMode` 守卫可能来不及拦截 | 在 `pagingDragGesture` 起点用 `slotAt` 判断，落在 app 槽位上就直接 return；或改用 `ExclusiveGesture` |
| 4.4 | 快捷键无法收起已显示的启动台 | 只注册了 `addGlobalMonitorForEvents`；当面板是 key window 时，本进程内事件不会走全局监听 | 同时注册 `addLocalMonitorForEvents` 实现真正的 toggle |
| 4.5 | FSEvents 刷新可能与拖拽并发 | `AppDelegate` 收到文件系统事件后直接 `await vm.refreshApps()`，会重建 `layout.pages` | 拖拽中（`dragState.isDragging`）挂起/合并刷新，拖完再执行 |

### P2（体验/一致性）

| # | 问题 | 根因 | 建议修复 |
|---|------|------|----------|
| 5.1 | 搜索框无焦点环/光标 | `SearchBarView` 声明了 `@FocusState` 但从未赋值 | 启动台显示且进入搜索时 `isFocused = true` |
| 5.2 | 打开文件夹浮层时打字会误触发搜索 | `LaunchpadWindowController` 的 key monitor 默认把字符加到 `searchText`，未判断 `expandedFolder != nil` | 文件夹浮层打开且未聚焦 TextField 时，不透传字符到搜索 |
| 5.3 | 搜索态点背景直接退出，而非清空搜索 | `LaunchpadView` 背景 tap 直接 `onDismiss()`，没有优先判断 `isSearching` | 先 `if viewModel.isSearching { viewModel.searchText = "" }` |
| 5.4 | 文件夹内拖拽无让位动画 | `FolderExpandedView` 只做了 `isTarget` 高亮，`orderedApps` 在 `commitFolderReorder` 前不重排 | 参照网格实现 folder 内的实时让位 |
| 5.5 | 崩溃/异常时 Dock 可能卡在隐藏态 | `LaunchpadWindowController.show()` 设置 `presentationOptions = [.hideDock, .autoHideMenuBar]`，`hide()` 才恢复 | 用 `defer` 或异常监听兜底恢复 |
| 5.6 | 设置窗口层级切换竞态 | 依赖设置窗口成为 key 才恢复面板层级；若设置窗口未正常成为 key，启动台会卡在普通层 | 增加超时/显式恢复路径 |
| 5.7 | 模糊搜索子序列噪音偏大 | `FuzzySearch.subsequenceScore` 的 `gaps <= query.count * 3` 阈值偏松 | 收紧 gaps 上限或提高紧凑度权重 |

### P3（已知限制/小优化）

- `folderProgressRing` 中心偏移：ring 挂在整个 `AppIconView` 上，可能压到文字；建议把 ring 套在图标图区域。
- `createFolder` 顺序：当前把「被拖到的目标 app」放首位，与多数启动台心智模型相反。
- 搜索结果过多时无滚动/分页：当前 `searchResultsView` 直接复用 `GridPageView`，大量结果可能超出可视区。
- `AppInfo` 用 `bundleID` 作为唯一 id，若同一 bundleID 出现在多个路径，只能保留第一个。

---

## 四、当前任务优先级建议

1. ~~**P0 跨页拖拽落点错配**（已修复 2026-07-22）~~
2. ~~**P0 拖到已有文件夹无反馈**（已修复 2026-07-22）~~
3. **P1 编辑模式抖动 / 删除按钮 / 手势冲突 / 快捷键 toggle / FSEvents 并发**
4. **P2 搜索焦点、文件夹浮层搜索、点背景清空搜索**
5. **P3 视觉微调和排序习惯**

> 注：本次审计中 **蓝圈问题** 与 **空文件夹槽位问题** 已修复；**P0 跨页落点错配** 与 **P0 拖到文件夹无反馈** 已修复（2026-07-22，编译通过）。其余问题仍待处理。
