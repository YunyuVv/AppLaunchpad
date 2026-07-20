import SwiftUI

/// 单页图标网格（LazyVGrid），列数由外部传入，最多 5 行
struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]
    let columns: Int
    let onTapApp: (AppInfo) -> Void

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(100), spacing: 20), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 30) {
            ForEach(items, id: \.self) { item in
                switch item {
                case .app(let bundleID):
                    if let app = apps.first(where: { $0.bundleID == bundleID }) {
                        AppIconView(app: app, onTap: { onTapApp(app) })
                    }
                case .folder:
                    // 文件夹占位，Phase 5 实现
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 60)
    }
}
