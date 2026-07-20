# Phase 5 实现计划 — 文件夹功能

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现文件夹创建（拖拽合并）、展开/收起动画、重命名、从文件夹内移出应用、自动解散。

**Architecture:** `FolderInfo` 存储文件夹元数据，`LayoutData.folders` 字典持久化。`FolderThumbnailView` 渲染收起状态，`FolderExpandedView` 渲染展开态（overlay 覆盖全屏）。文件夹创建/解散逻辑在 `LaunchpadViewModel` 中集中处理。

**Tech Stack:** Swift 6 · SwiftUI · matchedGeometryEffect · Codable · macOS 26+

## Global Constraints

- 不引入第三方依赖
- 文件夹展开态覆盖整个启动台，不跳转新页面
- 每行4个图标
- 文件夹只剩1个 app 时自动解散
- Bundle ID：com.applaunchpad.app

---

## Task 1：FolderInfo 模型 + LayoutData 更新

**Files:**
- Create: `AppLaunchpad/Models/FolderInfo.swift`
- Modify: `AppLaunchpad/Models/LayoutData.swift`

- [ ] **Step 1: 创建 FolderInfo**

```swift
// AppLaunchpad/Models/FolderInfo.swift
import Foundation

/// 用户创建的应用分组文件夹
struct FolderInfo: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var appIDs: [String]          // 文件夹内 app 的 bundleID 顺序列表
    var isUserNamed: Bool         // 用户是否手动改过名称

    init(id: UUID = UUID(), name: String = "文件夹", appIDs: [String] = [], isUserNamed: Bool = false) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
        self.isUserNamed = isUserNamed
    }
}
```

- [ ] **Step 2: 更新 LayoutData 加入 folders**

```swift
// AppLaunchpad/Models/LayoutData.swift
struct LayoutData: Codable {
    var pages: [[LayoutItem]]
    var folders: [UUID: FolderInfo]   // 新增
    var version: Int = 1

    init(pages: [[LayoutItem]] = [], folders: [UUID: FolderInfo] = [:]) {
        self.pages = pages
        self.folders = folders
    }

    static func initial(from apps: [AppInfo], itemsPerPage: Int) -> LayoutData {
        guard itemsPerPage > 0 else { return LayoutData() }
        let items = apps.map { LayoutItem.app(bundleID: $0.bundleID) }
        let pages = stride(from: 0, to: items.count, by: itemsPerPage).map {
            Array(items[$0 ..< min($0 + itemsPerPage, items.count)])
        }
        return LayoutData(pages: pages, folders: [:])
    }
}
```

- [ ] **Step 3: 提交**

```bash
git add AppLaunchpad/Models/FolderInfo.swift AppLaunchpad/Models/LayoutData.swift
git commit -m "feat: FolderInfo 模型 + LayoutData 加入 folders 字典"
```

---

## Task 2：ViewModel 文件夹操作

**Files:**
- Modify: `AppLaunchpad/ViewModel/LaunchpadViewModel.swift`

新增以下方法：

- [ ] **Step 1: 新增文件夹相关方法**

