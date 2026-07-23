import Foundation

/// 网格槽位的内容类型：单个应用或文件夹。
/// 注：文件夹功能当前已移除，`pages` 运行时只含 `.app`；`.folder` 仅保留作为
/// 数据兼容 / 未来扩展点（旧 layout.json 可由 mergeLayout 展开为 app）。
enum LayoutItem: Hashable, Codable {
    case app(bundleID: String)
    case folder(id: UUID)
}

/// 所有页面的图标排列布局，支持 JSON 持久化。
/// 注：`folders` 当前为惰性字段（始终为空），仅保留用于未来恢复文件夹特性；
/// 运行时布局不含 `.folder` 项。
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
