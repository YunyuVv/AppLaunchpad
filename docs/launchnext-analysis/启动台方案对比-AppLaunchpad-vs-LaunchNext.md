# 启动台方案对比：AppLaunchpad（本项目） vs LaunchNext

> 对比目的：从**功能覆盖**与**实现方案**两个维度，对比本项目 `AppLaunchpad`（纯 SwiftUI）与参考项目 `LaunchNext`（AppKit + Core Animation），分析各自优缺点，并判断哪条技术路线更优。
> 背景：`AppLaunchpad` 是正在自研的 macOS 启动台替代；`LaunchNext` 是开源参考（`references/LaunchNext/`，GPL-3 许可，基于 LaunchNow 演化）。
> 关键结论先行：**没有绝对的"谁更好"，取决于目标**。纯 SwiftUI 路线在「可维护性 / 零依赖 / 当前稳定性」上胜出；AppKit+CA 路线在「大规模性能 / 多输入覆盖 / 经典体验还原度」上胜出。对独立开发的自研 app，**建议保留纯 SwiftUI 地基，按需求点状借鉴 LaunchNext 的思路**。

---

## 一、功能对比

| 功能点 | AppLaunchpad（本项目） | LaunchNext（参考） | 差异说明 |
|---|---|---|---|
| 全屏启动台面板 | ✅ `NSPanel` 全屏浮层 | ✅ 无边框 `NSWindow`，支持全屏/紧凑两种模式 | LaunchNext 多一种紧凑窗口态 |
| 状态栏常驻 | ✅ `NSStatusItem`，单击/右键菜单 | 未明确（无状态栏项） | 本项目更贴合"常驻工具"定位 |
| 菜单栏 / Dock 隐藏 | ✅ 唤起时 `hideDock + autoHideMenuBar` | 默认全屏辅助层覆盖 | 近似 |
| 网格 + 翻页 | ✅ 多页 `VStack/HStack` + 边缘 0.4s 自动翻页 | ✅ `CALayer` 平移翻页 + 触控板精确滚动 | 思路同，渲染层不同 |
| 可调行列/图标尺寸/间距 | ✅ `UserPreferences`（"0=自动"按屏比例推算） | ✅ 类似参数（columns/rows/iconSize…） | 近似 |
| 编辑模式（抖动） | ✅ `WobbleModifier`（随机相位） | ✅ 抖动动画 | 近似 |
| 拖拽重排（含跨页） | ✅ 容器级 `DragGesture` + `SlotFrameKey` 最近槽位 | ✅ CA 层 `draggingLayer` + `gridPositionAt` 几何换算 | 思路同；本项目"松手才提交"，LaunchNext"延迟 0.15s 实时让位" |
| 拖到文件夹建文件夹 | ✅ 悬停 0.7s 进度环 | ✅ 悬停进 dropZone + 0.15s 延迟提交 | 近似 |
| 文件夹内重排 / 拖出 / 解散 | ✅ `FolderExpandedView`（`LazyVGrid` + `DragGesture`） | ✅ `CAFolderGridView`（paged/vertical 双布局） | LaunchNext 文件夹支持"分页/垂直滚动"两种模式更丰富 |
| 文件夹内联重命名 | ✅ `TextField` | ✅ 双击重命名 | 近似 |
| 搜索 | ⚠️ 子串匹配（`contains`，前缀优先排序） | ✅ 模糊匹配（`FuzzyMatcher`：归一化/缩写/子序列打分） | **LaunchNext 明显更强** |
| 键盘导航（方向键/回车/删除） | ✅ `LaunchpadWindowController.keyDown` | ✅ 本地 keyDown + 手柄命令 | 本项目覆盖键盘，LaunchNext 额外覆盖手柄 |
| 全局快捷键唤起 | ✅ `NSEvent.addGlobalMonitorForEvents`（⌥Space 可录制） | ✅ Carbon `RegisterEventHotKey` | 思路同，底层 API 不同 |
| 原生 4/5 指手势唤起 | ❌ 无 | ✅ OpenMultitouchSupport + 状态机 | **LaunchNext 独有** |
| 游戏手柄操作 | ❌ 无 | ✅ `GameController` | **LaunchNext 独有** |
| 热角唤起 | ❌ 无 | ✅ `HotCornerMonitor` | **LaunchNext 独有** |
| 拖到 Dock | ❌ 无 | ✅ `NSDraggingSession` | **LaunchNext 独有** |
| 批量选择 | ❌ 无 | ✅ `batchSelectionMode` | **LaunchNext 独有** |
| 原生 Launchpad 布局导入 | ❌ 无（自扫 + 自管布局） | ✅ 读系统 Launchpad SQLite | **LaunchNext 独有**，零配置上手 |
| 多显示器 | ✅ 主屏 / 鼠标所在屏（`UserPreferences`） | 未明确 | 本项目已支持 |
| CLI / TUI 管理 | ❌ 无 | ✅ 终端管理布局 | **LaunchNext 独有** |
| 多语言 | 中文为主 | 多语言（含简/繁中文） | LaunchNext 更全 |
| 背景模糊 | ✅ `NSVisualEffectView`（`NSViewRepresentable`） | ✅ `NSVisualEffectView`/liquidGlass | 近似 |
| 动画 | SwiftUI `Animation` / `.transition` | SwiftUI + `CATransaction` + `CADisplayLink` 120Hz | LaunchNext 动画链路更厚 |
| 数据持久化 | 手写 `LayoutStore` 写 JSON + `UserDefaults` | SwiftData `Data.store` | 本项目无第三方框架依赖 |
| 第三方依赖 | **零依赖** | OpenMultitouchSupport（C 框架）、SwiftData | **本项目更干净** |
| 最低系统 | macOS 26 (Tahoe) | macOS 26 (Tahoe) | 同 |

