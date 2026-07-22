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

    /// 当前页各槽位的全局坐标框（由 GridPageView 通过 preference 写入），
    /// 供「把 app 从文件夹里拖出来落到网格某槽位」时计算最近目标槽位使用。
    var slotFrames: [Int: CGRect] = [:]

    /// 拖拽开始时对当前页槽位坐标框的「快照」。网格几何在各页完全一致（同 cols/rows），
    /// 因此该快照在跨页翻页后依然有效（坐标相同）。拖拽中网格会实时重排并伴随动画，
    /// 实时 slotFrames 会随之移动，故命中测试必须读这份固定快照，目标 app 才不会因让位而「逃跑」。
    var dragSlotFrames: [Int: CGRect] = [:]

    /// 快照所针对的页码。拖拽中跨页翻页后当前页几何会变（目标页 app 数量/行列可能不同），
    /// 下一次命中测试时据此把 dragSlotFrames 刷新为「当前页」的 slotFrames（当前页无实时让位动画，几何稳定）。
    private var dragSnapshotPage: Int = -1

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

    private let fuzzySearcher = FuzzySearcher()

    var searchResults: [AppInfo] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText
        return allApps
            .compactMap { app -> (AppInfo, Int)? in
                // 同时模糊匹配显示名与 bundleID，取较高分；0 分视为不匹配。
                let nameScore = fuzzySearcher.score(query: q, target: app.displayName) ?? 0
                let bundleScore = fuzzySearcher.score(query: q, target: app.bundleID) ?? 0
                let total = max(nameScore, bundleScore)
                guard total > 0 else { return nil }
                return (app, total)
            }
            .sorted {
                // 分数高者优先；同分按显示名升序，保证顺序稳定。
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending
            }
            .map { $0.0 }
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
        dragSlotFrames = [:]
    }

    // MARK: - 拖拽排序

    func beginDrag(bundleID: String, pageIndex: Int, location: CGPoint) {
        // 源槽位由布局实时查找，调用方无需传入（这样拖拽手势闭包可不依赖槽位下标，
        // 跨页时手势识别器才不会被重建）。
        guard let slot = layout.pages[pageIndex].firstIndex(of: .app(bundleID: bundleID)) else { return }
        dragState = DragState(
            isDragging: true,
            draggedBundleID: bundleID,
            context: .grid(pageIndex: pageIndex),
            sourcePageIndex: pageIndex,
            sourceSlotIndex: slot,
            targetSlotIndex: slot,
            dragLocation: location
        )
        // 快照当前页槽位坐标框（固定参照，供拖拽中实时让位时做稳定命中测试）
        dragSlotFrames = slotFrames
        dragSnapshotPage = pageIndex
    }

    func updateDragTarget(slotIndex: Int, location: CGPoint) {
        guard dragState.isDragging else { return }

        let prevSlot = dragState.targetSlotIndex
        dragState.targetSlotIndex = slotIndex
        dragState.dragLocation = location

        // 切换到新槽位时：判定新的悬停目标
        if slotIndex != prevSlot {
            let page = currentPageIndex
            guard page < layout.pages.count, slotIndex < layout.pages[page].count else { return }
            let newItem = layout.pages[page][slotIndex]

            // 实时让位动画会使目标 app 在网格中移动，nearestSlot（固定在 beginDrag 时的
            // 坐标快照）可能在同一 app 的原槽位 / 新槽位之间微小抖动。若新槽位仍指向
            // 「同一个目标 app」，则保持文件夹创建进度不重置，避免计时器反复重启、
            // 进度永远到不了 1 而无法建文件夹。
            if case .app(let newTargetID) = newItem,
               newTargetID == dragState.folderCandidateID {
                return
            }

            // 真正切换到不同目标：重置悬停进度与文件夹/文件夹悬停高亮，重启进度计时器
            dragState.folderTargetID = nil
            dragState.folderCandidateID = nil
            dragState.folderProgress = 0
            dragState.folderHoverID = nil
            stopFolderProgressTimer()

            switch newItem {
            case .app(let targetID) where targetID != dragState.draggedBundleID:
                // 拖到另一 app 上：0.7s 内递增 folderProgress，满则进入文件夹创建模式
                dragState.folderCandidateID = targetID
                startFolderProgressTimer(targetID: targetID)
            case .folder(let fid):
                // 拖到已有文件夹上：高亮反馈，松手即 addAppToFolder（不进入文件夹创建计时）
                dragState.folderHoverID = fid
            default:
                break
            }
        }

        // 边缘翻页检测：拖拽到屏幕左/右边缘时自动翻页
        detectEdgeScroll(location: location)
    }

    // MARK: - 文件夹创建悬停进度

    private func startFolderProgressTimer(targetID: String) {
        let step: Double = 0.05
        let total: Double = 0.7
        // 关键：拖拽手势进行中 AppKit 会把 runloop 切到 NSEventTrackingRunLoopMode，
        // 默认的 Timer.scheduledTimer 只加到 .default mode，在事件追踪模式下不会 fire，
        // 导致 folderProgress 永远停在 0、folderTargetID 永远不置位（无法创建文件夹）。
        // 必须显式加到 .common modes（同时覆盖 default 与 eventTracking）。
        let timer = Timer(timeInterval: step, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.dragState.isDragging else { return }
                let p = min(1, self.dragState.folderProgress + step / total)
                self.dragState.folderProgress = p
                if p >= 1 {
                    self.dragState.folderTargetID = targetID
                    self.dragState.folderCandidateID = nil
                    self.stopFolderProgressTimer()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        folderProgressTimer = timer
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
        // 同样必须加到 .common mode：拖拽中 runloop 在事件追踪模式，default-mode Timer 不 fire，
        // 否则拖到屏幕边缘永远不自动翻页（无法把 app 拖到下一页）。
        let timer = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.edgeScrollTimer = nil
                // 拖拽中翻页：把被拖的 app 真正搬移到目标页，
                // 让它在翻页后仍留在可见网格里（手势所在视图不被销毁），从而可继续自由拖拽。
                self.flipPageWhileDragging(goNext: goNext)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeScrollTimer = timer
    }

    /// 拖拽中自动翻页（边缘停留 0.8s 触发）。
    /// 现在拖拽手势挂在 GridPageView 层级，翻页时视图实例不重建，
    /// 因此只需切换 currentPageIndex，无需把被拖 app 搬移到目标页。
    private func flipPageWhileDragging(goNext: Bool) {
        guard dragState.isDragging,
              case .grid = dragState.context else { return }
        dragState.folderTargetID = nil
        dragState.folderCandidateID = nil
        dragState.folderProgress = 0
        dragState.folderHoverID = nil
        stopFolderProgressTimer()
        // 翻页后把目标槽位复位到源位：目标页不参与实时让位（sourcePageIndex != 当前页），
        // 复位可避免再次回到源页时残留上一次 targetSlotIndex 造成的错位让位；
        // 下一次 onChanged 会用新页几何重算 targetSlotIndex。
        dragState.targetSlotIndex = dragState.sourceSlotIndex
        if goNext {
            goToNextPage()
        } else {
            goToPreviousPage()
        }
    }

    private func stopEdgeScrollTimer() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
    }

    func endDrag() {
        stopFolderProgressTimer()
        stopEdgeScrollTimer()
        dragSlotFrames = [:]
        guard dragState.isDragging else { return }

        switch dragState.context {
        case .grid(let sourcePage):
            if let targetID = dragState.folderTargetID {
                // 文件夹创建模式：悬停在另一个 app 上 0.7s 后松手
                createFolder(sourceID: dragState.draggedBundleID, targetID: targetID, pageIndex: sourcePage)
            } else {
                // 跨页重排：从源页移除，插入到松手时所在页（currentPageIndex）的目标槽位
                let src = dragState.sourceSlotIndex
                let dstPage = currentPageIndex
                guard sourcePage < layout.pages.count else { dragState = DragState(); return }
                var srcItems = layout.pages[sourcePage]
                guard src < srcItems.count else { dragState = DragState(); return }
                let item = srcItems.remove(at: src)
                layout.pages[sourcePage] = srcItems

                // 重新计算落点：基于当前页几何（nearestSlot 跨页后已把快照刷新为当前页），
                // 避免沿用源页高位槽位索引、被 min(dst,count) 截断到末尾导致落点错位。
                let dst = nearestSlot(to: dragState.dragLocation, itemsCount: 0) ?? dragState.targetSlotIndex
                if dstPage < layout.pages.count {
                    var dstItems = layout.pages[dstPage]
                    // 同一页内移除后，目标索引需前移一位（若目标在原位置之后）
                    var effectiveDst = dst
                    if sourcePage == dstPage && dst > src { effectiveDst -= 1 }
                    dstItems.insert(item, at: min(effectiveDst, dstItems.count))
                    layout.pages[dstPage] = dstItems
                } else {
                    // 异常情况：目标页不存在，把 app 放回源页原位
                    srcItems.insert(item, at: src)
                    layout.pages[sourcePage] = srcItems
                }
                saveLayout()
            }
        case .folder:
            // 文件夹内拖拽由 commitFolderReorder / 拖出逻辑提交，这里仅兜底重置
            break
        }
        dragState = DragState()
    }

    /// 拖拽时返回当前页的"视觉排列"
    /// 文件夹创建模式下：保持原始排列（不做让位，目标 App 会高亮显示）
    /// 拖到文件夹上：文件夹保持静止（不重排让位，松手即 addAppToFolder）
    /// 普通重排模式下：被拖图标插入目标槽位，其余让位（实时让位弹簧动画的数据源）
    func pageItemsWithDrag(pageIndex: Int) -> [LayoutItem] {
        guard dragState.isDragging, dragState.sourcePageIndex == pageIndex,
              pageIndex < layout.pages.count else {
            return pageIndex < layout.pages.count ? layout.pages[pageIndex] : []
        }
        // 文件夹模式：原始排列不动，视觉高亮由 folderTargetID 驱动
        if dragState.isFolderMode { return layout.pages[pageIndex] }

        let dst = dragState.targetSlotIndex
        // 拖到文件夹上：不重排让位（文件夹保持静止，松手即 addAppToFolder）
        if dst < layout.pages[pageIndex].count,
           case .folder = layout.pages[pageIndex][dst] {
            return layout.pages[pageIndex]
        }

        var items = layout.pages[pageIndex]
        let src = dragState.sourceSlotIndex
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
        dragSlotFrames = [:]
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

        // 解散空文件夹后，同步把 pages 里指向已删除 folder 的槽位移除，避免网格出现空洞。
        pages = pages.map { page in
            page.filter { item in
                if case .folder(let id) = item { return folders[id] != nil }
                return true
            }
        }.filter { !$0.isEmpty }

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

    /// 给定全局坐标点，返回该点所在槽位的索引（要求点落在槽位 frame 内）。
    /// 专供拖拽起点判定，避免空白处点击被误判为点击了最近 app。
    func slotAt(_ point: CGPoint) -> Int? {
        guard !slotFrames.isEmpty else { return nil }
        return slotFrames.first { $0.value.contains(point) }?.key
    }

    /// 给定全局坐标点，返回当前页中最近的槽位索引（供拖拽落点计算）。
    func nearestSlot(to point: CGPoint, itemsCount: Int) -> Int? {
        // 拖拽中（网格上下文）做命中测试：
        // - 同一页内：用 beginDrag 时拍的固定快照 dragSlotFrames，避免实时让位动画导致
        //   slotFrames 移动而产生反馈抖动 / 目标逃跑。
        // - 跨页翻页后：当前页几何已变（目标页 app 数量/行列可能不同），下一次命中时把
        //   快照刷新为「当前页」的 slotFrames（当前页无实时让位动画，几何稳定），
        //   否则会沿用源页高位槽位索引，松手被 min(dst,count) 截断到末尾 → 落点错位。
        let frames: [Int: CGRect]
        if dragState.isDragging, case .grid = dragState.context {
            if currentPageIndex != dragSnapshotPage, !slotFrames.isEmpty {
                dragSlotFrames = slotFrames
                dragSnapshotPage = currentPageIndex
            }
            frames = dragSlotFrames.isEmpty ? slotFrames : dragSlotFrames
        } else {
            frames = slotFrames
        }
        guard !frames.isEmpty else { return nil }
        return frames.min { a, b in
            hypot(a.value.midX - point.x, a.value.midY - point.y) <
            hypot(b.value.midX - point.x, b.value.midY - point.y)
        }?.key
    }

    /// 取某页某槽位的布局项（供拖拽落点判定，读取实时布局，跨页翻页后也准确）
    func itemAt(pageIndex: Int, slot: Int) -> LayoutItem? {
        guard pageIndex >= 0, pageIndex < layout.pages.count,
              slot >= 0, slot < layout.pages[pageIndex].count else { return nil }
        return layout.pages[pageIndex][slot]
    }

    // MARK: - 文件夹内拖拽（与网格拖拽共用 DragState）

    /// 开始文件夹内拖拽：与网格 beginDrag 同款，但上下文标记为 .folder。
    /// 不进入编辑模式、不做"建子文件夹"计时、不触发边缘翻页。
    func beginFolderDrag(bundleID: String, folderID: UUID, slotIndex: Int, location: CGPoint) {
        dragSlotFrames = [:]
        dragState = DragState(
            isDragging: true,
            draggedBundleID: bundleID,
            context: .folder(folderID: folderID),
            sourceSlotIndex: slotIndex,
            targetSlotIndex: slotIndex,
            dragLocation: location
        )
    }

    /// 更新文件夹内拖拽目标槽位（基于文件夹内 cell 的全局坐标命中）。
    /// 仅更新 targetSlotIndex 与 dragLocation，不重排、不计时。
    func updateFolderDragTarget(folderID: UUID, targetIndex: Int, location: CGPoint) {
        guard dragState.isDragging,
              case .folder(let fid) = dragState.context, fid == folderID else { return }
        dragState.targetSlotIndex = targetIndex
        dragState.dragLocation = location
    }

    /// 提交文件夹内重排：把被拖 app 从 sourceSlotIndex 移到 targetSlotIndex。
    /// 不嵌套子文件夹（落在另一 app 上即视为插入重排）。
    func commitFolderReorder(folderID: UUID) {
        guard dragState.isDragging,
              case .folder(let fid) = dragState.context, fid == folderID else { return }
        let src = dragState.sourceSlotIndex
        let dst = dragState.targetSlotIndex
        guard var folder = layout.folders[folderID], src < folder.appIDs.count else { return }
        let id = folder.appIDs.remove(at: src)
        folder.appIDs.insert(id, at: min(dst, folder.appIDs.count))
        layout.folders[folderID] = folder
        saveLayout()
    }

    /// 把 app 从文件夹里拖出来，落到当前页最近的目标槽位。
    /// 文件夹剩 1 个 app 时自动解散，把剩余 app 也放回网格。
    func moveAppOutOfFolder(bundleID: String, dropLocation: CGPoint, pageIndex: Int) {
        guard let entry = layout.folders.first(where: { $0.value.appIDs.contains(bundleID) }) else { return }
        let folderID = entry.key
        var folder = entry.value

        let target = nearestSlot(to: dropLocation, itemsCount: layout.pages[pageIndex].count)
            ?? layout.pages[pageIndex].count

        folder.appIDs.removeAll { $0 == bundleID }
        layout.folders[folderID] = folder

        var page = layout.pages[pageIndex]
        if folder.appIDs.count <= 1 {
            // 解散文件夹：移除占位，把被拖出的 app 与剩余 app 依次放回网格
            guard let fidx = page.firstIndex(of: .folder(id: folderID)) else { return }
            page.remove(at: fidx)
            layout.folders.removeValue(forKey: folderID)
            let remaining = folder.appIDs.map { LayoutItem.app(bundleID: $0) }
            var insertAt = min(target, page.count)
            if target > fidx { insertAt = max(0, insertAt - 1) }   // 占位移除后索引左移修正
            page.insert(.app(bundleID: bundleID), at: insertAt)
            var idx = insertAt + 1
            for r in remaining {
                page.insert(r, at: min(idx, page.count))
                idx += 1
            }
        } else {
            page.insert(.app(bundleID: bundleID), at: min(target, page.count))
        }
        layout.pages[pageIndex] = page
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