```swift
// MARK: - 文件夹

/// 把两个 app 合并创建文件夹（拖拽 A 到 B 上）
func createFolder(sourceID: String, targetID: String, pageIndex: Int) {
    guard pageIndex < layout.pages.count else { return }
    var page = layout.pages[pageIndex]

    guard let srcIdx = page.firstIndex(of: .app(bundleID: sourceID)),
          let dstIdx = page.firstIndex(of: .app(bundleID: targetID)) else { return }

    let folder = FolderInfo(
        appIDs: [targetID, sourceID],
        isUserNamed: false
    )
    layout.folders[folder.id] = folder

    // 用文件夹替换目标位置，移除源位置
    let minIdx = min(srcIdx, dstIdx)
    let maxIdx = max(srcIdx, dstIdx)
    page.remove(at: maxIdx)
    page.remove(at: minIdx)
    page.insert(.folder(id: folder.id), at: minIdx)
    layout.pages[pageIndex] = page
    saveLayout()
}

/// 把 app 拖入已有文件夹
func addAppToFolder(bundleID: String, folderID: UUID, pageIndex: Int) {
    guard pageIndex < layout.pages.count,
          layout.folders[folderID] != nil else { return }
    var page = layout.pages[pageIndex]
    page.removeAll { $0 == .app(bundleID: bundleID) }
    layout.pages[pageIndex] = page
    layout.folders[folderID]?.appIDs.append(bundleID)
    saveLayout()
}

/// 从文件夹内移出 app 到外层网格
func removeAppFromFolder(bundleID: String, folderID: UUID, pageIndex: Int) {
    guard layout.folders[folderID] != nil else { return }
    layout.folders[folderID]?.appIDs.removeAll { $0 == bundleID }

    // 文件夹只剩1个 app 时自动解散
    if let folder = layout.folders[folderID], folder.appIDs.count <= 1 {
        dissolveFolder(folderID: folderID, pageIndex: pageIndex)
    } else {
        // 将 app 追加到当前页末尾
        if pageIndex < layout.pages.count {
            layout.pages[pageIndex].append(.app(bundleID: bundleID))
        }
    }
    saveLayout()
}

/// 解散文件夹，把内部 app 放回网格
func dissolveFolder(folderID: UUID, pageIndex: Int) {
    guard let folder = layout.folders[folderID],
          pageIndex < layout.pages.count else { return }

    var page = layout.pages[pageIndex]
    if let folderIdx = page.firstIndex(of: .folder(id: folderID)) {
        page.remove(at: folderIdx)
        // 把文件夹内的 app 插入原位置
        let apps = folder.appIDs.map { LayoutItem.app(bundleID: $0) }
        page.insert(contentsOf: apps, at: min(folderIdx, page.count))
    }
    layout.pages[pageIndex] = page
    layout.folders.removeValue(forKey: folderID)
    saveLayout()
}

/// 重命名文件夹
func renameFolder(id: UUID, newName: String) {
    layout.folders[id]?.name = newName.isEmpty ? "文件夹" : newName
    layout.folders[id]?.isUserNamed = !newName.isEmpty
    saveLayout()
}
```

- [ ] **Step 2: mergeLayout 中保留已有文件夹**

在 `mergeLayout` 方法中加入对 `saved.folders` 的保留：
```swift
// mergeLayout 返回时保留文件夹
return LayoutData(pages: ..., folders: saved.folders)
```

- [ ] **Step 3: 提交**

```bash
git add AppLaunchpad/ViewModel/LaunchpadViewModel.swift
git commit -m "feat: ViewModel 文件夹 CRUD 操作"
```

---

## Task 3：FolderThumbnailView（收起态）

**Files:**
- Create: `AppLaunchpad/Views/FolderThumbnailView.swift`

- [ ] **Step 1: 创建缩略图视图**

```swift
// AppLaunchpad/Views/FolderThumbnailView.swift
import SwiftUI

/// 文件夹收起态：圆角矩形 + 内部最多 9 个小图标（3×3）+ 文件夹名称
struct FolderThumbnailView: View {
    let folder: FolderInfo
    let apps: [AppInfo]
    let isEditMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var icons: [String: NSImage] = [:]

    private let gridApps: [AppInfo] {
        folder.appIDs.prefix(9).compactMap { id in
            apps.first { $0.bundleID == id }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 80, height: 80)

                // 3×3 小图标网格
                let columns = min(3, Int(ceil(sqrt(Double(gridApps.count)))))
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(22), spacing: 4), count: 3),
                    spacing: 4
                ) {
                    ForEach(gridApps, id: \.id) { app in
                        if let icon = icons[app.bundleID] {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 22, height: 22)
                        }
                    }
                }
                .padding(8)
                .frame(width: 80, height: 80)
            }

            Text(folder.name)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
        }
        .frame(width: 100)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.5) { onLongPress() }
        .task {
            for app in gridApps {
                let icon = await IconCache.shared.icon(for: app)
                icons[app.bundleID] = icon
            }
        }
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add AppLaunchpad/Views/FolderThumbnailView.swift
git commit -m "feat: FolderThumbnailView 文件夹缩略图"
```

---

## Task 4：FolderExpandedView（展开态）

**Files:**
- Create: `AppLaunchpad/Views/FolderExpandedView.swift`

- [ ] **Step 1: 创建展开视图**

