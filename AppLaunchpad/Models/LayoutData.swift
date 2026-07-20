import Foundation

/// 网格槽位的内容类型：单个应用或文件夹（Phase 5 启用文件夹）
enum LayoutItem: Hashable, Codable {
    case app(bundleID: String)
    case folder(id: UUID)
}

/// 所有页面的图标排列布局，支持 JSON 持久化
struct LayoutData: Codable {
    /// pages[pageIndex][slotIndex]，从左到右、从上到下排列
    var pages: [[LayoutItem]]
    var version: Int = 1

    init(pages: [[LayoutItem]] = []) {
        self.pages = pages
    }

    /// 将应用列表按每页容量均分，生成初始默认布局
    static func initial(from apps: [AppInfo], itemsPerPage: Int) -> LayoutData {
        guard itemsPerPage > 0 else { return LayoutData() }
        let items = apps.map { LayoutItem.app(bundleID: $0.bundleID) }
        let pages = stride(from: 0, to: items.count, by: itemsPerPage).map {
            Array(items[$0 ..< min($0 + itemsPerPage, items.count)])
        }
        return LayoutData(pages: pages)
    }
}
