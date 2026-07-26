import AppKit
import CoreServices
import Foundation
import os

/// 异步扫描 macOS 应用目录，过滤后台/纯系统内部应用，返回去重后的应用列表
actor AppScanner {
    static let shared = AppScanner()

    private let scanPaths: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
    ]

    /// 扫描所有路径，返回按名称排序、去重的应用列表
    func scan() async -> [AppInfo] {
        var seen = Set<String>()
        var result: [AppInfo] = []

        for base in scanPaths {
            for app in await Self.scanDirectoryDetached(base) {
                if seen.insert(app.bundleID).inserted {
                    result.append(app)
                }
            }
        }

        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: - Private（nonisolated static，可在 Task.detached 中安全调用）

    /// 在后台线程执行同步目录枚举，避免 Swift 6 并发限制
    private static func scanDirectoryDetached(_ url: URL) async -> [AppInfo] {
        await Task.detached(priority: .utility) {
            scanDirectorySync(url)
        }.value
    }

    private static func scanDirectorySync(_ url: URL) -> [AppInfo] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var apps: [AppInfo] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "app" else { continue }
            if let app = makeAppInfo(from: fileURL) {
                apps.append(app)
            }
            enumerator.skipDescendants()
        }
        return apps
    }

    private static func makeAppInfo(from url: URL) -> AppInfo? {
        // 解析真实 bundle：普通 app 用 Contents/Info.plist；包裹型/非标 app（如安居客）
        // 外层无 Contents/Info.plist，真实包内嵌在 Wrapper/Anjuke.app，且 Info.plist 在
        // 顶层而非 Contents/。bundleURL 用于读资源/验 MAS，launchURL 始终用最外层 url
        // （与 Finder/系统启动台一致，由系统按 wrapper 逻辑启动）；plistURL 是真正
        // 包含 Info.plist 的文件位置（由 resolveBundle 按实际找到的路径返回，避免
        // 误把正常 app 的 Info.plist 拼成顶层路径导致全部漏扫）。
        guard let (plistURL, bundleURL, launchURL) = resolveBundle(at: url) else { return nil }
        guard
            let plist = NSDictionary(contentsOf: plistURL),
            let bundleID = plist["CFBundleIdentifier"] as? String,
            !bundleID.isEmpty
        else { return nil }

        // 过滤纯后台应用
        if let v = plist["LSBackgroundOnly"] as? Bool, v { return nil }
        if let v = plist["LSBackgroundOnly"] as? String, v == "1" { return nil }
        if let v = plist["LSUIElement"] as? Bool, v { return nil }
        if let v = plist["LSUIElement"] as? String, v == "1" { return nil }

        // 显示名优先级：
        // 1) 本地化 InfoPlist.strings（按用户首选语言 + 实际 lproj 目录手动匹配，
        //    绕过 Foundation 在 CFBundleDevelopmentRegion="en" 且无 CFBundleLocalizations
        //    时 preferredLocalizations 错选 en 的 bug —— 例：wechatwebdevtools.app）
        // 2) Info.plist 字面量 CFBundleDisplayName
        // 3) CFBundleName
        // 4) .app 文件名
        let baseDisplayName =
            (plist["CFBundleDisplayName"] as? String) ??
            (plist["CFBundleName"] as? String) ??
            url.deletingPathExtension().lastPathComponent

        let displayName = localizedDisplayName(
            resourcesURL: bundleURL.appendingPathComponent("Contents/Resources"),
            developmentRegion: plist["CFBundleDevelopmentRegion"] as? String,
            fallback: baseDisplayName
        )

        // 系统级本地化兜底：当 app 自身 bundle 没有可用本地化时（多数苹果第一方应用
        // 如 Photos 的 zh_CN.lproj 为空、只有英文 CFBundleDisplayName="Photos"），
        // 用 Spotlight 的公开 API `NSMetadataItemDisplayNameKey`（对应 kMDItemDisplayName）
        // 取系统级中文名（"照片"），与访达/系统启动台一致。该 API 走 Spotlight 索引缓存，
        // 单次亚毫秒级，且结果按路径 memo 化，只在 bundle 无本地化时才会被调用，
        // 因此不会拖慢启动。无需任何私有符号 / dlsym。
        let finalDisplayName: String
        if displayName == baseDisplayName,
           let sysName = systemDisplayName(for: launchURL),
           sysName != displayName
        {
            finalDisplayName = sysName
        } else {
            finalDisplayName = displayName
        }

        let isMASApp = FileManager.default.fileExists(
            atPath: bundleURL.appendingPathComponent("Contents/_MASReceipt").path
        )
        || FileManager.default.fileExists(
            atPath: bundleURL.appendingPathComponent("_MASReceipt").path
        )

        return AppInfo(
            id: bundleID,
            bundleID: bundleID,
            displayName: finalDisplayName,
            url: launchURL,
            isMASApp: isMASApp
        )
    }

    // MARK: - 包裹型 / 非标 app 解析

    /// 解析候选 .app 的真实 Info.plist 位置，返回 `(plistURL, bundleURL, launchURL)`：
    /// - `plistURL`：Info.plist 的实际文件路径。
    /// - `bundleURL`：承载 Resources/_MASReceipt 的目录（正常 app = url；非标/包裹型
    ///   = 真实内层包）。
    /// - `launchURL`：始终为最外层 url（与 Finder/系统启动台一致，由系统走 wrapper 启动）。
    /// 支持两类非标准结构：
    /// 1) 包裹型 app：外层 .app 没有 Info.plist，真实可启动包内嵌在 `WrappedBundle`
    ///    软链指向的 .app 或 `Wrapper/*.app` 中（例：安居客 → Wrapper/Anjuke.app）。
    /// 2) 非标 app：Info.plist 不在 `Contents/` 下，直接裸在 bundle 顶层
    ///    （例：安居客内层的 Anjuke.app/Info.plist）。
    /// `depth` 用于防御 `WrappedBundle` 指向自身造成的无限递归。
    private static func resolveBundle(at url: URL, depth: Int = 0) -> (plistURL: URL, bundleURL: URL, launchURL: URL)? {
        guard depth < 4 else { return nil }

        // 1) 标准结构：Contents/Info.plist
        let contentsPlist = url.appendingPathComponent("Contents/Info.plist")
        if FileManager.default.fileExists(atPath: contentsPlist.path) {
            return (contentsPlist, url, url)
        }
        // 2) 非标结构：Info.plist 直接裸在 bundle 顶层
        let topPlist = url.appendingPathComponent("Info.plist")
        if FileManager.default.fileExists(atPath: topPlist.path) {
            return (topPlist, url, url)
        }
        // 3) 包裹型：WrappedBundle 软链 → 内层 .app
        let wrapped = url.appendingPathComponent("WrappedBundle")
        if let inner = try? URL(resolvingAliasFileAt: wrapped, options: [.withoutUI]),
           inner.pathExtension == "app",
           let resolved = resolveBundle(at: inner, depth: depth + 1)
        {
            return (resolved.plistURL, resolved.bundleURL, url)
        }
        // 4) 包裹型：Wrapper/*.app
        let wrapperDir = url.appendingPathComponent("Wrapper")
        if let subs = try? FileManager.default.contentsOfDirectory(at: wrapperDir, includingPropertiesForKeys: nil),
           let inner = subs.first(where: { $0.pathExtension == "app" }),
           let resolved = resolveBundle(at: inner, depth: depth + 1)
        {
            return (resolved.plistURL, resolved.bundleURL, url)
        }
        return nil
    }

    /// 按用户首选语言 + bundle 实际 lproj 目录手动挑最佳匹配，
    /// 读对应 lproj/InfoPlist.strings 里的 CFBundleDisplayName。
    ///
    /// 为什么不用 `Bundle.localizedString(forKey:table:)`：
    /// 腾讯 `wechatwebdevtools.app` 这种 CFBundleDevelopmentRegion="en" 且缺失
    /// CFBundleLocalizations 字段的 bundle，Foundation 的 preferredLocalizations
    /// 会错选 en（实测 `Bundle.preferredLocalizations` 返回 `["en"]` 而非 `["zh_CN"]`），
    /// 导致即使系统语言是中文，Foundation 也只读到 en.lproj/InfoPlist.strings 里的
    /// "Wechat Devtools"，拿不到 zh_CN.lproj/InfoPlist.strings 里的"微信开发者工具"。
    /// Spotlight(mdls) 在同样输入下能正确返回"微信开发者工具"，因此手写该匹配。
    private static func localizedDisplayName(
        resourcesURL: URL,
        developmentRegion: String?,
        fallback: String
    ) -> String {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: resourcesURL.path)) ?? []
        let lprojDirs = contents.filter { $0.hasSuffix(".lproj") }
        guard !lprojDirs.isEmpty else { return fallback }

        var candidates: [String] = []
        for userLang in Locale.preferredLanguages {
            let underscore = userLang.replacingOccurrences(of: "-", with: "_")
            let parts = underscore.split(separator: "_")
            let lang = parts.first.map(String.init) ?? ""
            // 地区码取最后一个（用户语言形如 zh-Hans-CN 时，最后一个 "CN" 才是地区；
            // 中间的 "Hans" 是脚本/方言变体，不要当作地区处理，否则会生成
            // "zh_Hans.lproj" 这种几乎不存在的目录名导致匹配失败）。
            let last = parts.last.map(String.init) ?? ""
            let region = (parts.count > 1 && last != lang) ? last : ""
            // 形如 zh-Hans-CN.lproj（极少见，但放上以防万一个别 app 用横线 lproj）
            candidates.append("\(userLang).lproj")
            // 形如 zh_Hans_CN.lproj
            if !underscore.isEmpty && underscore != userLang {
                candidates.append("\(underscore).lproj")
            }
            // 形如 zh_CN.lproj（最常见：bundle 走下划线、用户语言带横线）
            if !lang.isEmpty && !region.isEmpty {
                candidates.append("\(lang)_\(region).lproj")
            }
            // 形如 zh.lproj（仅主语言）
            if !lang.isEmpty {
                candidates.append("\(lang).lproj")
            }
        }
        if let dev = developmentRegion, !dev.isEmpty {
            candidates.append("\(dev).lproj")
        }

        for c in candidates {
            if lprojDirs.contains(c),
               let dict = NSDictionary(contentsOf: resourcesURL.appendingPathComponent(c).appendingPathComponent("InfoPlist.strings")),
               let name = dict["CFBundleDisplayName"] as? String,
               !name.isEmpty
            {
                return name
            }
        }
        return fallback
    }

    // MARK: - 系统级本地化显示名（兜底 Photos 等第一方应用）

    /// 系统级本地化名缓存（按 app 路径）。扫描整进程只发生有限次，缓存避免重复查询
    /// Spotlight 元数据；即使被多次调用也只付一次成本，确保不影响启动速度。
    private static let systemNameCache = OSAllocatedUnfairLock<[String: String?]>(initialState: [:])

    /// 取系统级本地化显示名（Spotlight 公开 API，对应 `mdls -name kMDItemDisplayName`）。
    /// 返回与访达/系统启动台一致的系统级 App 名（如 Photos → "照片"），来源是系统级
    /// App 名数据库，而非 bundle 自身 lproj。仅在 app 自身 bundle 无可用本地化时由
    /// `makeAppInfo` 调用。返回 nil 表示无法获取，此时沿用原显示名。
    private static func systemDisplayName(for url: URL) -> String? {
        if let cached = systemNameCache.withLock({ $0[url.path] }) { return cached }
        let result: String? = {
            guard let item = NSMetadataItem(url: url) else { return nil }
            guard let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String,
                  !name.isEmpty else { return nil }
            return name
        }()
        systemNameCache.withLock { $0[url.path] = result }
        return result
    }
}
