import AppKit
import Observation

/// 共享状态容器：所有 UI 可变状态的单一数据源（Single Source of Truth）。
/// 只持有状态 + 极简无副作用动作（翻页、清除选中、几何落点读取），
/// 不包含业务编排逻辑；具体行为由各 Controller 通过对 `data` 的读写完成。
///
/// 这样拆分后：改拖拽只动 `DragController`、改搜索只动 `SearchController`，
/// 彼此不牵连，出问题能一眼定位到具体控制器。
@Observable
@MainActor
final class LaunchpadData {

    // MARK: - 核心数据

    var allApps: [AppInfo] = []
    var layout: LayoutData = LayoutData()

    // MARK: - UI 状态

    var isVisible: Bool = false
    var currentPageIndex: Int = 0
    var searchText: String = ""
    var isEditMode: Bool = false
    var dragState: DragState = DragState()

    /// 网格几何（全局坐标系），由 LaunchpadView 的 GeometryReader 持续写入。
    /// 拖拽期间稳定（网格容器不移动），落点纯几何推导，无需测量每个 cell 的实时坐标框、
    /// 也无需拖拽起手拍快照，从根本上消除「实时让位 ↔ 快照命中」的反馈振荡。
    /// 标 @ObservationIgnored：其变更不触发 SwiftUI 重渲染（避免设值→通知→重渲染死循环）。
    @ObservationIgnored var gridGeometry: GridGeometry? = nil

    /// 拖拽进行中被 FSEvents 触发的「应用刷新」请求挂起标记。
    /// 拖拽中若收到 refreshApps，直接置位并跳过（避免重建 layout.pages 让拖拽索引失效）；
    /// 拖拽结束后由 DragController 补执行，从而既保住刚排好的顺序、又不错过应用变更。
    @ObservationIgnored var pendingAppsRefresh: Bool = false

    // 键盘导航选中态
    var selectedSlotIndex: Int? = nil     // 当前页网格内选中的槽位
    var selectedSearchIndex: Int? = nil   // 搜索结果中选中的索引

    // 翻页方向（供视图层 transition 使用）
    private(set) var pageFlipGoingForward: Bool = true

    // MARK: - 极简动作（仅读写本容器状态，无外部依赖）

    var totalPages: Int { layout.pages.count }

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

    func clearSelection() {
        selectedSlotIndex = nil
        selectedSearchIndex = nil
    }

    // MARK: - 持久化

    /// 委托 LayoutStore 异步保存当前布局（原子写 layout.json）。
    /// 保存前清理空页：某页所有 app 被拖走/移入文件夹后无需保留空白页。
    func saveLayout() {
        var current = layout
        current.pages = current.pages.filter { !$0.isEmpty }
        layout = current
        // 空页清理后 currentPageIndex 可能越界（如最后一页变空被移除）
        if currentPageIndex >= current.pages.count {
            currentPageIndex = max(0, current.pages.count - 1)
        }
        Task.detached { await LayoutStore.shared.save(current) }
    }

    // MARK: - 几何落点（取代 measured frame / 快照 / 最近中心点）

    /// 由光标坐标经 GridGeometry 推导其所在槽位（0..cols*rows-1）。
    /// 落点纯几何、确定性强、与图标当前视觉位置无关 —— 拖拽让位不会造成反馈振荡。
    func slotUnderCursor(_ point: CGPoint, pageIndex: Int) -> Int? {
        guard let geo = gridGeometry else { return nil }
        return geo.slotUnderCursor(point)
    }

    /// 光标是否落在某「图标 footprint（图标实际方形，不含 cell 间隙）」内，
    /// 返回对应槽位与布局项。用于区分「压在 app 图标上（重排落点）」与「落在间隙（重排）」。
    func iconFootprintItemAt(_ point: CGPoint) -> (slot: Int, item: LayoutItem)? {
        guard let geo = gridGeometry,
              let slot = slotUnderCursor(point, pageIndex: currentPageIndex),
              geo.iconRect(forSlot: slot).contains(point) else { return nil }
        guard slot < layout.pages[currentPageIndex].count else { return nil }
        return (slot, layout.pages[currentPageIndex][slot])
    }

    /// 起手判定：光标是否压在 app 图标上（footprint 内且为 app）。
    /// 返回该 app 的 bundleID；否则（间隙 / 文件夹 / 空白）返回 nil，交给翻页 / 点击处理。
    func appAtIconPoint(_ point: CGPoint) -> String? {
        guard let (_, item) = iconFootprintItemAt(point) else { return nil }
        if case .app(let bundleID) = item { return bundleID }
        return nil
    }

    /// 起手判定：光标是否压在文件夹图标上（footprint 内且为 folder）。
    /// 返回文件夹 UUID；否则返回 nil。
    func folderAtIconPoint(_ point: CGPoint) -> UUID? {
        guard let (_, item) = iconFootprintItemAt(point) else { return nil }
        if case .folder(let id) = item { return id }
        return nil
    }

    /// 起手判定：光标是否压在任何一个图标 footprint 上（app 或文件夹）。
    /// 用于翻页手势的放行判断。
    func anyItemAtIconPoint(_ point: CGPoint) -> Bool {
        iconFootprintItemAt(point) != nil
    }
}
