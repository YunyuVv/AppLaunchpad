import AppKit

/// 应用图标内存缓存，actor 保证并发安全，NSCache 自动响应内存压力淘汰
actor IconCache {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        // 最大缓存 50MB
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    /// 获取图标；缓存命中直接返回，未命中在后台线程加载后写入缓存
    func icon(for app: AppInfo) async -> NSImage {
        let key = app.bundleID as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let image = await Task.detached(priority: .utility) {
            NSWorkspace.shared.icon(forFile: app.url.path)
        }.value
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 清空全部缓存（内存警告时调用）
    func clearAll() {
        cache.removeAllObjects()
    }
}