```swift
// AppLaunchpad/Views/FolderExpandedView.swift
import SwiftUI

/// 文件夹展开态：从缩略图位置放大，内部可滚动，顶部可编辑名称
struct FolderExpandedView: View {
    @Binding var folder: FolderInfo
    let apps: [AppInfo]
    let isEditMode: Bool
    let onClose: () -> Void
    let onTapApp: (AppInfo) -> Void
    let onRemoveApp: (String) -> Void
    let onRename: (String) -> Void

    @State private var isEditingName = false
    @State private var editingName = ""

    private var folderApps: [AppInfo] {
        folder.appIDs.compactMap { id in apps.first { $0.bundleID == id } }
    }

    var body: some View {
        VStack(spacing: 16) {
            // 文件夹名称
            if isEditingName {
                TextField("文件夹名称", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 200)
                    .onSubmit { commitRename() }
            } else {
                Text(folder.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .onTapGesture {
                        editingName = folder.name
                        isEditingName = true
                    }
            }

            // 内部图标（4列）
            let columns = Array(repeating: GridItem(.fixed(80), spacing: 20), count: 4)
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(folderApps, id: \.id) { app in
                    AppIconView(
                        app: app,
                        isEditMode: isEditMode,
                        onTap: { onTapApp(app) },
                        onLongPress: {},
                        onDelete: isEditMode ? { onRemoveApp(app.bundleID) } : nil
                    )
                }
            }
            .padding(20)
        }
        .padding(24)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.15)))
        )
        .onTapGesture { } // 阻止点击穿透到背景关闭层
    }

    private func commitRename() {
        isEditingName = false
        onRename(editingName)
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add AppLaunchpad/Views/FolderExpandedView.swift
git commit -m "feat: FolderExpandedView 文件夹展开视图"
```

---

## Task 5：集成到 GridPageView 和 LaunchpadView

**Files:**
- Modify: `AppLaunchpad/Views/GridPageView.swift`
- Modify: `AppLaunchpad/Views/LaunchpadView.swift`

- [ ] **Step 1: GridPageView 渲染文件夹缩略图**

在 `itemView(for:slotIndex:)` 的 `.folder` 分支：
```swift
case .folder(let id):
    if let folder = /* 从外部传入的 folders 字典 */[id] {
        FolderThumbnailView(
            folder: folder, apps: apps,
            isEditMode: isEditMode,
            onTap: { onTapFolder?(folder) },
            onLongPress: onLongPress
        )
    }
```

- [ ] **Step 2: LaunchpadView 管理文件夹展开状态**

```swift
@State private var expandedFolder: FolderInfo? = nil
@Namespace private var folderNamespace

// 在 ZStack 底层加入展开视图
if let folder = expandedFolder {
    Color.black.opacity(0.4)
        .ignoresSafeArea()
        .onTapGesture { expandedFolder = nil }

    FolderExpandedView(
        folder: binding(for: folder.id),
        ...
        onClose: { expandedFolder = nil }
    )
    .transition(.scale(scale: 0.3).combined(with: .opacity))
}
```

- [ ] **Step 3: 拖拽时检测目标是否为文件夹**

在 `GridPageView.dragGesture.onEnded` 时，若目标槽位是 `.folder`，调用 `addAppToFolder` 而非普通排序。

- [ ] **Step 4: 编译验证**

```bash
xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

- [ ] **Step 5: 提交**

```bash
git add AppLaunchpad/Views/ AppLaunchpad/ViewModel/ AppLaunchpad.xcodeproj
git commit -m "feat: Phase 5 完成 - 文件夹创建/展开/收起/重命名/移出"
```

---

## Self-Review

- [x] PRD §3.6.1 创建文件夹：Task 2 createFolder()
- [x] PRD §3.6.2 收起展示：Task 3 FolderThumbnailView（3×3 小图标）
- [x] PRD §3.6.3 展开：Task 4 FolderExpandedView（放大动画）
- [x] PRD §3.6.4 移出应用 / 自动解散：Task 2 removeAppFromFolder()
- [x] PRD §3.6.5 重命名：Task 4 FolderExpandedView 内联编辑
- [x] 持久化：folders 字典随 LayoutData 一起 Codable