**功能覆盖小结**：LaunchNext 在「输入方式多样性」（4/5 指手势、手柄、热角、拖到 Dock、批量选择）、「经典体验还原」（原生布局导入、紧凑模式、多语言、CLI）上明显领先；本项目在「常驻工具定位」（状态栏、多显示器、可录制热键、零依赖、稳定自管布局）上更贴合独立自研工具，且核心网格/拖拽/文件夹/搜索/键盘导航均已具备。

---

## 二、实现方案对比（按子系统）

### 2.1 窗口 / 生命周期

- **AppLaunchpad**：`@main App` + `@NSApplicationDelegateAdaptor`，但**启动台本体是命令式创建的 `NSPanel` 全屏浮层**（`LaunchpadWindowController` 持 `KeyablePanel`，`borderless` + 覆盖 `canBecomeKey`）。设置窗是独立的 SwiftUI `Window("设置")` 场景，经 `openWindow(id:)` 桥接。常驻靠 `applicationShouldTerminateAfterLastWindowClosed → false` + Dock 重开 `toggle()`。
- **LaunchNext**：`@main App` 但 `body` 仅 `Settings {}`，**全部窗口由 AppDelegate 用 AppKit 创建**（无边框 `NSWindow`，`NSHostingView` 挂 SwiftUI 树）。不区分"启动台面板"与"设置窗"两种窗口类型，统一一个 `NSWindow`。

> 实质相同：两者都是 "AppKit 宿主 + SwiftUI 内容"，只是本项目把"全屏启动台"单独做成 `NSPanel` 浮层，LaunchNext 把整棵 SwiftUI 树当 `NSWindow` 内容。

### 2.2 网格渲染

