# Phase 5 开发日志 — 文件夹功能

**完成日期**: 2026-07-20  
**状态**: ✅ 完成

---

## 一、交付内容

| 文件 | 说明 |
|-----|------|
| `Models/FolderInfo.swift` | 文件夹数据模型（id/name/appIDs/isUserNamed） |
| `Views/FolderThumbnailView.swift` | 收起态：3×3 小图标 + 文件夹名，支持抖动 |
| `Views/FolderExpandedView.swift` | 展开态：4列图标网格，顶部内联编辑名称 |
| `Models/LayoutData.swift` | 新增 `folders: [UUID: FolderInfo]` 字典 |
| `ViewModel/LaunchpadViewModel.swift` | createFolder / addApp / removeApp / dissolve / rename |
| `Views/GridPageView.swift` | 渲染文件夹缩略图，拖拽检测目标是否为文件夹 |
| `Views/LaunchpadView.swift` | 展开/收起动画，文件夹交互流程 |

---

## 二、交互流程

| 操作 | 行为 |
|-----|------|
| 编辑模式下拖 App A 到 App B 上 | 创建文件夹，两个 app 合并进去 |
| 编辑模式下拖 App 到文件夹上 | app 加入文件夹 |
| 点击文件夹（非编辑模式） | 文件夹弹出展开视图（scale+opacity 动画） |
| 点击展开视图外部区域 | 收起文件夹 |
| 点击展开视图内图标 | 启动 app，收起文件夹 |
| 点击文件夹名称 | 内联编辑，回车确认 |
| 编辑模式下点展开视图内图标的 × | 从文件夹移出，追加到当前页 |
| 文件夹只剩1个 app 时 | 自动解散，app 放回网格 |

---

## 三、待办（TODO）

- 文件夹内的删除 × 按钮目前也是"移出文件夹"，MAS 应用实际卸载在 Phase 7 处理
