import AppKit
import Observation

/// 拖拽控制器：网格内「app 重排 / 文件夹创建 / 添加到文件夹」的状态机。
/// 落点由 GridGeometry 纯几何推导（光标 + 固定几何），与图标视觉位置无关，
/// 因此实时让位不会造成反馈振荡。
@Observable
@MainActor
final class DragController {

    let data: LaunchpadData
    private let layoutService: LayoutService
    private let folderController: FolderController

    // 边缘翻页计时器：拖拽到屏幕边缘时自动翻页（必须加到 .common mode）
    private var edgeScrollTimer: Timer? = nil

    init(data: LaunchpadData, layoutService: LayoutService, folderController: FolderController) {
        self.data = data
        self.layoutService = layoutService
        self.folderController = folderController
    }

    // MARK: - 拖拽排序

    func beginDrag(bundleID: String, pageIndex: Int, location: CGPoint) {
        // 源槽位由布局实时查找，调用方无需传入（这样拖拽手势闭包可不依赖槽位下标，
        // 跨页时手势识别器才不会被重建）。
        guard let slot = data.layout.pages[pageIndex].firstIndex(of: .app(bundleID: bundleID)) else { return }
        data.dragState = DragState(
            isDragging: true,
            draggedBundleID: bundleID,
            sourcePageIndex: pageIndex,
            sourceSlotIndex: slot,
            cursorSlot: slot,
            dragLocation: location
        )
        // 落点由 GridGeometry 纯几何推导，无需拍坐标快照。
    }

    /// 文件夹拖拽起点：设置 draggedItemType = .folder，其余与 app 拖拽一致。
    func beginDrag(folderID: UUID, pageIndex: Int, location: CGPoint) {
        guard let slot = data.layout.pages[pageIndex].firstIndex(of: .folder(id: folderID)) else { return }
        data.dragState = DragState(
            isDragging: true,
            sourcePageIndex: pageIndex,
            sourceSlotIndex: slot,
            cursorSlot: slot,
            dragLocation: location,
            draggedItemType: .folder,
            draggedFolderID: folderID
        )
    }

    /// 拖拽中更新目标：①几何落点（cursorSlot → make-way）
    /// ②悬停目标检测（hoverTargetBundleID/FolderID）
    func updateDragTarget(location: CGPoint) {
        guard data.dragState.isDragging else { return }

        data.dragState.dragLocation = location

        // 边缘翻页检测：拖拽到屏幕左/右边缘时自动翻页（Timer 必须 .common）
        detectEdgeScroll(location: location)

        guard let geo = data.gridGeometry else { return }
        // ① 几何落点（用于 make-way）
        let slot = geo.slotUnderCursor(location)
        data.dragState.cursorSlot = slot

        // ② 悬停检测——仅 app 拖拽时触发（文件夹拖拽不做合并/嵌套）
        if data.dragState.draggedItemType == .app {
            detectHoverTarget(location: location, geo: geo)
        } else {
            clearHover()
        }
    }

    // MARK: - 悬停检测（文件夹创建 / 添加）

    /// 用"移除被拖 app 后的视觉布局"检测悬停目标。
    /// 内联计算布局（不调 pageItemsWithDrag），避免 hoverTarget → pageItemsWithDrag
    /// → detectHoverTarget → hoverTarget 的循环依赖。
    private func detectHoverTarget(location: CGPoint, geo: GridGeometry) {
        guard data.currentPageIndex < data.layout.pages.count else {
            clearHover(); return
        }
        // 视觉布局：原始布局减掉被拖 app（其余项自然左移）
        var visualItems = data.layout.pages[data.currentPageIndex]
        visualItems.removeAll {
            if case .app(let id) = $0, id == data.dragState.draggedBundleID { return true }
            return false
        }

        for (visSlot, item) in visualItems.enumerated() {
            let col = CGFloat(visSlot % geo.columns)
            let row = CGFloat(visSlot / geo.columns)
            let cellX = geo.origin.x + col * (geo.cellW + geo.hSpacing)
            let cellY = geo.origin.y + row * (geo.cellH + geo.vSpacing)

            let marginX = geo.cellW * 0.15
            let hitRect = CGRect(x: cellX + marginX, y: cellY,
                                 width: geo.cellW - 2 * marginX,
                                 height: geo.cellH)
            guard hitRect.contains(location) else { continue }

            switch item {
            case .app(let bundleID):
                if bundleID != data.dragState.draggedBundleID {
                    // hoverTargetBundleID 唯一标识目标，endDrag 用 findInPage 查位置
                    data.dragState.hoverTargetBundleID = bundleID
                    data.dragState.hoverTargetSlot = visSlot
                    data.dragState.hoverTargetFolderID = nil
                    return
                }
            case .folder(let folderID):
                data.dragState.hoverTargetFolderID = folderID
                data.dragState.hoverTargetSlot = visSlot
                data.dragState.hoverTargetBundleID = nil
                return
            }
        }
        clearHover()
    }