- **AppLaunchpad — 纯 SwiftUI 声明式**：`GridPageView` 用 `VStack` 套 `HStack` 逐行逐列铺 `AppIconView`；布局参数（`computeIconSize` / `autoColumnCount`）按屏幕尺寸推算，用户覆盖优先。`SlotFrameKey`（`preference`）采集每个槽位全局 `frame`，供拖拽时查最近槽位。
- **LaunchNext — Core Animation 命令式**：`CAGridView`（`NSView` 子类）用 `CALayer` 层级渲染：每 item = `iconLayer + textLayer(+ 文件夹 glassLayer)`，翻页即 `pageContainerLayer.transform` 平移。`gridCenterForGlobalIndex` / `gridPositionAt` 做索引↔坐标互转；`CADisplayLink` 跑 120Hz ProMotion。通过 `NSViewRepresentable` 嵌回 SwiftUI。

> 核心分歧点：视图层级由谁持有。SwiftUI 由框架管理子视图生命周期；CA 由开发者直接操作图层矩阵。这是两者性能与可维护性的根本分水岭。

### 2.3 交互 / 手势

- **AppLaunchpad**：**完全用 SwiftUI 手势**——容器级 `.highPriorityGesture(DragGesture)` / `.simultaneousGesture(pagingDragGesture)`；长按进编辑用 `onLongPressGesture(minimumDuration: 0.5)`；按压态由 `onPressingChanged` 驱动以避开手势竞争。键盘/滚轮用 `NSEvent` 本地监视器（`LaunchpadWindowController`）。**没有用 `NSGestureRecognizer`**。
- **LaunchNext**：**同样完全绕开 `NSGestureRecognizer`**，但方向相反——直接在 `NSView` 上重写 `mouseDown/Dragged/Up` + `NSEvent` 本地监视器 + `NSTrackingArea` 悬停。原生 4/5 指手势走第三方 OpenMultitouchSupport C 框架（`GestureMonitor` + `GestureStateMachine`，状态机 `idle→arming→tracking→triggered→cooldown`，按"手指距离中位数/质心/半径比 + 连续帧匹配"识别）。

> 共同点：两者都**刻意不用 `NSGestureRecognizer`**，且在拖拽跨页这个坑上**殊途同归**——都把"拖拽手势宿主上移到容器层 + 翻页不重建视图身份"作为解法（本项目曾因 `.id(currentPageIndex)` 翻页导致跨页卡死，后改为原地切内容）。

### 2.4 拖拽重排 / 建文件夹

- **AppLaunchpad**：`DragState` 状态机（`DragContext` + `draggedBundleID` + `folderProgress`）+ 容器级 `DragGesture`。拖拽中实时更新 `targetSlotIndex`，**松手才提交重排**（`endDrag`）；拖到文件夹 cell 上 `addAppToFolder`；悬停另一 app 0.7s 起 `folderProgressTimer` 满 1 建文件夹。边缘翻页 0.8s（`startEdgeScrollTimer`），**两个 Timer 都加 `.common`** 模式（绕开拖拽中 `NSEventTrackingRunLoopMode` 不 fire 的坑）。
- **LaunchNext**：`startDragging` 创建 `draggingLayer`（放大 1.1 跟随光标）→ `updateDragging` 用 `gridPositionAt` 求悬停格 → **延迟 0.15s 提交** `applyIconPositionUpdate`（`CATransaction` 0.45s 弹簧位移，把目标位前后图标推开/合拢）→ 边缘翻页 0.4s。落点：app+app→建文件夹，app+folder→移入，其余→跨页级联重排。同样 `Timer` 加 `.common`。

> 思路高度一致，差异在"提交时机"与"让位动画"：LaunchNext 拖动中就有实时弹簧让位（更跟手），本项目是松手才重排（更简单、更少动画状态 bug）。

### 2.5 文件夹

- **AppLaunchpad**：`FolderThumbnailView`（圆角 + 3×3 小图标）+ `FolderExpandedView`（居中浮层 `LazyVGrid` 4 列 + `.ultraThinMaterial` 背景 + `transition(.scale.combined(with:.opacity))`）。拖出文件夹靠 `folderGlobalFrame.contains(location)` 判定。
- **LaunchNext**：`CAFolderGridView`（CA 层，paged / vertical 双布局）+ SwiftUI `FolderView` 兜底；拖出触发 `onDragAppOut`。

