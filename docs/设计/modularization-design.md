# AppLaunchpad 模块化设计文档

> 目标：把巨型 `LaunchpadViewModel`（709 行、8 组强耦合职责）拆成职责单一的子协调器，
> 收敛散落的重复逻辑，拆分 SettingsView 大文件。
> 隔离层级：**同 target 内拆分（不拆独立 framework）**，共享类型无需 `public`，
> 改动聚焦、回归风险低、出问题一眼定位到具体控制器。

---

## 1. 设计原则

1. **单一职责**：每个控制器只管一类行为（拖拽 / 文件夹 / 搜索 / 键盘导航 / 几何布局）。
2. **单向依赖**：`Controllers → Data`（只读写共享状态），`ViewModel → 组合`，`View → ViewModel`。
   无循环引用（`Data` 不反向引用任何 Controller）。
3. **薄壳转发、视图少改**：根 `LaunchpadViewModel` 保留公开属性/方法的转发（`var dragState { drag.dragState }`、
   `func beginDrag(...) { drag.beginDrag(...) }`），让现有 View 层几乎零改动，最大化降低回归风险。
4. **行为隔离、逻辑可测**：改拖拽只动 `DragController`；改文件夹只动 `FolderController`；互不牵连。
5. **重复逻辑收敛到 Utils**：`chunked`、cell 尺寸、字号公式、翻页动画、几何推算各一处定义。

---

## 2. 目标架构

```
┌──────────────────────────────────────────────────────────────┐
│  View 层（LaunchpadView / GridPageView / FolderExpandedView …） │
│  只读 viewModel.xxx（经转发薄壳访问子控制器状态与方法）            │
└───────────────────────────┬──────────────────────────────────┘
                            │ 持有 / 转发
┌───────────────────────────▼──────────────────────────────────┐
│  LaunchpadViewModel  （组合根 + 薄壳转发，不再含业务细节）        │
│    ├─ data:       LaunchpadData        // 共享状态容器 @Observable│
│    ├─ drag:       DragController        // 拖拽状态机 + 拖拽逻辑    │
│    ├─ folders:    FolderController      // 文件夹创建/归入/拖出/改名 │
│    ├─ search:     SearchController       // 搜索过滤              │
│    ├─ navigation: NavigationController   // 键盘网格/搜索导航      │
│    ├─ layout:     LayoutService          // 几何 + 布局 + 分页      │
│    └─ services:   LayoutStore / AppScanner / IconCache           │
└──────────────────────────────────────────────────────────────┘
        │ 单向读写                │ 单向读写
┌───────▼────────┐      ┌─────────▼──────────┐
│ LaunchpadData  │      │ Utils（无状态工具） │
│ (@Observable)  │      │ Array+Chunked       │
│ layout/allApps │      │ LayoutGeometry      │
│ pageIndex/...  │      │ AnimationConstants  │
└────────────────┘      └────────────────────┘
```

依赖方向：`Controller → Data`、`Controller/ViewModel → Utils`、`View → ViewModel`。**无反向、无环**。

---

## 3. 模块清单（新建文件）

### 3.1 `ViewModel/Core/LaunchpadData.swift` — 共享状态容器
`@Observable class`，纯状态、无业务逻辑：
- `var layout: LayoutData`
- `var allApps: [AppInfo]`
- `var currentPageIndex: Int`
- `var selectedSlotIndex: Int?`
- `var isVisible: Bool`
- `var isEditMode: Bool`
- `var searchText: String`
- `@ObservationIgnored var gridGeometry: GridGeometry`

### 3.2 `ViewModel/Controllers/DragController.swift` — 拖拽
`@Observable class`，持有 `let data: LaunchpadData`：
- 状态：`var dragState: DragState`
- 方法：`beginDrag` / `updateDragTarget` / `endDrag` / `pageItemsWithDrag` /
  `flipPageWhileDragging` / `detectEdgeScroll` + 边缘翻页 Timer（`.common`）
- 几何落点：`slotUnderCursor` / `iconFootprintItemAt` / `appAtIconPoint`（读 `data.gridGeometry`）

### 3.3 `ViewModel/Controllers/FolderController.swift` — 文件夹
`@Observable class`，持有 `let data: LaunchpadData`：
- `createFolder` / `addAppToFolder` / `removeAppFromFolder` / `dissolveFolder` / `renameFolder`
- `beginFolderDrag` / `updateFolderDragTarget` / `commitFolderReorder` / `moveAppOutOfFolder`

### 3.4 `ViewModel/Controllers/SearchController.swift` — 搜索
`@Observable class`，持有 `let data: LaunchpadData`：
- `var searchResults: [AppInfo]`
- `var isSearching: Bool`
- 过滤逻辑（复用 `FuzzySearch` / `FuzzySearcher`）

### 3.5 `ViewModel/Controllers/NavigationController.swift` — 键盘导航
`@Observable class`，持有 `let data: LaunchpadData`：
- `currentPageItems` / `moveGridSelection` / `moveSearchSelection` / `activateSelected` / `clearSelection`

### 3.6 `ViewModel/Controllers/LayoutService.swift` — 几何 / 布局 / 分页
`@Observable class`，持有 `let data: LaunchpadData` + `let store: LayoutStore`：
- 几何：`columnCount` / `rowCount` / `itemsPerPage` / `totalPages` / `autoColumnCount` / `autoRowCount`
- 布局：`reflowLayout` / `mergeLayout`（从 VM 迁入，最复杂的合并/解散/清理）
- 持久化：`saveLayout`（委托 `store`）
- 分页：`goToPreviousPage` / `goToNextPage` / `goToPage`

