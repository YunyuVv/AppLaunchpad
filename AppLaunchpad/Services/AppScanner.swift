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

        let displayName =
            (plist["CFBundleDisplayName"] as? String) ??
            (plist["CFBundleName"] as? String) ??
            url.deletingPathExtension().lastPathComponent

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
}
