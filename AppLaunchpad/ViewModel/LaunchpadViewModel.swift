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

    // MARK: - 计算属性

    /// 根据屏幕宽度动态决定每行列数
    func columnCount(for screen: NSScreen) -> Int {
        switch screen.frame.width {
        case 1440...: return 7
        case 1280 ..< 1440: return 6
        default: return 5
        }
    }

    /// 每页图标容量（固定 5 行）
    var itemsPerPage: Int {
        columnCount(for: NSScreen.main ?? NSScreen.screens[0]) * 5
    }

    var totalPages: Int { layout.pages.count }

    /// 搜索结果：前缀匹配排在前面，其余按名称排序
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

    // MARK: - Actions

    /// 后台扫描应用并初始化布局
    func loadApps() async {
        let scanned = await AppScanner.shared.scan()
        allApps = scanned
        layout = LayoutData.initial(from: scanned, itemsPerPage: itemsPerPage)
    }

    /// 启动应用，同时关闭启动台
    func launch(_ app: AppInfo) {
        hide()
        NSWorkspace.shared.open(app.url)
    }

    func show() {
        isVisible = true
    }

    func hide() {
        isVisible = false
        isEditMode = false
        searchText = ""
        currentPageIndex = 0
    }
}