    private func clearHover() {
        data.dragState.hoverTargetBundleID = nil
        data.dragState.hoverTargetFolderID = nil
        data.dragState.hoverTargetSlot = nil
    }

    // MARK: - 边缘翻页

    private func detectEdgeScroll(location: CGPoint) {
        let screenWidth = NSScreen.screens.first?.frame.width ?? 1440
        let edgeZone: CGFloat = 100

        if location.x < edgeZone && data.currentPageIndex > 0 {
            startEdgeScrollTimer(goNext: false)
        } else if location.x > screenWidth - edgeZone && data.currentPageIndex < data.totalPages - 1 {
            startEdgeScrollTimer(goNext: true)
        } else {
            stopEdgeScrollTimer()
        }
    }

    private func startEdgeScrollTimer(goNext: Bool) {
        guard edgeScrollTimer == nil else { return }   // 已有计时器，不重复创建
        // 同样必须加到 .common mode：拖拽中 runloop 在事件追踪模式，default-mode Timer 不 fire，
        // 否则拖到屏幕边缘永远不自动翻页（无法把 app 拖到下一页）。
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.edgeScrollTimer = nil
                // 拖拽中翻页把光标所在视图不销毁，从而可继续自由拖拽。
                self.flipPageWhileDragging(goNext: goNext)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeScrollTimer = timer
    }

    /// 拖拽中自动翻页（边缘停留 0.8s 触发）。
    /// 拖拽手势挂在 LaunchpadView 根层级，翻页时视图实例不重建，
    /// 因此只需切换 currentPageIndex，无需把被拖 app 搬移到目标页。
    private func flipPageWhileDragging(goNext: Bool) {
        guard data.dragState.isDragging else { return }
        // 翻页后把几何落点复位到源位：目标页不参与实时让位（sourcePageIndex != 当前页），
        // 复位可避免残留上一次 cursorSlot 造成的错位让位；
        // 下一次 onChanged 会用新页几何重算 cursorSlot。
        data.dragState.cursorSlot = data.dragState.sourceSlotIndex
        if goNext {
            data.goToNextPage()
        } else {
            data.goToPreviousPage()
        }
    }

