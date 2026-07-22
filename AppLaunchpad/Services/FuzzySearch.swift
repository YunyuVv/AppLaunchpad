import Foundation

/// 轻量模糊搜索打分器。
///
/// 思路借鉴常见 fuzzy 匹配范式（归一化 + 分词 + 首字母缩写 + 子序列打分），
/// 纯 Swift 自研实现，不依赖任何第三方库。对 displayName / bundleID 均可打分，
/// 分数越高代表越相关（完全相等 1000 → 前缀 700 → token 前缀 520 →
/// 首字母缩写 470 → 子序列 300+ → 包含 180）。
struct FuzzySearcher {
    /// 归一化：去变音符/大小写/全角宽度，非字母数字统一转空格，再合并为连续串。
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined()
    }

    /// 分词：按非字母数字切分（保留每个 token 原串）。
    static func tokenize(_ value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    /// 首字母缩写：每个 token 首字符拼接（如 "Screen Flow" → "sf"）。
    static func acronym(_ tokens: [String]) -> String {
        tokens.compactMap { $0.first }.map(String.init).joined()
    }

    /// 对单个目标串打分；无法匹配返回 nil。
    func score(query: String, target: String) -> Int? {
        let nq = Self.normalize(query)
        guard !nq.isEmpty else { return nil }
        let nt = Self.normalize(target)
        guard !nt.isEmpty else { return nil }

        if nt == nq {
            return 1000
        }

        if nt.hasPrefix(nq) {
            return 700 - min(80, max(0, nt.count - nq.count))
        }

        let tokens = Self.tokenize(target)
        if let tokenIndex = tokens.firstIndex(where: { $0.hasPrefix(nq) }) {
            return 520 - min(tokenIndex * 15, 120)
        }

        let acr = Self.acronym(tokens)
        if !acr.isEmpty, acr.hasPrefix(nq) {
            return 470 - min(max(0, acr.count - nq.count) * 10, 80)
        }

        if let subsequenceScore = subsequenceScore(query: nq, target: nt) {
            return subsequenceScore
        }

        if nt.contains(nq) {
            return 180
        }

        return nil
    }

    /// 子序列匹配：query 的字符按顺序全出现在 target 中。
    /// 越紧凑、越靠前、越连续，分数越高。分散度过大会被丢弃以降噪。
    private func subsequenceScore(query: String, target: String) -> Int? {
        var positions: [Int] = []
        var searchStart = target.startIndex

        for character in query {
            guard let matchIndex = target[searchStart...].firstIndex(of: character) else {
                return nil
            }
            positions.append(target.distance(from: target.startIndex, to: matchIndex))
            searchStart = target.index(after: matchIndex)
        }

        guard let first = positions.first, let last = positions.last else { return nil }

        let span = last - first + 1
        let gaps = max(0, span - query.count)
        // 过滤极度分散的匹配（如长名中零星出现的字符），降低噪音。
        guard gaps <= query.count * 3 else { return nil }

        let adjacencyCount = zip(positions, positions.dropFirst()).reduce(0) { partial, pair in
            partial + (pair.1 == pair.0 + 1 ? 1 : 0)
        }
        let leadingBonus = max(0, 40 - first * 2)
        let compactnessBonus = max(0, 80 - gaps * 5)
        let adjacencyBonus = adjacencyCount * 12

        return 300 + leadingBonus + compactnessBonus + adjacencyBonus
    }
}
