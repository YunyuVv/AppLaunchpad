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

    // 键盘导航选中态
    var selectedSlotIndex: Int? = nil     // 当前页网格内选中的槽位
    var selectedSearchIndex: Int? = nil   // 搜索结果中选中的索引

    // 文件夹创建悬停进度计时器：拖到另一 App 上后 0.7s 内递增 folderProgress，满则进入文件夹模式
    private var folderProgressTimer: Timer? = nil
    // 边缘翻页计时器：拖拽到屏幕边缘时自动翻页
    private var edgeScrollTimer: Timer? = nil

    // MARK: - 翻页方向（供视图层 transition 使用）
    private(set) var pageFlipGoingForward: Bool = true

    // MARK: - 计算属性

    /// 仅按屏幕宽度自动决定的列数（不含用户手动覆盖），供 LaunchpadView 在覆盖值为 0 时调用
    func autoColumnCount(for screen: NSScreen) -> Int {
        switch screen.frame.width {                     // 根据屏幕宽度自动，宽屏多列
        case 2560...: return 12
        case 1920 ..< 2560: return 9
        case 1440 ..< 1920: return 7
        case 1280 ..< 1440: return 6
        default: return 5
        }
    }

    /// 仅按屏幕高度自动决定的每页行数（不含用户手动覆盖）
    func autoRowCount(for screen: NSScreen) -> Int {
        let h = screen.frame.height
        switch h {
        case 1200...: return 6
        case 900 ..< 1200: return 5
        default: return 4
        }
    }

    /// 每页列数：用户手动覆盖优先，否则按屏幕宽度自动
    func columnCount(for screen: NSScreen) -> Int {
        let override = UserPreferences.shared.columnCountOverride
        return override >= 3 ? min(override, 12) : autoColumnCount(for: screen)
    }

    /// 每页行数：用户手动覆盖优先，否则按屏幕高度自动
    func rowCount(for screen: NSScreen) -> Int {
        let override = UserPreferences.shared.rowCountOverride
        return override >= 3 ? min(override, 8) : autoRowCount(for: screen)
    }

    var itemsPerPage: Int {
        let screen = NSScreen.screens.first ?? NSScreen.screens[0]
        return columnCount(for: screen) * rowCount(for: screen)
    }

    var totalPages: Int { layout.pages.count }

    /// 当用户调整列数/行数导致 itemsPerPage 变化时，按新密度重新分页。
    /// 规则：保持所有图标的相对顺序，将当前所有 page 拍平后按新 pageSize 重切。
    func reflowLayout(to itemsPerPage: Int) {
        guard itemsPerPage > 0 else { return }
        let allItems = layout.pages.flatMap { $0 }
        guard !allItems.isEmpty else { return }
        layout.pages = allItems.chunked(into: itemsPerPage)
        currentPageIndex = min(currentPageIndex, max(0, layout.pages.count - 1))
        saveLayout()
    }

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
        stopFolderProgressTimer()
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

        // 切换到新槽位时：重置悬停进度与文件夹模式，重启进度计时器
        if slotIndex != prevSlot {
            dragState.folderTargetID = nil
            dragState.folderProgress = 0
            stopFolderProgressTimer()

            // 检查新槽位是否是另一个 app（原始布局，非预览）
            let page = dragState.sourcePageIndex
            guard page < layout.pages.count,
                  slotIndex < layout.pages[page].count,
                  case .app(let targetID) = layout.pages[page][slotIndex],
                  targetID != dragState.draggedBundleID else { return }

            // 拖到另一 app 上：0.7s 内递增 folderProgress，满则进入文件夹创建模式
            startFolderProgressTimer(targetID: targetID)
        }

        // 边缘翻页检测：拖拽到屏幕左/右边缘时自动翻页
        detectEdgeScroll(location: location)
    }

    // MARK: - 文件夹创建悬停进度

    private func startFolderProgressTimer(targetID: String) {
        let step: Double = 0.05
        let total: Double = 0.7
        folderProgressTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.dragState.isDragging else { return }
                let p = min(1, self.dragState.folderProgress + step / total)
                self.dragState.folderProgress = p
                if p >= 1 {
                    self.dragState.folderTargetID = targetID
                    self.stopFolderProgressTimer()
                }
            }
        }
    }

    private func stopFolderProgressTimer() {
        folderProgressTimer?.invalidate()
        folderProgressTimer = nil
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
        stopFolderProgressTimer()
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

    /// FSEvents 触发时调用：重新扫描并合并布局（保留用户排列，追加/移除变化的 App）
    func refreshApps() async {
        let scanned = await AppScanner.shared.scan()
        allApps = scanned
        layout = mergeLayout(saved: layout, scanned: scanned)
        // 如果当前页已不存在（如卸载 App 导致页数减少），回到第一页
        if currentPageIndex >= totalPages {
            currentPageIndex = max(0, totalPages - 1)
        }
    }

    func launch(_ app: AppInfo) {
        clearSelection()
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
        clearSelection()
    }

    // MARK: - 键盘导航

    /// 当前页的布局项（用于选中态计算）
    func currentPageItems() -> [LayoutItem] {
        currentPageIndex < layout.pages.count ? layout.pages[currentPageIndex] : []
    }

    /// 网格内移动选中（dx/dy 为方向；横向越界则翻页并把选中移到邻页对应位置）
    func moveGridSelection(dx: Int, dy: Int, columns: Int) {
        guard !isSearching else { return }
        let items = currentPageItems()
        guard !items.isEmpty else { return }
        let count = items.count
        let idx = selectedSlotIndex ?? -1
        if idx < 0 { selectedSlotIndex = 0; return }
        let newCol = (idx % columns) + dx
        let newRow = (idx / columns) + dy
        if newCol < 0 {
            guard currentPageIndex > 0 else { return }
            goToPreviousPage()
            selectedSlotIndex = columns - 1
            return
        }
        if newCol >= columns {
            guard currentPageIndex < totalPages - 1 else { return }
            goToNextPage()
            selectedSlotIndex = 0
            return
        }
        var newIdx = newRow * columns + newCol
        newIdx = min(max(newIdx, 0), count - 1)
        selectedSlotIndex = newIdx
    }

    /// 搜索结果内移动选中
    func moveSearchSelection(dx: Int, dy: Int, columns: Int) {
        guard isSearching else { return }
        let count = searchResults.count
        guard count > 0 else { return }
        let idx = selectedSearchIndex ?? -1
        if idx < 0 { selectedSearchIndex = 0; return }
        let newCol = min(max((idx % columns) + dx, 0), columns - 1)
        var newIdx = ((idx / columns) + dy) * columns + newCol
        newIdx = min(max(newIdx, 0), count - 1)
        selectedSearchIndex = newIdx
    }

    /// 回车：打开当前选中项
    func activateSelected() {
        if isSearching {
            if let i = selectedSearchIndex, i < searchResults.count {
                launch(searchResults[i])
            } else if let first = searchResults.first {
                launch(first)
            }
        } else if let idx = selectedSlotIndex,
                  idx < currentPageItems().count,
                  case .app(let id) = currentPageItems()[idx],
                  let app = allApps.first(where: { $0.bundleID == id }) {
            launch(app)
        }
    }

    /// 清除键盘选中态
    func clearSelection() {
        selectedSlotIndex = nil
        selectedSearchIndex = nil
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

        // 清理文件夹内已卸载的 app 引用；引用全部失效则解散该文件夹
        var folders = saved.folders
        for (id, var folder) in folders {
            let kept = folder.appIDs.filter { scannedIDs.contains($0) }
            if kept.isEmpty {
                folders.removeValue(forKey: id)
            } else if kept.count != folder.appIDs.count {
                folder.appIDs = kept
                folders[id] = folder
            }
        }

        return LayoutData(pages: pages.isEmpty ? [newItems] : pages, folders: folders)
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
