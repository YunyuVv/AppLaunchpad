import AppKit
import Observation

/// 启动台组合根（Composition Root）。
///
/// 设计目标：**把巨型 ViewModel 拆成职责单一的子控制器，改一块不影响其他**，
/// 同时用「薄壳转发」保持对 View 层的公开接口完全不变（View 零改动、回归风险最低）。
///
/// - 状态单一来源：`LaunchpadData`（data）
/// - 行为分流：`LayoutService` / `DragController` / `SearchController` / `NavigationController`
/// - 依赖方向：`Controller → Data`（单向）；`ViewModel → 组合所有`；`View → ViewModel`。
///
/// 想改拖拽 → 只动 `DragController`；各 Controller 互不牵连。
/// （文件夹功能已移除；如需恢复，作为独立 Controller + View 局部新增即可，见代码注释中的扩展点。）
@Observable
@MainActor
final class LaunchpadViewModel {

    // MARK: - 组合

    let data: LaunchpadData
    let layoutService: LayoutService
    let drag: DragController
    let search: SearchController
    let navigation: NavigationController

    init() {
        let data = LaunchpadData()
        let layoutService = LayoutService(data: data)
        let search = SearchController(data: data)
        let drag = DragController(data: data, layoutService: layoutService)
        let navigation = NavigationController(data: data, search: search)
        self.data = data
        self.layoutService = layoutService
        self.search = search
        self.drag = drag
        self.navigation = navigation
        // 选中项回车启动：由 NavigationController 回调，避免 Controller 反向依赖根 VM
        navigation.launcher = { [weak self] app in self?.launch(app) }
    }

    // MARK: - 状态转发（View 通过 viewModel.xxx 读写，底层落到 data）

    var allApps: [AppInfo] { data.allApps }
    var layout: LayoutData { data.layout }
    var isVisible: Bool { data.isVisible }
    var currentPageIndex: Int { get { data.currentPageIndex } set { data.currentPageIndex = newValue } }
    var searchText: String { get { data.searchText } set { data.searchText = newValue } }
    var isEditMode: Bool { data.isEditMode }
    var dragState: DragState { get { data.dragState } set { data.dragState = newValue } }
    var gridGeometry: GridGeometry? { get { data.gridGeometry } set { data.gridGeometry = newValue } }
    var selectedSlotIndex: Int? { get { data.selectedSlotIndex } set { data.selectedSlotIndex = newValue } }
    var selectedSearchIndex: Int? { get { data.selectedSearchIndex } set { data.selectedSearchIndex = newValue } }
    var totalPages: Int { data.totalPages }
    var pageFlipGoingForward: Bool { data.pageFlipGoingForward }

    var isSearching: Bool { search.isSearching }
    var searchResults: [AppInfo] { search.searchResults }

    // MARK: - 几何 / 布局（→ LayoutService）

    func autoColumnCount(for screen: NSScreen) -> Int { layoutService.autoColumnCount(for: screen) }
    func autoRowCount(for screen: NSScreen) -> Int { layoutService.autoRowCount(for: screen) }
    func columnCount(for screen: NSScreen) -> Int { layoutService.columnCount(for: screen) }
    func rowCount(for screen: NSScreen) -> Int { layoutService.rowCount(for: screen) }
    var itemsPerPage: Int { layoutService.itemsPerPage }
    func reflowLayout(to itemsPerPage: Int) { layoutService.reflowLayout(to: itemsPerPage) }

    // MARK: - 翻页（→ data）

    func goToPreviousPage() { data.goToPreviousPage() }
    func goToNextPage() { data.goToNextPage() }
    func goToPage(_ index: Int) { data.goToPage(index) }

    // MARK: - 编辑模式

    func enterEditMode() { data.isEditMode = true }
    func exitEditMode() {
        drag.resetEdgeScroll()
        data.isEditMode = false
        data.dragState = DragState()
    }

    // MARK: - 拖拽（→ DragController）

    func beginDrag(bundleID: String, pageIndex: Int, location: CGPoint) {
        drag.beginDrag(bundleID: bundleID, pageIndex: pageIndex, location: location)
    }
    func updateDragTarget(location: CGPoint) { drag.updateDragTarget(location: location) }
    func endDrag() { drag.endDrag() }
    func pageItemsWithDrag(pageIndex: Int) -> [LayoutItem] { drag.pageItemsWithDrag(pageIndex: pageIndex) }

    // 几何落点（→ data，纯几何）
    func slotUnderCursor(_ point: CGPoint, pageIndex: Int) -> Int? { data.slotUnderCursor(point, pageIndex: pageIndex) }
    func iconFootprintItemAt(_ point: CGPoint) -> (slot: Int, item: LayoutItem)? { data.iconFootprintItemAt(point) }
    func appAtIconPoint(_ point: CGPoint) -> String? { data.appAtIconPoint(point) }

    // MARK: - 搜索（→ SearchController 已通过属性转发；导航走 NavigationController）

    // MARK: - 键盘导航（→ NavigationController）

    func currentPageItems() -> [LayoutItem] { navigation.currentPageItems() }
    func moveGridSelection(dx: Int, dy: Int, columns: Int) { navigation.moveGridSelection(dx: dx, dy: dy, columns: columns) }
    func moveSearchSelection(dx: Int, dy: Int, columns: Int) { navigation.moveSearchSelection(dx: dx, dy: dy, columns: columns) }
    func activateSelected() { navigation.activateSelected() }
    func clearSelection() { data.clearSelection() }

    // MARK: - 应用生命周期 / 加载（→ LayoutService / data）

    func loadApps() async { await layoutService.loadApps() }
    func refreshApps() async { await layoutService.refreshApps() }
    func saveLayout() { data.saveLayout() }
    func show() { data.isVisible = true }
    func hide() {
        data.isVisible = false
        data.isEditMode = false
        data.dragState = DragState()
        data.searchText = ""
        data.currentPageIndex = 0
        navigation.clearSelection()
    }

    func launch(_ app: AppInfo) {
        navigation.clearSelection()
        exitEditMode()
        hide()
        NSWorkspace.shared.open(app.url)
    }
}
