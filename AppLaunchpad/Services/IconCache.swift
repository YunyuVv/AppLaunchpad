import AppKit

/// 应用图标内存缓存，actor 保证并发安全，NSCache 自动响应内存压力淘汰
actor IconCache {
    static let shared = IconCache()

    // NSCache 本身是线程安全的，提升为 static 以便 nonisolated 同步查询。
    // 用 nonisolated(unsafe) 绕过 Swift 6 隔离检查（NSCache 已保证线程安全）。
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()

    init() {
        // 最大缓存 50MB
        Self.cache.totalCostLimit = 50 * 1024 * 1024
    }

    /// 获取图标；缓存命中直接返回，未命中在后台线程加载后写入缓存
    func icon(for app: AppInfo) async -> NSImage {
        let key = app.bundleID as NSString
        if let cached = Self.cache.object(forKey: key) {
            return cached
        }
        let image = await Task.detached(priority: .utility) {
            NSWorkspace.shared.icon(forFile: app.url.path)
        }.value
        let cost = Int(image.size.width * image.size.height * 4)
        Self.cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 同步查询缓存（不触发加载）。用于视图重建时立即拿到已缓存图标，
    /// 避免翻页等场景下 AppIconView 重建导致图标短暂回 nil、显示灰色占位一闪。
    nonisolated static func cachedIcon(for app: AppInfo) -> NSImage? {
        Self.cache.object(forKey: app.bundleID as NSString)
    }

    /// 清空全部缓存（内存警告时调用）
    func clearAll() {
        Self.cache.removeAllObjects()
    }
}
