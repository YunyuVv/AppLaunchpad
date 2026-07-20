import SwiftUI

/// 启动台全屏根视图：背景 + 搜索框 + 多页翻页 + 页码指示器 + 呼出/关闭动画
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    let onDismiss: () -> Void

    // 呼出动画控制
    @State private var appeared = false
    // 触控板横向拖拽偏移量
    @State private var dragOffsetX: CGFloat = 0

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    var body: some View {
        ZStack {
            // ── 背景（纯视觉）
            BackgroundView()
                .allowsHitTesting(false)

            // ── 主体内容
            VStack(spacing: 0) {
                // 搜索框
                SearchBarView(text: $viewModel.searchText)
                    .padding(.top, 56)

                Spacer()

                // 图标区域
                if viewModel.allApps.isEmpty {
                    loadingView
                } else if viewModel.isSearching {
                    searchResultsView
                } else {
                    pagingView
                }

                Spacer()

                // 页码指示器（搜索时隐藏）
                if !viewModel.isSearching && viewModel.totalPages > 1 {
                    PageIndicatorView(
                        totalPages: viewModel.totalPages,
                        currentPage: viewModel.currentPageIndex,
                        onTap: { viewModel.goToPage($0) }
                    )
                } else {
                    Spacer().frame(height: 46)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 呼出动画：整体从缩放+透明淡入
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1.0 : 0)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: appeared)
        .onAppear { appeared = true }
        // 空白区域点击关闭
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        // 触控板双指横向滑动翻页
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard !viewModel.isSearching else { return }
                    dragOffsetX = value.translation.width
                }
                .onEnded { value in
                    guard !viewModel.isSearching else { return }
                    let threshold: CGFloat = 60
                    if value.translation.width < -threshold {
                        viewModel.goToNextPage()
                    } else if value.translation.width > threshold {
                        viewModel.goToPreviousPage()
                    }
                    dragOffsetX = 0
                }
        )
    }

    // MARK: - Subviews

    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(1.5)
            .tint(.white)
    }

    /// 搜索结果页（单页展示匹配项）
    private var searchResultsView: some View {
        let cols = viewModel.columnCount(for: screen)
        let items = viewModel.searchResults.map { LayoutItem.app(bundleID: $0.bundleID) }
        return Group {
            if items.isEmpty {
                Text("未找到应用")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                GridPageView(
                    items: items,
                    apps: viewModel.allApps,
                    columns: cols,
                    onTapApp: { viewModel.launch($0) }
                )
            }
        }
    }

    /// 多页翻页视图（水平 HStack + offset 偏移）
    private var pagingView: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            HStack(spacing: 0) {
                ForEach(0..<viewModel.totalPages, id: \.self) { pageIndex in
                    pageContent(pageIndex: pageIndex)
                        .frame(width: pageWidth)
                }
            }
            // 通过偏移量实现翻页，加上拖拽中的实时偏移
            .offset(x: -CGFloat(viewModel.currentPageIndex) * pageWidth + dragOffsetX)
            .animation(.spring(duration: 0.3, bounce: 0.1), value: viewModel.currentPageIndex)
            .animation(.interactiveSpring(), value: dragOffsetX)
        }
    }

    private func pageContent(pageIndex: Int) -> some View {
        let cols = viewModel.columnCount(for: screen)
        let items = pageIndex < viewModel.layout.pages.count
            ? viewModel.layout.pages[pageIndex]
            : []
        return GridPageView(
            items: items,
            apps: viewModel.allApps,
            columns: cols,
            onTapApp: { viewModel.launch($0) }
        )
    }
}
