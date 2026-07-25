# AppLaunchpad — App 图标操作能力需求（对齐原生启动台）

**版本**: v0.1（草稿）  
**日期**: 2026-07-25  
**关联文档**: `docs/需求/PRD-启动台需求文档.md`、`docs/开发知识库/翻页功能.md`

---

## 一、背景与目标

macOS 原生「启动台（Launchpad）」在 **app 图标**上提供一整套操作：单击启动、长按进入编辑（抖动）模式、拖拽重排/建文件夹、删除、以及**右键上下文菜单（打开 / 在 Finder 中显示 / 添加到程序坞）** 等。

用户原话「右边 app 有什么操作」即指 **app 图标的右键上下文菜单及全部 app 级操作**。本文档：

1. 梳理原生启动台在 app 图标上的**全部操作**；
2. 对照 AppLaunchpad **现状**，标注已实现 / 缺口；
3. 给出**补齐需求（R1–R6）与优先级**，供本项目逐项支持。

> 注：「文件夹」主网格拖拽建文件夹当前已从运行期移除（仅保留惰性数据骨架），故文件夹建/归入不在本文档范围，单列于「不在范围」。

---

## 二、原生启动台 App 操作全集

| 编号  | 操作                  | 触发方式                   | 原生行为                                                       |
| --- | ------------------- | ---------------------- | ---------------------------------------------------------- |
| N1  | 启动应用                | 单击图标                   | 打开对应 app                                                   |
| N2  | 进入编辑模式              | 长按图标（约 0.5s）           | 图标抖动（jiggle），可移动/删除                                        |
| N3  | 拖拽重排                | 编辑模式下拖动                | 图标让位（make-way），松手落位                                        |
| N4  | 拖拽建文件夹              | 编辑模式下拖到另一 app 上        | 自动生成文件夹，两 app 归入                                           |
| N5  | 拖入/拖出文件夹            | 编辑模式下拖到文件夹 / 拖出        | 归入或移出                                                      |
| N6  | 删除应用                | 编辑模式下点图标左上角 **X**      | **仅 App Store 下载的 app 显示 X**；系统/非商店 app 无 X；点击 = 卸载（移到废纸篓） |
| N7  | 右键菜单 · 打开           | 右键 / 双指轻点 / Control-单击 | 打开 app                                                     |
| N8  | 右键菜单 · 在 Finder 中显示 | 同上                     | 在 Finder 中定位并高亮 `.app`                                     |
| N9  | 右键菜单 · 添加到程序坞       | 同上                     | 把 app 加到 Dock 持久区                                          |
| N10 | 拖拽到程序坞              | 从启动台把图标拖到 Dock         | 加入 Dock                                                    |
| N11 | 搜索过滤                | 顶部搜索框                  | 实时过滤（本项目已实现，略）                                             |

---

## 三、AppLaunchpad 现状对照矩阵

| 原生操作               | AppLaunchpad 现状 | 缺口说明                                                               |
| ------------------ | --------------- | ------------------------------------------------------------------ |
| N1 启动              | ✅ 已实现           | `AppIconView` 的 `onTap` → `viewModel.launch`                       |
| N2 编辑模式            | ✅ 已实现           | `onLongPress(minimumDuration:0.5)` → `enterEditMode`；图标 hover/缩放已有 |
| N3 拖拽重排            | ✅ 已实现           | `DragController` make-way 几何落点（纯 `GridGeometry.slotUnderCursor`）   |
| N4 拖拽建文件夹          | ❌ 已移除           | 主网格 `folderHoverID`/建文件夹手势已移除；`FolderController` 仅服务文件夹展开视图        |
| N5 拖入/拖出文件夹        | ❌ 已移除           | 同上                                                                 |
| N6 删除              | ✅ 已实现（调整）     | 用户确认编辑模式 X 不好看 → **改为右键菜单「删除」项**（非 X）；含二次确认 + 放回原处（见 R4） |
| N7 右键-打开           | ✅ 已实现           | `AppIconView` `.contextMenu` → `NSWorkspace.open(url)`                       |
| N8 右键-在 Finder 中显示 | ✅ 已实现           | `.contextMenu` → `activateFileViewerSelecting([url])`                        |
| N9 右键-添加到程序坞       | ❌ 无             | 本次未实现（保留为后续需求，见 R3 状态）                                          |
| N10 拖到程序坞          | ❌ 无             | —                                                                  |

