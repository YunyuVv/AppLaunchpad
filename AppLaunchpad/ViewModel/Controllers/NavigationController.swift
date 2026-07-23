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

    /// 搜索结果内移动选中
    func moveSearchSelection(dx: Int, dy: Int, columns: Int) {
        guard search.isSearching else { return }
        let count = search.searchResults.count
        guard count > 0 else { return }
        let idx = data.selectedSearchIndex ?? -1
        if idx < 0 { data.selectedSearchIndex = 0; return }
        let newCol = min(max((idx % columns) + dx, 0), columns - 1)
        var newIdx = ((idx / columns) + dy) * columns + newCol
        newIdx = min(max(newIdx, 0), count - 1)
        data.selectedSearchIndex = newIdx
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