### 2.6 动画

- **AppLaunchpad**：**仅 SwiftUI 原生动画**（`.spring(duration:bounce:)` 翻页/弹入、`WobbleModifier` 抖动、`.transition` 文件夹开合）。无 `CAAnimation` / `CATransaction`。
- **LaunchNext**：**三层动画并存**（SwiftUI `Animation` / Core Animation `CATransaction`+`CAFrameRateRange` / 窗口 `NSAnimationContext`），`LNAnimations` 集中管理，支持统一开关与调速。

### 2.7 数据与持久化

- **AppLaunchpad**：`AppScanner`（`actor`）枚举三处 `/Applications` + 读 `Info.plist` 过滤后台 App；`IconCache`（`NSCache`）异步取图标；`FSEventsWatcher` 监听安装/卸载。**布局用 `LayoutStore`（`actor`）写 JSON 到 `Application Support/AppLaunchpad/layout.json`**，`UserPreferences`（`@Observable` 单例）写 `UserDefaults`。**零框架依赖，无 SwiftData/CoreData**。
- **LaunchNext**：`NSWorkspace` 扫描 + **读系统 Launchpad SQLite 一键迁移**（`NativeLaunchpadImporter`，SQLite3 C API）+ 持久化用 **SwiftData `Data.store`**（`PageEntryData` 按页/位/类型写入）。

### 2.8 搜索

- **AppLaunchpad**：搜索框 + `LaunchpadViewModel.searchResults`，纯 `contains` 子串过滤、前缀优先排序；面板内直接敲字符也追加进搜索（类原生）。
- **LaunchNext**：`LaunchpadSearchEngine` + 自研 `FuzzyMatcher`（`SearchIndexEntry` 做归一化/分词/首字母缩写），打分排序（完全相等 1000 → 前缀 700 → 缩写 470 → 子序列 300+ → contains 180），"sf" 对 "Safari" 等缩写场景体验明显更好。

### 2.9 唤起方式

- **AppLaunchpad**：全局快捷键（`NSEvent.addGlobalMonitorForEvents`，⌥Space 可录制）+ 状态栏菜单 + Dock 菜单/重开 `toggle`。
- **LaunchNext**：Carbon `RegisterEventHotKey` + 原生 4/5 指手势 + 游戏手柄 + 热角 + 拖到 Dock。

### 2.10 技术栈

| 项 | AppLaunchpad | LaunchNext |
|---|---|---|
| UI 框架 | 纯 SwiftUI（声明式） | AppKit NSView + Core Animation（+ SwiftUI 混合） |
| 最低系统 | macOS 26 | macOS 26 |
| 并发模型 | `actor` + `@MainActor @Observable` | Swift Concurrency + `ObservableObject`/`@Published` |
| 持久化 | JSON + UserDefaults（自写） | SwiftData |
| 第三方依赖 | **无** | OpenMultitouchSupport（C）、SwiftData |
| 规模 | 24 文件 ≈ 3299 行 | 更大（含 Gesture/Search/Folder 多引擎） |
| 许可 | 自有 | GPL-3（传染性强） |

---

## 三、各自的优缺点

### AppLaunchpad（纯 SwiftUI）优缺点

**优点**
1. **可维护性高**：声明式 UI，布局/拖拽/文件夹/搜索全部在一个心智模型内，无 AppKit/CA 双栈协调成本。新人易读易改。
2. **零第三方依赖**：仅用系统框架（`NSWorkspace`/`NSEvent`/`NSVisualEffectView`），无 GPL 传染风险，可闭源商用。
3. **当前稳定性好**：跨页拖拽、边缘翻页、文件夹进度环等核心交互已修通，关键 `Timer .common` 坑已踩平。
4. **常驻工具定位清晰**：状态栏 + 多显示器 + 可录制热键 + 自管布局，已具备"轻量替代启动台"的完整体验闭环。
5. **实时外观调节**：`UserPreferences`（`@Observable` 单例 + `UserDefaults` didSet）让设置滑块即时驱动启动台重绘，体验顺滑。

