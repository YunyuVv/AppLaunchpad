import Foundation

/// 把数组按固定大小分块（用于按每页容量重新分页）。
/// 原散落在 LaunchpadViewModel 与 GridPageView 两处，现已统一到此处单一定义。
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
