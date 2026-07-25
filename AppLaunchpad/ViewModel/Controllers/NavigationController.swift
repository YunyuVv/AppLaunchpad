import AppKit
import Observation

/// 键盘导航控制器：方向键在网格 / 搜索结果内移动选中，回车启动选中项。
/// 通过 `launcher` 闭包回调启动 App，不直接依赖 LaunchpadViewModel（避免循环引用）。
@Observable
@MainActor
final class NavigationController {

    let data: LaunchpadData
    private let search: SearchController

    /// 由根 VM 注入：选中项回车时被调用，执行「清选中 → 退出编辑 → 隐藏 → 打开 App」。
    var launcher: ((AppInfo) -> Void)?

    init(data: LaunchpadData, search: SearchController) {
        self.data = data
        self.search = search
    }

    /// 当前页的布局项（用于选中态计算）
    func currentPageItems() -> [LayoutItem] {
        data.currentPageIndex < data.layout.pages.count ? data.layout.pages[data.currentPageIndex] : []
    }

    /// 网格内移动选中（dx/dy 为方向；横向越界则翻页并把选中移到邻页对应位置）
    func moveGridSelection(dx: Int, dy: Int, columns: Int) {
        guard !search.isSearching else { return }
        let items = currentPageItems()
        guard !items.isEmpty else { return }
        let count = items.count
        let idx = data.selectedSlotIndex ?? -1
        if idx < 0 { data.selectedSlotIndex = 0; return }
        let newCol = (idx % columns) + dx
        let newRow = (idx / columns) + dy
        if newCol < 0 {
            guard data.currentPageIndex > 0 else { return }
            data.goToPreviousPage()
            data.selectedSlotIndex = columns - 1
            return
        }
        if newCol >= columns {
            guard data.currentPageIndex < data.totalPages - 1 else { return }
            data.goToNextPage()
            data.selectedSlotIndex = 0
            return
        }
        var newIdx = newRow * columns + newCol
        newIdx = min(max(newIdx, 0), count - 1)
        data.selectedSlotIndex = newIdx
    }

    /// 搜索结果内移动选中：到达当前页边界时翻到上一页/下一页（←→ 跨列、↑↓ 跨行），否则按网格内移动
    func moveSearchSelection(dx: Int, dy: Int, columns: Int) {
        guard search.isSearching else { return }
        let count = search.searchResults.count
        guard count > 0 else { return }
        let perPage = max(data.searchItemsPerPage, 1)
        let totalPages = data.searchTotalPages
        // 列数优先用视图写入的 searchColumns（targetScreen 口径，与 searchItemsPerPage 同源），
        // 避免多显示器下 primaryScreen 与 targetScreen 列数不一致导致跨页边界判定错位。
        let columns = data.searchColumns > 0 ? data.searchColumns : columns
        let idx = data.selectedSearchIndex ?? -1
        if idx < 0 { data.selectedSearchIndex = 0; return }

        let page = idx / perPage
        let colInPage = idx % columns
        let rowInPage = (idx % perPage) / columns
        let rowsPerPage = max(perPage / columns, 1)

        if dx != 0 {
            // 左右：到当前页最右列 → 下一页首列；到最左列 → 上一页末列
            if dx > 0, colInPage == columns - 1, page < totalPages - 1 {
                data.goToSearchPage(page + 1)
                data.selectedSearchIndex = (page + 1) * perPage
                return
            }
            if dx < 0, colInPage == 0, page > 0 {
                data.goToSearchPage(page - 1)
                data.selectedSearchIndex = (page + 1) * perPage - 1
                return
            }
            let newCol = min(max(colInPage + dx, 0), columns - 1)
            var newIdx = page * perPage + rowInPage * columns + newCol
            newIdx = min(max(newIdx, 0), count - 1)
            data.selectedSearchIndex = newIdx
        } else if dy != 0 {
            let newRow = rowInPage + dy
            // 上：当前页首行 → 上一页同列末行
            if newRow < 0, page > 0 {
                data.goToSearchPage(page - 1)
                let prevStart = (page - 1) * perPage
                let prevCount = min(perPage, count - prevStart)
                let prevRows = max((prevCount + columns - 1) / columns, 1)
                data.selectedSearchIndex = prevStart + (prevRows - 1) * columns + colInPage
                return
            }
            // 下：当前页末行 → 下一页同列首行
            if newRow >= rowsPerPage, page < totalPages - 1 {
                data.goToSearchPage(page + 1)
                data.selectedSearchIndex = (page + 1) * perPage + colInPage
                return
            }
            var newIdx = page * perPage + newRow * columns + colInPage
            newIdx = min(max(newIdx, 0), count - 1)
            data.selectedSearchIndex = newIdx
        }
    }

    /// 回车：打开当前选中项
    func activateSelected() {
        if search.isSearching {
            if let i = data.selectedSearchIndex, i < search.searchResults.count {
                launcher?(search.searchResults[i])
            } else if let first = search.searchResults.first {
                launcher?(first)
            }
        } else if let idx = data.selectedSlotIndex,
                  idx < currentPageItems().count,
                  case .app(let id) = currentPageItems()[idx],
                  let app = data.allApps.first(where: { $0.bundleID == id }) {
            launcher?(app)
        }
    }

    /// 清除键盘选中态
    func clearSelection() {
        data.clearSelection()
    }
}