**缺点**
1. **大规模性能天花板**：数百图标重排/翻页时，SwiftUI 子视图重建开销高于 CA 直接操作图层；当前靠"松手才提交 + 不翻页 `.id`"规避卡死，图标极多时仍可能掉帧。
2. **输入方式单一**：仅全局快捷键/状态栏/Dock + 鼠标拖拽；缺 4/5 指手势、手柄、热角、拖到 Dock、批量选择。
3. **搜索是子串匹配**：无模糊/缩写打分，长列表精准度弱于 `FuzzyMatcher`。
4. **缺原生布局导入**：用户从系统 Launchpad 迁移需手动重排，上手成本高于 LaunchNext 的"一键迁移"。

### LaunchNext（AppKit + Core Animation）优缺点

**优点**
1. **大规模性能更稳**：CALayer 直接操作矩阵 + `CADisplayLink` 120Hz，数百图标实时重排/翻页不触发 SwiftUI 视图重建，帧率更稳。
2. **多输入覆盖全面**：原生 4/5 指手势、游戏手柄、热角、拖到 Dock、批量选择——还原经典 Launchpad 体验最完整。
3. **拖动中实时让位动画**：`CATransaction` 弹簧位移让邻近图标实时推开/合拢，手感最跟手。
4. **零配置上手**：读系统 Launchpad SQLite 一键迁移布局/文件夹，新用户零学习成本。
5. **体验细节丰富**：紧凑模式、多语言、CLI/TUI 管理、文件夹分页/垂直双布局。

**缺点**
1. **可维护性成本最高**：AppKit `NSView` + `CALayer` + SwiftUI 三栈混合，双引擎（Legacy/CA）并存，心智负担与潜在 bug 面远大于纯 SwiftUI。
2. **第三方依赖与许可风险**：`OpenMultitouchSupport` 是第三方 C 框架（需评估引入与系统兼容性），整体 GPL-3 具传染性——若本项目直接复制其代码，可能被迫开源本项目。
3. **SwiftData 耦合**：持久化绑死 SwiftData `Data.store`，升级/迁移/调试成本高于本项目手写 JSON。
4. **复杂度推高稳定性风险**：多输入状态机（手势/手柄/热角/热键并行）、双渲染引擎并行，任一环节回归都难定位。
5. **常驻工具定位弱**：无状态栏常驻、无多显示器策略，更偏"复刻体验 demo"而非"日常常驻工具"。

---

## 四、哪个实现方案更好？

**结论：没有绝对赢家，按目标分场景判断。**

### 场景 A：独立自研、长期维护、希望闭源商用 → 本项目（纯 SwiftUI）更好
对单人/小团队的自研工具，**可维护性与零依赖 > 极限性能**。本项目当前已具备完整可用的启动台体验（网格/翻页/拖拽/文件夹/搜索/键盘/状态栏/热键/多屏），且代码干净、无 GPL 风险。把地基换成 CA 双引擎，会成倍增加维护负担却只换取"图标上千时才显现"的性能余量——性价比低。**保留纯 SwiftUI 地基是更优的工程选择。**

### 场景 B：要 1:1 复刻经典 Launchpad 体验、并接受开源/社区协作 → LaunchNext 路线更优
若目标是"还原苹果原生启动台的所有交互细节"（4/5 指手势、手柄、热角、拖到 Dock、原生布局迁移、模糊搜索），那 CA 路线 + 多输入状态机是必经之路，LaunchNext 已把这些难点趟平。**但 GPL-3 传染是硬约束**——若本项目要闭源商用，不能直接复用其代码，只能借鉴思路。

