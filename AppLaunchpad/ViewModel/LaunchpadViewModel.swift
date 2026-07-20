import AppKit
import Observation

/// 启动台全局状态管理，所有 UI 状态的单一数据源
@Observable
@MainActor
final class LaunchpadViewModel {

    // MARK: - 核心数据

    var allApps: [AppInfo] = []
    var layout: LayoutData = LayoutData()

    // MARK: - UI 状态

    var isVisible: Bool = false
    var currentPageIndex: Int = 0
    var searchText: String = ""
    var isEditMode: Bool = false
    var dragState: DragState = DragState()

    // 悬停计时器：用于检测拖拽到另一个 App 上 0.7s 后进入文件夹创建模式
    private var folderHoverTimer: Timer? = nil
    // 边缘翻页计时器：拖拽到屏幕边缘时自动翻页
    private var edgeScrollTimer: Timer? = nil

    // MARK: - 翻页方向（供视图层 transition 使用）
    private(set) var pageFlipGoingForward: Bool = true

    // MARK: - 计算属性

    func columnCount(for screen: NSScreen) -> Int {
        switch screen.frame.width {
        case 1440...: return 7
        case 1280 ..< 1440: return 6
        default: return 5
        }
    }

    var itemsPerPage: Int {
        columnCount(for: NSScreen.screens.first ?? NSScreen.screens[0]) * 5
    }

    var totalPages: Int { layout.pages.count }

    var searchResults: [AppInfo] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return allApps
            .filter { $0.displayName.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
            .sorted {
                let ap = $0.displayName.lowercased().hasPrefix(q)
                let bp = $1.displayName.lowercased().hasPrefix(q)
                if ap != bp { return ap }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    var isSearching: Bool { !searchText.isEmpty }

    // MARK: - 翻页

    func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        pageFlipGoingForward = false
        currentPageIndex -= 1
    }

    func goToNextPage() {
        guard currentPageIndex < totalPages - 1 else { return }
        pageFlipGoingForward = true
        currentPageIndex += 1
    }

    func goToPage(_ index: Int) {
        guard index >= 0, index < totalPages else { return }
        pageFlipGoingForward = index > currentPageIndex
        currentPageIndex = index
    }

    // MARK: - 编辑模式

    func enterEditMode() {
        isEditMode = true
    }

    func exitEditMode() {
        folderHoverTimer?.invalidate()
        folderHoverTimer = nil
        stopEdgeScrollTimer()
        isEditMode = false
        dragState = DragState()
    }

    // MARK: - 拖拽排序

    func beginDrag(bundleID: String, pageIndex: Int, slotIndex: Int, location: CGPoint) {
        dragState = DragState(
            isDragging: true,
            draggedBundleID: bundleID,
            sourcePageIndex: pageIndex,
            sourceSlotIndex: slotIndex,
            targetSlotIndex: slotIndex,
            dragLocation: location
        )
    }

    func updateDragTarget(slotIndex: Int, location: CGPoint) {
        guard dragState.isDragging else { return }

        let prevSlot = dragState.targetSlotIndex
        dragState.targetSlotIndex = slotIndex
        dragState.dragLocation = location

        // 切换到新槽位时：清除文件夹模式，重启悬停计时器
        if slotIndex != prevSlot {
            dragState.folderTargetID = nil
            folderHoverTimer?.invalidate()
            folderHoverTimer = nil

            // 检查新槽位是否是另一个 app（原始布局，非预览）
            let page = dragState.sourcePageIndex
            guard page < layout.pages.count,
                  slotIndex < layout.pages[page].count,
                  case .app(let targetID) = layout.pages[page][slotIndex],
                  targetID != dragState.draggedBundleID else { return }

            // 悬停 0.7s 后进入文件夹创建模式
            folderHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.dragState.isDragging,
                          self.dragState.targetSlotIndex == slotIndex else { return }
                    self.dragState.folderTargetID = targetID
                }
            }
        }

