import AppKit
import Observation

/// 搜索控制器：根据 searchText 对 allApps 做模糊过滤，与拖拽 / 布局逻辑完全解耦。
@Observable
@MainActor
final class SearchController {

    let data: LaunchpadData
    private let fuzzySearcher = FuzzySearcher()

    init(data: LaunchpadData) {
        self.data = data
    }

    var searchResults: [AppInfo] {
        guard !data.searchText.isEmpty else { return [] }
        let q = data.searchText
        return data.allApps
            .compactMap { app -> (AppInfo, Int)? in
                // 同时模糊匹配显示名与 bundleID，取较高分；0 分视为不匹配。
                let nameScore = fuzzySearcher.score(query: q, target: app.displayName) ?? 0
                let bundleScore = fuzzySearcher.score(query: q, target: app.bundleID) ?? 0
                let total = max(nameScore, bundleScore)
                guard total > 0 else { return nil }
                return (app, total)
            }
            .sorted {
                // 分数高者优先；同分按显示名升序，保证顺序稳定。
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending
            }
            .map { $0.0 }
    }

    var isSearching: Bool { !data.searchText.isEmpty }
}
