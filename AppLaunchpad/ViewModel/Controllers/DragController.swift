import AppKit
import Observation

/// 拖拽控制器：网格内「app 重排」的状态机 + 行为全集。
/// 落点由 GridGeometry 纯几何推导（光标 + 固定几何），与图标视觉位置无关，
/// 因此实时让位不会造成反馈振荡。文件夹功能已移除，本控制器只负责 app 重排。
@Observable
@MainActor
final class DragController {

    let data: LaunchpadData
    private let layoutService: LayoutService

    // 边缘翻页计时器：拖拽到屏幕边缘时自动翻页（必须加到 .common mode）
    private var edgeScrollTimer: Timer? = nil

    init(data: LaunchpadData, layoutService: LayoutService) {
        self.data = data
        self.layoutService = layoutService
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

    /// 拖拽中更新目标：由光标坐标经 GridGeometry 推导落点槽位（cursorSlot）。
    /// 不依赖 measured frame / 快照 / 最近中心点，与图标当前视觉位置无关。
    func updateDragTarget(location: CGPoint) {
        guard data.dragState.isDragging else { return }

        data.dragState.dragLocation = location

        // 边缘翻页检测：拖拽到屏幕左/右边缘时自动翻页（Timer 必须 .common）
        detectEdgeScroll(location: location)

        guard let geo = data.gridGeometry else { return }
        let slot = geo.slotUnderCursor(location)
        data.dragState.cursorSlot = slot
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
        let timer = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in
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

        // 重排落点：与拖拽中「让位预览」共用同一 move 语义，松手零跳变。
        // 用松手瞬间的精确坐标（dragLocation）按几何重算落点作为兜底，
        // 消除「最后一步 onChanged 与松手位置存在一格偏差」导致的偏移（落不到正位）。
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
            // 与 pageItemsWithDrag 预览完全一致：光标在哪儿 app 落在哪儿。
            // 之前同页走 `to > src ? to - 1` 会让 Typora 松手后偏左一格
            // （向右拖时光标已到 col3、Typora 落到 col2 → "没正确落位"）。
            let effectiveDst = to
            dstItems.insert(item, at: min(effectiveDst, dstItems.count))
            data.layout.pages[dstPage] = dstItems
        } else {
            // 异常情况：目标页不存在，把 app 放回源页原位
            srcItems.insert(item, at: src)
            data.layout.pages[sourcePage] = srcItems
        }
        data.saveLayout()

        data.dragState = DragState()
        // 拖拽结束后，若期间有被挂起的 FSEvents 应用刷新，立即补执行：
        // 此时 dragState 已复位（非 dragging），refreshApps 会正常跑且保留刚排好的顺序。
        if data.pendingAppsRefresh {
            data.pendingAppsRefresh = false
            Task { await layoutService.refreshApps() }
        }
    }

    /// 拖拽时返回当前页的"视觉排列"（让位预览数据源）。
    /// 同页：移除被拖 app 并插入 cursorSlot 让位；
    /// 翻页后目标页：把被拖 app 作为占位插入 cursorSlot 让位。
    func pageItemsWithDrag(pageIndex: Int) -> [LayoutItem] {
        guard data.dragState.isDragging,
              pageIndex < data.layout.pages.count else {
            return pageIndex < data.layout.pages.count ? data.layout.pages[pageIndex] : []
        }

        if pageIndex == data.dragState.sourcePageIndex {
            // 源页：把被拖 app 从原位拔出、插到当前光标槽位 — 其余 app 让位推开
            let src = data.dragState.sourceSlotIndex
            let to  = data.dragState.cursorSlot
            var items = data.layout.pages[pageIndex]
            guard src < items.count else { return items }
            let item = items.remove(at: src)
            items.insert(item, at: min(max(to, 0), items.count))
            return items
        } else if data.currentPageIndex == pageIndex {
            // 翻页后的目标页：占位插入 cursorSlot 让本页 app 推开
            let to = data.dragState.cursorSlot
            var items = data.layout.pages[pageIndex]
            items.insert(.app(bundleID: data.dragState.draggedBundleID),
                         at: min(max(to, 0), items.count))
            return items
        } else {
            return data.layout.pages[pageIndex]
        }
    }
}
