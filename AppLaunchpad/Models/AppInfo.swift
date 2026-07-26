import Foundation

/// 单个已安装应用的完整信息，扫描后不可变
struct AppInfo: Identifiable, Hashable, Sendable {
    /// 使用 bundleID 作为唯一标识，比路径更稳定
    let id: String
    let bundleID: String
    let displayName: String
    let url: URL
    let isMASApp: Bool
    /// 标记该 app 自身 bundle 无可用本地化、扫描阶段先用 bundle 名（可能英文）顶替，
    /// 需后台异步用 Spotlight 取系统级中文名（Photos→"照片"）补查。默认 false。
    let needsSystemNameResolution: Bool

    init(id: String, bundleID: String, displayName: String, url: URL, isMASApp: Bool, needsSystemNameResolution: Bool = false) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.url = url
        self.isMASApp = isMASApp
        self.needsSystemNameResolution = needsSystemNameResolution
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
