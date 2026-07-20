import SwiftUI

/// 启动台全屏根视图：背景 + 图标网格，点击空白区域关闭
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    var body: some View {
        ZStack {
            // 背景层：纯视觉，不拦截点击
            BackgroundView()
                .allowsHitTesting(false)

            // 内容层
            VStack(spacing: 0) {
                Spacer().frame(height: 80)   // 搜索框预留位（Phase 2）

                if viewModel.allApps.isEmpty {
                    loadingView
                } else {
                    currentPageView
                }

                Spacer()
                Spacer().frame(height: 40)   // 页码指示器预留位（Phase 2）
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 整个根视图可点击：图标按钮优先拦截自身点击，空白区域触发 hide
        .contentShape(Rectangle())
        .onTapGesture { viewModel.hide() }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(1.5)
            .tint(.white)
    }

    private var currentPageView: some View {
        let cols = viewModel.columnCount(for: screen)
        let pageItems: [LayoutItem] = viewModel.currentPageIndex < viewModel.layout.pages.count
            ? viewModel.layout.pages[viewModel.currentPageIndex]
            : []
        return GridPageView(
            items: pageItems,
            apps: viewModel.allApps,
            columns: cols,
            onTapApp: { viewModel.launch($0) }
        )
    }
}
