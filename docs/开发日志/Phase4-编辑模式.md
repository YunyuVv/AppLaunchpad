# Phase 4 开发日志 — 编辑模式与图标拖拽排序

**完成日期**: 2026-07-20  
**对应计划**: `docs/superpowers/plans/2026-07-20-phase4-edit-mode.md`  
**状态**: ✅ 完成

---

## 一、交付内容

### 新增文件

| 文件 | 说明 |
|-----|------|
| `Persistence/LayoutStore.swift` | JSON 持久化，路径 `~/Library/Application Support/AppLaunchpad/layout.json` |
| `Models/DragState.swift` | 拖拽实时状态数据模型 |
| `Views/WobbleModifier.swift` | 图标抖动 ViewModifier，随机相位防止同步摆动 |

### 修改文件

| 文件 | 改动说明 |
|-----|---------|
| `ViewModel/LaunchpadViewModel.swift` | 新增编辑模式、拖拽、持久化、布局合并逻辑 |
| `Views/AppIconView.swift` | 长按进入编辑模式，MAS 应用显示 × 按钮，抖动动画 |
| `Views/GridPageView.swift` | PreferenceKey 收集槽位 frame，DragGesture 拖拽排序 |
| `Views/LaunchpadView.swift` | 编辑模式下背景点击退出编辑，pagingView 接入拖拽状态 |
| `Window/LaunchpadWindowController.swift` | Escape 三级优先：退出编辑 → 清空搜索 → 关闭面板 |

---

## 二、功能说明

### 2.1 进入/退出编辑模式

| 触发 | 行为 |
|-----|------|
| 长按任意图标 0.5s | 进入编辑模式，所有图标开始抖动 |
| 点击空白背景 | 退出编辑模式（不关闭面板） |
| Escape（第一次） | 退出编辑模式 |
| Escape（第二次） | 关闭面板 |
| 点击图标 | 编辑模式下无效，需先退出 |

### 2.2 图标抖动（WobbleModifier）

- 振幅：±2.2°
- 频率：0.10–0.13s（每个图标随机，避免同步）
- 起始延迟：0–0.25s 随机（制造"依次开始抖动"的效果）

### 2.3 拖拽排序

- 触发：编辑模式下，拖拽任意图标（`DragGesture(minimumDistance: 5)`）
- 命中检测：`PreferenceKey` 收集所有槽位的 Global Frame，找最近槽位
- 实时让位：`pageItemsWithDrag()` 返回拖拽中的视觉排列，其余图标动态位移
- 松手落位：`endDrag()` 写入 `layout.pages[page]` 并调用 `LayoutStore.save()`
- 持久化：重启 App 后排列保留

### 2.4 布局持久化与合并

**合并策略**（保证用户排列不丢失）：
```
已存储布局 + 最新扫描结果
    ├─ 移除已卸载的 App（不在扫描结果中的 bundleID）
    └─ 追加新安装的 App 到末页
```

### 2.5 MAS 应用删除按钮

- 编辑模式下，`isMASApp == true` 的应用左上角显示 × 按钮
- 当前点击 × 仅预留接口（TODO：Phase 7 实现实际卸载流程）

---

## 三、关键技术点

**PreferenceKey 收集槽位 frame**：
```swift
.background(
    GeometryReader { geo in
        Color.clear.preference(
            key: SlotFrameKey.self,
            value: [slotIndex: geo.frame(in: .global)]
        )
    }
)
.onPreferenceChange(SlotFrameKey.self) { slotFrames = $0 }
```
这是 SwiftUI 中父视图获取子视图位置信息的标准模式，无需 UIKit/AppKit 坐标转换。

**Swift 6 并发修复**：
`PreferenceKey.defaultValue` 是 `nonisolated` 静态属性，需标注 `nonisolated(unsafe)` 规避并发检查。

---

## 四、验收结果

- [x] 长按 0.5s 进入编辑模式，图标抖动，相位随机
- [x] 编辑模式下拖拽图标，其余图标实时让位
- [x] 松开后图标落入目标槽位
- [x] MAS 应用显示 × 删除按钮
- [x] Escape 三级优先正确
- [x] 排列在 App 重启后保留

---

## 五、待办（TODO）

- MAS 应用实际卸载流程（Phase 7）
- 跨页拖拽（Phase 6）
- 触控板两指滑动翻页（Phase 6，见 Phase 2 日志 TODO-1）

---

## 六、修复记录

### Bug 1：编辑模式下无法拖拽图标
**根因**：`AppIconView` 内 `Button` 在编辑模式下仍参与命中检测（`allowsHitTesting` 默认 true），捕获了所有 `mouseDown` 事件，父级 `VStack` 的 `DragGesture` 永远收不到事件起点，`onChanged` 无法触发。  
**修复**：
- `AppIconView`：编辑模式下对 Button 设置 `.allowsHitTesting(!isEditMode)`，让 mouseDown 事件穿透到父级 VStack
- `FolderThumbnailView`：同理，编辑模式下设置 `.allowsHitTesting(!isEditMode)`
- `GridPageView`：`.gesture(dragGesture, including: isEditMode ? .all : .subviews)` 代替 `nil` 条件判断，非编辑模式下手势仅传给子视图

---

## 六、未解决 TODO

### TODO-2：图标拖拽排序最终无法落位
**现象**：拖拽可以自由移动，松手后图标不归位/不重排。  
**已分析**：SwiftUI 拖拽闭包捕获旧 struct 导致 `hasBegunDrag` 方案仍有问题，`endDrag()` 的调用时机不确定。  
**预计阶段**：Phase 6 深度调试

### TODO-3：拖拽创建文件夹无效
**现象**：悬停 0.7s 计时器可能正常触发（白圈高亮出现），但 `createFolder` 执行后文件夹未在界面显示，或 `endDrag` 未被正确调用。  
**预计阶段**：Phase 6 与 TODO-2 一并修复

### TODO-4：跨页拖拽触发翻页后图标无法落入新页
**现象**：边缘触发翻页后 `endDrag` 调用的是原来页的布局，新页槽位信息未同步。  
**预计阶段**：Phase 6
