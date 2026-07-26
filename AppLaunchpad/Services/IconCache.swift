import AppKit

/// 应用图标内存缓存，actor 保证并发安全，NSCache 自动响应内存压力淘汰。
///
/// 性能要点（修复首开/翻页卡顿）：
/// 1) 取回系统图标后**预缩放**到目标尺寸再缓存，避免缓存 1024² 原图造成的
///    内存膨胀与每帧 GPU 缩放开销；显示 60~90pt 图标时 128pt（Retina 256 物理）
///    足够清晰、且不糊。
/// 2) 启动/刷新扫描完成后调用 `prewarm` 在后台批量预热全部图标，使首屏与翻页
///    时 `cachedIcon` 直接命中缓存，不在主线程做磁盘 IO（根治首次卡顿）。
actor IconCache {
    static let shared = IconCache()

    // NSCache 本身是线程安全的，提升为 static 以便 nonisolated 同步查询。
    // 用 nonisolated(unsafe) 绕过 Swift 6 隔离检查（NSCache 已保证线程安全）。
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()

    /// 预缩放目标尺寸（点）。Retina 下物理像素 = 2x，128pt → 256 物理像素，
    /// 覆盖 60~90pt 显示需求且余量充足，比原生 1024px 原图省约 16x 内存/纹理。
    private nonisolated static let targetSize = NSSize(width: 128, height: 128)

    init() {
        // 最大缓存 50MB，最多 2000 个图标
        Self.cache.totalCostLimit = 50 * 1024 * 1024
        Self.cache.countLimit = 2000
    }

    /// 获取图标；缓存命中直接返回，未命中在后台线程加载并缩放后写入缓存。
    func icon(for app: AppInfo) async -> NSImage {
        let key = app.bundleID as NSString
        if let cached = Self.cache.object(forKey: key) {
            return cached
        }
        let image = await Task.detached(priority: .utility) {
            let raw = NSWorkspace.shared.icon(forFile: app.url.path)
            return Self.resized(raw) ?? raw
        }.value
        let cost = Int(image.size.width * image.size.height * 4)
        Self.cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 批量预热：后台一次性把全部 app 图标加载、缩放并缓存。
    /// 调用后首屏/翻页时 `cachedIcon` 全部命中，不在主线程做磁盘 IO。
    /// 幂等：已缓存的跳过，可安全重复调用（如 FSEvents 刷新后）。
    func prewarm(_ apps: [AppInfo]) {
        Task.detached(priority: .utility) { [apps] in
            for app in apps {
                let key = app.bundleID as NSString
                guard Self.cache.object(forKey: key) == nil else { continue }
                let raw = NSWorkspace.shared.icon(forFile: app.url.path)
                guard let resized = Self.resized(raw) else { continue }
                let cost = Int(resized.size.width * resized.size.height * 4)
                Self.cache.setObject(resized, forKey: key, cost: cost)
            }
        }
    }

    /// 同步查询缓存（不触发异步加载）。用于视图重建时立即拿到已缓存图标，
    /// 避免翻页等场景下 AppIconView 重建导致图标短暂回 nil、显示灰色占位一闪。
    /// 若缓存未命中，则同步取系统图标、缩放并回填缓存（兜底）——保证视图重建时
    /// 永远有图标、不闪灰。这样即使翻页动画取消了淡入（整页滑动、opacity 恒 1.0），
    /// 也绝不会出现灰框。
    nonisolated static func cachedIcon(for app: AppInfo) -> NSImage? {
        let key = app.bundleID as NSString
        if let cached = Self.cache.object(forKey: key) {
            return cached
        }
        // 兜底：同步取系统图标并缩放回填缓存。NSWorkspace 本身有系统级缓存，
        // 单次取图标开销极小；预热已覆盖绝大多数 app，此处仅兜底极少数冷图标。
        let raw = NSWorkspace.shared.icon(forFile: app.url.path)
        let result = Self.resized(raw) ?? raw
        Self.cache.setObject(result, forKey: key)
        return result
    }

    /// 清空全部缓存（内存警告时调用）
    func clearAll() {
        Self.cache.removeAllObjects()
    }

    // MARK: - 缩放

    /// 把系统原图（常为 1024×1024）等比缩放到目标尺寸，省内存、渲染更快。
    /// 已小于目标的图直接返回（无需缩放）。缩放出错时返回 nil（调用方回退原图）。
    private nonisolated static func resized(_ image: NSImage) -> NSImage? {
        let max = targetSize
        guard image.size.width > max.width || image.size.height > max.height else {
            return image
        }
        let new = NSImage(size: max)
        new.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: max),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        new.unlockFocus()
        return new
    }
}