### 3.7 `ViewModel/LaunchpadViewModel.swift` — 组合根（瘦身）
- 持有 `data` + 五个控制器 + 服务（`AppScanner` / `IconCache`）
- 转发属性：`dragState`、`currentPageIndex`、`isEditMode`、`isVisible`、`searchText`、
  `selectedSlotIndex`、`layout`、`allApps`、`gridGeometry`、`prefs`
- 转发方法：`beginDrag` / `updateDragTarget` / `endDrag` / `pageItemsWithDrag` /
  `createFolder` / `addAppToFolder` / …（薄壳，一行转发）
- 应用生命周期：`show` / `hide` / `launch` / `loadApps` / `refreshApps` / `enterEditMode` / `exitEditMode`
- 委托搜索结果/导航给对应控制器

---

## 4. 重复逻辑收敛（新建 `Utils/`）

| 重复项 | 当前位置 | 收敛目标 |
|---|---|---|
| `chunked(into:)` | `LaunchpadViewModel.swift:702` + `GridPageView.swift:147` | `Utils/Array+Chunked.swift`（单一定义） |
| `cellW/cellH` 计算 | `LaunchpadView.swift:~340` + `GridPageView.swift:~30` | `Utils/LayoutGeometry.swift` 的 `cellSize(iconSize:)` |
| 字号公式 `min(max(10,iconSize*0.14),16)` | `AppIconView.swift:31` + `FolderThumbnailView.swift:59` | `Utils/LayoutGeometry.swift` 的 `labelFontSize(for:)` |
| 翻页动画 `.spring(duration:0.38,bounce:0.18)` | `LaunchpadView` + `WindowController` 共 5 处 | `Utils/AnimationConstants.swift` |
| 自动间距/行列估算 | `LaunchpadView:31-42` + `ViewModel:41-59` | 收归 `LayoutService` / `GridGeometry` |

> 命中测试两套哲学（纯几何 vs 测量帧最近距离）本轮**先不统一** FolderExpandedView，
> 留给后续单独任务，避免改动文件夹拖拽逻辑引入回归。本轮只抽无状态的纯工具。

---

## 5. SettingsView 拆分

当前 `Views/Settings/SettingsView.swift`（452 行）含四面板 + 权限请求 + 拖拽录制。
按 section 拆成独立文件（同目录 `Views/Settings/`）：
- `SettingsView.swift` — 主容器（NavigationSplitView + 侧栏）
- `SettingsGeneralPane.swift`
- `SettingsAppearancePane.swift`
- `SettingsBehaviorPane.swift`
- `SettingsAboutPane.swift`
- `SettingsPermissionsView.swift`（辅助功能 / 完全磁盘访问等权限请求）
- 拖拽录制相关抽到对应 pane 或 `SettingsBehaviorPane`

（具体面板名以读取 SettingsView 后为准。）

---

## 6. 实施步骤（分批，每批 `xcodebuild` 通过、行为不变）

1. **建 `LaunchpadData` + 五个 Controller 骨架**：把方法体从 `LaunchpadViewModel` 整体搬入对应
   Controller（签名不变），Controller 通过 `data` 读写共享状态。根 VM 改为组合 + 转发薄壳。
   → 编译通过、运行时行为与原版一致（仅结构变化）。
2. **收敛 Utils**：`Array+Chunked` / `LayoutGeometry`（cell 尺寸、字号、自动间距）/
   `AnimationConstants`，替换各处的重复定义与硬编码。
3. **拆分 SettingsView**：按 section 拆文件，主视图保留组合。
4. **`project.yml` 更新 + `xcodegen generate`**：新文件需纳入工程。
5. **回归验证**：`xcodebuild` + 真机实测（见第 8 节）。

---

## 7. 风险与回滚

- **风险 A（Observation 嵌套）**：子控制器须为 `@Observable class`，根 VM 转发计算属性访问底层
  可观测属性即可触发视图更新。拆分后首轮必须真机验证拖拽/编辑态重渲染正常。
- **风险 B（循环引用）**：Controller 持有 `data`（独立单例，被所有人共享），`data` 不反向引用
  Controller，无环。根 VM 强持有控制器，`data` 由根 VM 与控制器共享引用（非互相持有）。
- **回滚**：每批提交前可单独 `git stash`/对比；若某批编译或行为异常，回退该批即可，不影响其他模块。

---

## 8. 验证清单

- [ ] `xcodebuild … Debug build` 通过，无 warning（尤其无未使用/循环引用警告）
- [ ] 拖拽重排落位准确、松手无跳变（DragController 独立）
- [ ] 压 app 建文件夹、压文件夹归入、跨页建/归入（FolderController 独立）
- [ ] 搜索过滤正确（SearchController 独立）
- [ ] 键盘方向键导航、回车启动（NavigationController 独立）
- [ ] 改外观（列/行/间距/图标尺寸）实时生效（LayoutService 独立）
- [ ] 设置四面板均可打开、改动生效（SettingsView 拆分）
- [ ] 后续改 DragController 时，FolderController/SearchController/View 无需改动（模块化达标）
