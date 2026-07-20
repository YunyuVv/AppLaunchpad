import Foundation

/// 网格槽位的内容类型：单个应用或文件夹
enum LayoutItem: Hashable, Codable {
    case app(bundleID: String)
    case folder(id: UUID)
}

/// 所有页面的图标排列布局，支持 JSON 持久化
struct LayoutData: Codable {
    var pages: [[LayoutItem]]
    var folders: [UUID: FolderInfo]
    var version: Int = 1

    init(pages: [[LayoutItem]] = [], folders: [UUID: FolderInfo] = [:]) {
        self.pages = pages
        self.folders = folders
    }

    static func initial(from apps: [AppInfo], itemsPerPage: Int) -> LayoutData {
        guard itemsPerPage > 0 else { return LayoutData() }
        let items = apps.map { LayoutItem.app(bundleID: $0.bundleID) }
        let pages = stride(from: 0, to: items.count, by: itemsPerPage).map {
            Array(items[$0 ..< min($0 + itemsPerPage, items.count)])
        }
        return LayoutData(pages: pages)
    }
}
