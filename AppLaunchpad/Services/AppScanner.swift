import AppKit
import Foundation

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
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
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
            resourcesURL: url.appendingPathComponent("Contents/Resources"),
            developmentRegion: plist["CFBundleDevelopmentRegion"] as? String,
            fallback: baseDisplayName
        )

        let isMASApp = FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Contents/_MASReceipt").path
        )

        return AppInfo(
            id: bundleID,
            bundleID: bundleID,
            displayName: displayName,
            url: url,
            isMASApp: isMASApp
        )
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
}
