import SwiftUI

/// 启动台全屏根视图：背景 + 图标网格
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    /// 关闭回调由 LaunchpadWindowController 注入，确保 panel.orderOut 被正确调用
    let onDismiss: () -> Void

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    var body: some View {
        ZStack {
            // 背景：纯视觉，不拦截点击
            BackgroundView()
                .allowsHitTesting(false)

            // 内容层
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                if viewModel.allApps.isEmpty {
                    loadingView
                } else {
                    currentPageView
                }

                Spacer()
                Spacer().frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 整个根视图兜底：按钮优先消费图标区域的点击，空白区域触发 dismiss
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
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