**结论**：单击启动、编辑模式、拖拽重排已齐备；**右键菜单「打开 / 在 Finder 中显示 / 删除」已实现**（N7/N8 + 调整的 N6），其中「删除」含二次确认并支持废纸篓「放回原处」；原生 N9「添加到程序坞」与编辑模式 X 未实现（用户选择右键删除替代 X）。

---

## 四、需求详述（Requirements）

### R1 — App 图标右键上下文菜单（P0）

- **描述**：在任意 app 图标上右键 / 双指轻点 / Control-单击，弹出 NSMenu。
- **菜单项（实际落地）**：
  - `打开`（→ `viewModel.launch(app)`）
  - `在 Finder 中显示`（→ R2）
  - `删除`（→ R4，移入废纸篓 + 二次确认 + 支持「放回原处」）
  - > 注：原生 R3「添加到程序坞」本次**未实现**（见 R3 状态），菜单按用户决策以「删除」替代「添加到程序坞」入列。
- **触发规则**：
  - 右键（secondary click）**直接弹菜单**，**不进入编辑模式**（与原生一致）。
  - 与现有背景层 `.contextMenu`（关闭启动台）共存：app 图标上的右键由 `AppIconView` 的 `.contextMenu` 优先消费，背景层菜单作兜底。
- **手势冲突**：现有 `onLongPressGesture(0.5s)` 处理 primary 长按进编辑；SwiftUI `.contextMenu` 自动识别 secondary click，二者不冲突，无需改长按逻辑。
- **验收**：右键 app 弹「打开 / 在 Finder 中显示 / 添加到程序坞」三选项；点击分别正确执行；空白处右键仍弹「关闭启动台」。

### R2 — 在 Finder 中显示（P0，R1 子项）

- **描述**：定位并高亮 app 的 `.app` 包。
- **实现**：`NSWorkspace.shared.activateFileViewerSelecting([app.url])`。
- **依赖**：`AppInfo.url` 已提供（AppScanner 采集）。

### R3 — 添加到程序坞（P0，R1 子项）

- **描述**：把 app 加入 Dock 持久区（左侧应用区）。
- **实现（推荐）**：
  - 读 `~/Library/Preferences/com.apple.dock.plist` 的 `persistent-apps`；
  - 追加一个 tile（含 `tile-data.file-data._CFURLString = app.url.path`、`tile-type = "file-tile"`）；
  - `defaults write` 后 `killall Dock` 刷新（放异步 `Task`，避免阻塞 UI）。
  - 备选：AppleScript `tell application "Dock" to make new ...`；plist 直写更可控。
- **验收**：右键「添加到程序坞」后 Dock 出现该 app 图标；重复添加应去重（按 path 判重）。
- **状态**：⚠️ **未实现**。用户聚焦「在 Finder 中显示 / 删除」，未要求 Dock 集成；删除项已替代「添加到程序坞」进入右键菜单（见 R1/R4）。保留为后续需求。

### R4 — App 删除（右键菜单「删除」项 + 二次确认 + 放回原处 / Put Back）（P1，已落地）

- **入口调整（对齐用户决策）**：用户确认编辑模式抖动 X「不好看」，**不采用原生编辑模式 X**，改为在 app 图标**右键菜单中加入「删除」项**（与原生右键「打开 / 在 Finder 中显示」并列）。触发后动作与原生卸载一致：把 `.app` 移入废纸篓。
- **二次确认**：点「删除」先弹 `.confirmationDialog("确定把"<displayName>"移到废纸篓？", …)`，确认按钮（`role: .destructive`）才执行删除，取消（`role: .cancel`）不删。避免误删（原生无确认，本项目加此道保险）。
- **放回原处（Put Back）支持（关键）**：
  - 废纸篓里右键「放回原处」依赖文件被移入时记录的**原始路径元数据**。
  - 实现**必须**用 `NSWorkspace.shared.performFileOperation(.recycleOperation, source: 父目录路径, destination: "", files: [app名], tag:)`——与 Finder 把文件拖进废纸篓走同一条代码路径，会自动写原始路径元数据，Put Back 才可用。
  - **禁用** `FileManager.default.trashItem(at:)`：该 Foundation 底层 API 只把文件挪到 `~/.Trash`，**不写 Put Back 元数据** → 废纸篓右键无「放回原处」（早期实现踩过此坑，已改为 `NSWorkspace` 路径）。
