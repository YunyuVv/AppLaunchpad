import Foundation

/// 轻量搜索打分器。
///
/// 策略参考 macOS 原生启动台：只匹配 hasPrefix / contains，**不做子序列乱序匹配**。
/// 原版的子序列打分（h-a-i 在不相邻位置也能命中）虽然"灵活"但会产生大量噪音——
/// 例如搜 "hai" 会把 Screen Sharing（s-h-a-r-i-n-g）、The Unarchiver（t-h-e-a-r-c-h-i-v-e-r）、
/// draw.io 的 bundleID（com.jgr**a**p**h**.dr**a**w**i**o.desktop）都搜出来，而真正含
/// "hai" 子串的 app 反而排到后面。这与原生 Launchpad 行为相去甚远。
///
/// 现在的打分优先级（高→低）：
/// - 完全相等 1000
/// - 前缀匹配 700- 偏移
/// - 子串包含 500   （**唯一**的"中间匹配"路径）
/// - token 前缀 420
/// - 首字母缩写 380
/// - 不匹配 → nil
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

        // 包含子串：500 分。仅当 hasPrefix 不命中时生效（位置靠后的"hai" 也能搜出来，
        // 例如 bundleID "com.haima.cloudpc" 搜 "hai"、displayName "The Unarchiver"
        // 搜 "arch" 等场景）。这与原生启动台行为一致——只匹配真正的子串，不过度泛化。
        if nt.contains(nq) {
            return 500
        }

        let tokens = Self.tokenize(target)
        if let tokenIndex = tokens.firstIndex(where: { $0.hasPrefix(nq) }) {
            return 420 - min(tokenIndex * 15, 120)
        }

        let acr = Self.acronym(tokens)
        if !acr.isEmpty, acr.hasPrefix(nq) {
            return 380 - min(max(0, acr.count - nq.count) * 10, 80)
        }

        // 不做子序列乱序匹配：之前太宽松导致搜 "hai" 把 Screen Sharing / The Unarchiver /
        // draw.io 等完全无关的 app 全搜出来。详见文件头注释。
        return nil
    }

    /// 占位空实现（保留以备将来扩展）。原版实现见 git history。
    private func subsequenceScore(query: String, target: String) -> Int? {
        return nil
    }
}
