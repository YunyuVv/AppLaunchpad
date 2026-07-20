import Foundation

/// 单个已安装应用的完整信息，扫描后不可变
struct AppInfo: Identifiable, Hashable, Sendable {
    /// 使用 bundleID 作为唯一标识，比路径更稳定
    let id: String
    let bundleID: String
    let displayName: String
    let url: URL
    let isMASApp: Bool

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