        // 边缘翻页检测：拖拽到屏幕左/右边缘时自动翻页
        detectEdgeScroll(location: location)
    }

    private func detectEdgeScroll(location: CGPoint) {
        let screenWidth = NSScreen.screens.first?.frame.width ?? 1440
        let edgeZone: CGFloat = 100

        if location.x < edgeZone && currentPageIndex > 0 {
            startEdgeScrollTimer(goNext: false)
        } else if location.x > screenWidth - edgeZone && currentPageIndex < totalPages - 1 {
            startEdgeScrollTimer(goNext: true)
        } else {
            stopEdgeScrollTimer()
        }
    }

    private func startEdgeScrollTimer(goNext: Bool) {
        guard edgeScrollTimer == nil else { return }   // 已有计时器，不重复创建
        edgeScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if goNext { self.goToNextPage() } else { self.goToPreviousPage() }
                self.edgeScrollTimer = nil
            }
        }
    }

    private func stopEdgeScrollTimer() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
    }

    func endDrag() {
        folderHoverTimer?.invalidate()
        folderHoverTimer = nil
        stopEdgeScrollTimer()
        guard dragState.isDragging else { return }

        let page = dragState.sourcePageIndex

        if let targetID = dragState.folderTargetID {
            // 文件夹创建模式：悬停在另一个 app 上 0.7s 后松手
            createFolder(sourceID: dragState.draggedBundleID, targetID: targetID, pageIndex: page)
        } else {
            // 普通重排
            let src = dragState.sourceSlotIndex
            let dst = dragState.targetSlotIndex
            if src != dst, page < layout.pages.count {
                var items = layout.pages[page]
                guard src < items.count else { dragState = DragState(); return }
                let item = items.remove(at: src)
                items.insert(item, at: min(dst, items.count))
                layout.pages[page] = items
                saveLayout()
            }
        }
        dragState = DragState()
    }

    /// 拖拽时返回当前页的"视觉排列"
    /// 文件夹创建模式下：保持原始排列（不做让位，目标 App 会高亮显示）
    /// 普通重排模式下：被拖图标插入目标槽位，其余让位
    func pageItemsWithDrag(pageIndex: Int) -> [LayoutItem] {
        guard dragState.isDragging, dragState.sourcePageIndex == pageIndex,
              pageIndex < layout.pages.count else {
            return pageIndex < layout.pages.count ? layout.pages[pageIndex] : []
        }
        // 文件夹模式：原始排列不动，视觉高亮由 folderTargetID 驱动
        if dragState.isFolderMode { return layout.pages[pageIndex] }

        var items = layout.pages[pageIndex]
        let src = dragState.sourceSlotIndex
        let dst = dragState.targetSlotIndex
        guard src < items.count else { return items }
        let item = items.remove(at: src)
        items.insert(item, at: min(dst, items.count))
        return items
    }

    // MARK: - 应用操作

    func loadApps() async {
        let scanned = await AppScanner.shared.scan()
        allApps = scanned

        if let saved = await LayoutStore.shared.load() {
            layout = mergeLayout(saved: saved, scanned: scanned)
        } else {
            layout = LayoutData.initial(from: scanned, itemsPerPage: itemsPerPage)
        }
    }

    func launch(_ app: AppInfo) {
        exitEditMode()
        hide()
        NSWorkspace.shared.open(app.url)
    }

    func saveLayout() {
        let current = layout
        Task.detached { await LayoutStore.shared.save(current) }
    }

    func show() { isVisible = true }

    func hide() {
        isVisible = false
        isEditMode = false
        dragState = DragState()
        searchText = ""
        currentPageIndex = 0
    }

    // MARK: - Private

    /// 合并已存储布局与最新扫描结果：保留顺序，追加新 App，移除已卸载 App
    private func mergeLayout(saved: LayoutData, scanned: [AppInfo]) -> LayoutData {
        let scannedIDs = Set(scanned.map(\.bundleID))

        // 移除已卸载的 app
        var pages = saved.pages.map { page in
            page.filter { item in
                if case .app(let id) = item { return scannedIDs.contains(id) }
                return true
            }
        }.filter { !$0.isEmpty }

        // 找出新增的 app
        let existingIDs = Set(pages.flatMap { $0 }.compactMap {
            if case .app(let id) = $0 { return id }
            return nil
        })
        let newItems = scanned
            .filter { !existingIDs.contains($0.bundleID) }
            .map { LayoutItem.app(bundleID: $0.bundleID) }

        // 将新 app 追加到末页（满页则新建一页）
        if !newItems.isEmpty {
            for item in newItems {
                if pages.isEmpty {
                    pages = [[item]]
                } else if pages[pages.count - 1].count < itemsPerPage {
                    pages[pages.count - 1].append(item)
                } else {
                    pages.append([item])
                }
            }
        }

        return LayoutData(pages: pages.isEmpty ? [newItems] : pages, folders: saved.folders)
    }
}

// MARK: - 文件夹操作

extension LaunchpadViewModel {

    /// 把两个 app 合并创建文件夹（拖拽 sourceID 到 targetID 上触发）
    func createFolder(sourceID: String, targetID: String, pageIndex: Int) {
        guard pageIndex < layout.pages.count else { return }
        var page = layout.pages[pageIndex]
        guard let srcIdx = page.firstIndex(of: .app(bundleID: sourceID)),
              let dstIdx = page.firstIndex(of: .app(bundleID: targetID)) else { return }

        let folder = FolderInfo(appIDs: [targetID, sourceID])
        layout.folders[folder.id] = folder

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
        layout.pages[pageIndex].removeAll { $0 == .app(bundleID: bundleID) }
        layout.folders[folderID]?.appIDs.append(bundleID)
        saveLayout()
    }

    /// 从文件夹内移出 app，文件夹只剩1个 app 时自动解散
    func removeAppFromFolder(bundleID: String, folderID: UUID, pageIndex: Int) {
        guard layout.folders[folderID] != nil else { return }
        layout.folders[folderID]?.appIDs.removeAll { $0 == bundleID }

        if let folder = layout.folders[folderID], folder.appIDs.count <= 1 {
            dissolveFolder(folderID: folderID, pageIndex: pageIndex)
        } else {
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
            let apps = folder.appIDs.map { LayoutItem.app(bundleID: $0) }
            page.insert(contentsOf: apps, at: min(folderIdx, page.count))
        }
        layout.pages[pageIndex] = page
        layout.folders.removeValue(forKey: folderID)
        saveLayout()
    }

    /// 重命名文件夹
    func renameFolder(id: UUID, newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        layout.folders[id]?.name = name.isEmpty ? "文件夹" : name
        layout.folders[id]?.isUserNamed = !name.isEmpty
        saveLayout()
    }
}
