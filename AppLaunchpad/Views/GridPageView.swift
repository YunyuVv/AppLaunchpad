import SwiftUI

/// 单页图标网格，使用 VStack+HStack 行布局（非懒加载），确保 HStack+offset 翻页时所有 item 都能渲染
struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]
    let columns: Int
    let onTapApp: (AppInfo) -> Void

    var body: some View {
        let rows = items.chunked(into: columns)
        return VStack(spacing: 30) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowItems in
                HStack(spacing: 20) {
                    ForEach(rowItems, id: \.self) { item in
                        itemView(for: item)
                    }
                    // 最后一行不满时用透明占位保持对齐
                    if rowItems.count < columns {
                        ForEach(0..<(columns - rowItems.count), id: \.self) { _ in
                            Color.clear.frame(width: 100)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 60)
    }

    @ViewBuilder
    private func itemView(for item: LayoutItem) -> some View {
        switch item {
        case .app(let bundleID):
            if let app = apps.first(where: { $0.bundleID == bundleID }) {
                AppIconView(app: app, onTap: { onTapApp(app) })
            } else {
                Color.clear.frame(width: 100)
            }
        case .folder:
            // 文件夹占位，Phase 5 实现
            Color.clear.frame(width: 100)
        }
    }
}

private extension Array {
    /// 将数组按 size 分割为多行
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
