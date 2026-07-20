import SwiftUI

/// 启动台全屏根视图：背景 + 图标网格
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    var body: some View {
        ZStack {
            // 背景层：点击空白区域关闭
            BackgroundView()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.hide() }

            VStack(spacing: 0) {
                Spacer().frame(height: 80)  // 搜索框预留位（Phase 2）

                if viewModel.allApps.isEmpty {
                    loadingView
                } else {
                    currentPageView
                }

                Spacer()
                Spacer().frame(height: 40)  // 页码指示器预留位（Phase 2）
            }
            // VStack 自身不拦截点击，空白区域事件穿透到背景层
            .allowsHitTesting(false)
            .overlay {
                // 只有图标区域恢复点击响应
                currentPageOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// 在与 VStack 相同位置叠加可交互的图标层
    private var currentPageOverlay: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 80)
            if !viewModel.allApps.isEmpty {
                currentPageView
                    .allowsHitTesting(true)
            }
            Spacer()
            Spacer().frame(height: 40)
        }
    }
}