- **安全范围**：`/System/` 下受 SIP 保护的系统 app 不显示「删除」项（原生也无卸载入口）；其余 app 删除失败（权限/SIP）静默忽略。
- **实现**：`LaunchpadViewModel.deleteApp(_:)` → `NSWorkspace.performFileOperation(.recycleOperation, …)` → 随后 `await layoutService.refreshApps()`，`mergeLayout` 自动剔除已卸载的 app。
- **验收**：
  - 右键「删除」弹二次确认 → 确认后 app 移入废纸篓、启动台图标消失；取消则不删。
  - 在废纸篓里右键该 app **出现「放回原处」**，可还原到原 `/Applications` 位置。
  - `/System` 下系统 app 右键无「删除」项。

### R5 — 拖拽到程序坞（P2，可选）

- **描述**：从启动台把图标拖到 Dock 释放即加入（同 N10）。
- **依赖**：需接入 Dock 拖放事件（AppKit `performDragOperation`），工作量较大；可视 R3 完成后扩展。

### R6 — 恢复文件夹拖拽建/归入（P2，可选，不在本次强制）

- **描述**：主网格编辑模式下拖到另一 app 自动建文件夹、拖入/出文件夹（N4/N5）。
- **现状**：运行时已移除，仅保留 `FolderController` 惰性骨架与 `LayoutService.mergeLayout` 兼容逻辑。恢复需重建手势与 UI（参见 `MEMORY.md`「文件夹功能」节）。
- **决策**：需用户单独确认是否恢复，本文档不纳入 P0/P1。

---

## 五、实现要点与风险

1. **右键菜单落地位置**：在 `AppIconView` 的 `Button` 上追加 `.contextMenu { ... }`。注意 `AppIconView` 当前是 `Button(action:)` 包裹，`.contextMenu` 应加在 `Button` 外层 `ZStack` 或 `Button` 本身；secondary click 不会触发 `onTap`（primary click 才触发），逻辑无冲突。
2. **编辑模式 vs 右键**：原生右键在编辑模式下也弹菜单（不退出编辑）。本项目保持：右键恒弹菜单；长按恒进编辑。两者触发源不同，安全。
3. **添加到程序坞的 Dock 刷新**：`killall Dock` 会重启 Dock，属正常副作用；放后台 `Task` 执行，UI 不卡。
4. **删除权限**：移动 `.app` 到 `~/.Trash` 需要对该 app 目录有写权限；系统目录（/System、/Applications 受 SIP 保护的）移动可能失败，R4 已用 `isMASApp` 限定主要由用户态 `/Applications` 下的商店 app，失败应 `try/catch` 并提示。
5. **`gridGeometry` 与现状红线**：新增右键/删除均**不改动翻页偏移与落点几何**（`gridGeometry` 固定当前页），符合既有红线（勿搬回 LaunchNext 式全并排宽容器）。

---

## 六、验收标准（汇总）

- [ ] 右键 app 弹出「打开 / 在 Finder 中显示 / 删除」三项（R1+R2+R4；R3 添加到程序坞未实现）
- [ ] 「删除」弹二次确认 → 确认后移入废纸篓、启动台图标消失（R4）
- [ ] 废纸篓里该 app 右键**出现「放回原处」**，可还原到原 `/Applications` 位置（R4 · Put Back）
- [ ] `/System` 下系统 app 右键无「删除」项（R4）
- [ ] 右键不进入编辑模式、不与长按进编辑冲突（R1）
- [ ] 现有单击启动 / 长按编辑 / 拖拽重排 / 翻页体验不被回归

---

## 七、优先级与排期建议

| 优先级    | 需求           | 说明                                      |
| ------ | ------------ | --------------------------------------- |
| **P0** | R1 + R2 + R4 | 右键菜单：打开 / 在 Finder 中显示 / 删除（删除含二次确认 + 放回原处）。R3 添加到程序坞未实现、延后 |
| **P1** | R4（删除）     | 右键「删除」项 + 二次确认 + 放回原处（Put Back），替代原生编辑模式 X               |
| **P2** | R5 / R6      | 拖到 Dock / 恢复文件夹，可选，待用户确认                |



---

## 八、不在本次范围

- 文件夹主网格拖拽建/归入（N4/N5，R6）——当前运行期已移除，需单独评估恢复成本。
- 搜索过滤（N11）——已实现，不在缺口。
- 程序坞拖放反向（从 Dock 拖回启动台）——原生不支持，忽略。