### 推荐策略（给本项目）：**"纯 SwiftUI 地基 + 点状借鉴"**
1. **地基不动**：继续用纯 SwiftUI + `NSPanel` + JSON 持久化，保住可维护性与零依赖。
2. **优先借鉴的高性价比点**（按性价比排序）：
   - ① **模糊搜索**（高/低）：把 `FuzzyMatcher` 算法（归一化 + 首字母缩写 + 子序列打分）移植到 `searchResults`，体验提升明显、改动小、无依赖。
   - ② **原生布局导入**（高/中）：实现 `NativeLaunchpadImporter` 思路，读系统 Launchpad SQLite 一键迁移，解决上手成本问题（注意 SQLite schema 兼容，LaunchNext 仅支持 legacy schema）。
   - ③ **拖动中实时让位动画**（中/中）：参考 `applyIconPositionUpdate` 的 0.15s 延迟弹簧，把"松手才重排"升级为"拖动中邻近图标实时让位"，手感更跟手（需控制动画状态复杂度避免回归）。
   - ④ **多输入唤起**（中/高）：若用户需要，按 `HotCornerMonitor` / `GestureStateMachine` 思路加"热角"与"4/5 指手势"；但 OpenMultitouchSupport 是第三方 C 依赖 + GPL 风险，建议自研或评估替代（如 `MultitouchSupport` 私有框架的合规封装）。
   - ⑤ **拖到 Dock / 批量选择**（低/高）：属于锦上添花，优先级靠后。
3. **不建议盲目照搬**：双渲染引擎（Legacy/CA）并行、把网格整体改写为 `CALayer`——除非本项目确实遇到大规模掉帧且纯 SwiftUI 无法优化，否则不值得为性能余量牺牲可维护性。

---

## 五、落地建议清单（本项目可行动项）

| 优先级 | 借鉴点 | 来源机制 | 落地成本 | 收益 |
|---|---|---|---|---|
| P0 | 模糊搜索（缩写/子序列打分） | `FuzzyMatcher` + `SearchIndexEntry` | 低（纯算法，无依赖） | 高 |
| P0 | 原生 Launchpad 布局导入 | `NativeLaunchpadImporter`（SQLite3 C API） | 中（需 schema 兼容） | 高（零配置上手） |
| P1 | 拖动中实时让位弹簧动画 | `applyIconPositionUpdate`（0.15s 延迟 + `CATransaction`） | 中 | 中高（手感） |
| P2 | 热角唤起 | `HotCornerMonitor`（NSEvent 鼠标位置 + hitbox） | 中 | 中 |
| P2 | 原生 4/5 指手势 | `GestureMonitor` + `GestureStateMachine` | 高（第三方 C 依赖 + GPL 风险） | 中（尝鲜向） |
| P3 | 拖到 Dock / 批量选择 | `NSDraggingSession` + `batchSelectionMode` | 高 | 低（锦上添花） |

> ⚠️ **许可红线**：LaunchNext 为 **GPL-3**，具传染性。本项目若直接复制其源码（尤其 `Gesture/`、`Search/FuzzyMatcher`、`CAGridView` 拖拽逻辑等核心模块），可能要求开源本项目。**只借鉴架构思路与算法，不直接拷贝源码**；引入任何第三方手势框架前先评估许可与系统兼容性。

---

## 附：关键参考位置

- 本项目代码：`AppLaunchpad/AppLaunchpad/`（`LaunchpadView.swift` / `LaunchpadViewModel.swift` / `GridPageView.swift` / `FolderExpandedView.swift` / `UserPreferences.swift` / `AppDelegate.swift` / `LaunchpadWindowController.swift`）
- 参考项目：`references/LaunchNext/LaunchNext/`（`CAGridView.swift` / `CAGridView+Input.swift` / `Gesture/` / `Search/FuzzyMatcher.swift` / `NativeLaunchpadImporter.swift` / `CAFolderGridView.swift` / `Animations.swift`）
- 已生成的 LaunchNext 分析文档：`docs/launchnext-analysis/LaunchNext启动台实现分析.md`