    private func stopEdgeScrollTimer() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
    }

    /// 退出编辑模式时由根 VM 调用：停止边缘翻页计时器
    func resetEdgeScroll() { stopEdgeScrollTimer() }

    func endDrag() {
        stopEdgeScrollTimer()
        guard data.dragState.isDragging else { return }

        // ═══ 悬停分支（优先于重排）═══

        // ── 分支 1：创建新文件夹（拖拽 app 到另一个 app 的 icon 上）──
        if let targetBundleID = data.dragState.hoverTargetBundleID {
            let draggedID = data.dragState.draggedBundleID
            let srcPage = data.dragState.sourcePageIndex

            // ① 先移除被拖 app（目标可能因此左移）
            removeFromPage(draggedID, pageIndex: srcPage)
            // ② 在移除被拖 app 之后，查询目标 app 的当前位置
            let targetSlot = findInPage(data.currentPageIndex, .app(bundleID: targetBundleID))
            // ③ 再移除目标 app
            removeFromPage(targetBundleID, pageIndex: data.currentPageIndex)
            // ④ 文件夹插入到目标 app 被移除前的位置
            let insertSlot = targetSlot.map { min($0, data.layout.pages[data.currentPageIndex].count) }
                             ?? min(data.dragState.hoverTargetSlot ?? data.dragState.cursorSlot,
                                    data.layout.pages[data.currentPageIndex].count)

            folderController.createFolder(
                containing: [draggedID, targetBundleID],
                atPage: data.currentPageIndex,
                atSlot: insertSlot
            )
            data.saveLayout()
            data.dragState = DragState()
            if data.pendingAppsRefresh { completePendingRefresh() }
            return
        }

        // ── 分支 2：添加到已有文件夹 ──
        if let targetFolderID = data.dragState.hoverTargetFolderID {
            let draggedID = data.dragState.draggedBundleID
            removeFromPage(draggedID, pageIndex: data.dragState.sourcePageIndex)
            folderController.addApp(draggedID, toFolder: targetFolderID)
            data.saveLayout()
            data.dragState = DragState()
            if data.pendingAppsRefresh { completePendingRefresh() }
            return
        }

        // ── 分支 3：普通重排 ──
        let src = data.dragState.sourceSlotIndex
        var to = data.dragState.cursorSlot
        if let geo = data.gridGeometry {
            to = geo.slotUnderCursor(data.dragState.dragLocation)
        }
        let sourcePage = data.dragState.sourcePageIndex
        let dstPage = data.currentPageIndex
        guard sourcePage < data.layout.pages.count else { data.dragState = DragState(); return }
        var srcItems = data.layout.pages[sourcePage]
        guard src < srcItems.count else { data.dragState = DragState(); return }
        let item = srcItems.remove(at: src)
        data.layout.pages[sourcePage] = srcItems

        if dstPage < data.layout.pages.count {
            var dstItems = data.layout.pages[dstPage]
            // 跨页防重复：目标页若已有同名 .app（之前 folder 拖出/历史 bug 留下的副本），
            // 先全部移除，避免 endDrag 插入后产生「两个一样的 app」。
            if sourcePage != dstPage,
               case .app(let id) = item {
                dstItems.removeAll {
                    if case .app(let other) = $0, other == id { return true }
                    return false
                }
            }
            // clamp 用 dstItems.count 而非 itemsPerPage-1：满页时两者相等；不满页时 itemsPerPage-1
            // 远大于 count 导致越界崩溃。用 dstItems.count 覆盖满/不满两种场景，永不越界。
            // （P0 修复，2026-07-25）
            let effectiveDst = min(max(to, 0), dstItems.count)
            dstItems.insert(item, at: effectiveDst)
            data.layout.pages[dstPage] = dstItems
        } else {
            // 异常情况：目标页不存在，把 app 放回源页原位
            srcItems.insert(item, at: src)
            data.layout.pages[sourcePage] = srcItems
        }
        data.saveLayout()

        data.dragState = DragState()
        if data.pendingAppsRefresh { completePendingRefresh() }
    }

    // MARK: - 辅助

    /// 从指定页中移除某个 app 的所有槽位。
    private func removeFromPage(_ bundleID: String, pageIndex: Int) {
        guard pageIndex < data.layout.pages.count else { return }
        data.layout.pages[pageIndex].removeAll {
            if case .app(let id) = $0, id == bundleID { return true }
            return false
        }
    }

    /// 在指定页中查找某个 LayoutItem 的槽位索引。
    private func findInPage(_ pageIndex: Int, _ target: LayoutItem) -> Int? {
        guard pageIndex < data.layout.pages.count else { return nil }
        return data.layout.pages[pageIndex].firstIndex(of: target)
    }

    private func completePendingRefresh() {
        data.pendingAppsRefresh = false
        Task { await layoutService.refreshApps() }
    }

    /// 拖拽时返回当前页的"视觉排列"（让位预览数据源）。
    /// 文件夹模式（hover 在 icon 上）：仅移除被拖 app，目标留在原位 → 网格留空。
    /// 排序模式（光标在缝隙）：正常 make-way。
    func pageItemsWithDrag(pageIndex: Int) -> [LayoutItem] {
        guard data.dragState.isDragging,
              pageIndex < data.layout.pages.count else {
            return pageIndex < data.layout.pages.count ? data.layout.pages[pageIndex] : []
        }

        // ── 文件夹模式：被拖 app 在网格中留空，仅浮动图标悬停在目标上方 ──
        if let _ = data.dragState.hoverTargetSlot,
           pageIndex == data.dragState.sourcePageIndex {
            let src = data.dragState.sourceSlotIndex
            var items = data.layout.pages[pageIndex]
            guard src < items.count else { return items }
            items.remove(at: src)  // 移除被拖 app，不 insert → 原位置留空
            return items
        }

        // ── 排序模式：正常 make-way ──
        if pageIndex == data.dragState.sourcePageIndex {
            // 源页：把被拖 app 从原位拔出、插到当前光标槽位  其余 app 让位推开
            let src = data.dragState.sourceSlotIndex
            let to  = data.dragState.cursorSlot
            var items = data.layout.pages[pageIndex]
            guard src < items.count else { return items }
            let item = items.remove(at: src)
            // clamp 用 items.count：满页时 = itemsPerPage-1；不满页时自动 append 到末尾。
            // （P0 修复，2026-07-25）
            items.insert(item, at: min(max(to, 0), items.count))
            return items
        } else if data.currentPageIndex == pageIndex {
            // 翻页后的目标页：根据拖拽项类型插入对应占位（app 或 folder）
            let to = data.dragState.cursorSlot
            var items = data.layout.pages[pageIndex]
            let placeholder: LayoutItem = data.dragState.draggedItemType == .folder
                ? .folder(id: data.dragState.draggedFolderID ?? UUID())
                : .app(bundleID: data.dragState.draggedBundleID)
            items.insert(placeholder, at: min(max(to, 0), items.count))
            return items
        } else {
            return data.layout.pages[pageIndex]
        }
    }
}
