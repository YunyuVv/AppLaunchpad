import SwiftUI

/// 启动台全屏根视图
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var dragOffsetX: CGFloat = 0
    // 记录本次拖拽方向，用于视觉反馈
    @State private var isDragging = false

    private var pageWidth: CGFloat {
        NSScreen.screens.first?.frame.width ?? 1440
    }
    private var targetScreen: NSScreen {
        NSScreen.screens.first ?? NSScreen.screens[0]
    }

    var body: some View {
        ZStack {
            // ── 背景（纯视觉）
            BackgroundView()
                .allowsHitTesting(false)

            // ── 交互层：承担全屏 tap 关闭 + 全屏 drag 翻页
            // simultaneousGesture 使 tap 和 drag 互不干扰
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .simultaneousGesture(pagingDragGesture)

            // ── 内容层（最上层，按钮/文本框拦截自身点击）
            VStack(spacing: 0) {
                SearchBarView(text: $viewModel.searchText)
                    .padding(.top, 56)

                Spacer()
                contentArea
                Spacer()
                pageIndicatorArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1.0 : 0)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: appeared)
        .onAppear {
            appeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { appeared = true }
        }
    }

    // MARK: - 全屏拖拽翻页手势

    private var pagingDragGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                guard !viewModel.isSearching else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffsetX = value.translation.width
                isDragging = true
            }
            .onEnded { value in
                guard !viewModel.isSearching else { return }
                isDragging = false
                let threshold: CGFloat = 50
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                    dragOffsetX = 0
                    if value.translation.width < -threshold {
                        viewModel.goToNextPage()
                    } else if value.translation.width > threshold {
                        viewModel.goToPreviousPage()
                    }
                }
            }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.allApps.isEmpty {
            ProgressView().progressViewStyle(.circular).scaleEffect(1.5).tint(.white)
        } else if viewModel.isSearching {
            searchResultsView
        } else {
            pagingView
        }
    }

    @ViewBuilder
    private var pageIndicatorArea: some View {
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

    private var searchResultsView: some View {
        let cols = viewModel.columnCount(for: targetScreen)
        let items = viewModel.searchResults.map { LayoutItem.app(bundleID: $0.bundleID) }
        return Group {
            if items.isEmpty {
                Text("未找到应用").font(.system(size: 18)).foregroundStyle(.white.opacity(0.6))
            } else {
                GridPageView(items: items, apps: viewModel.allApps, columns: cols,
                             onTapApp: { viewModel.launch($0) })
            }
        }
    }

    /// 多页视图：每次只渲染当前页，用 transition(.move) 模拟滑动
    /// 避免 HStack+offset+clipped 方案中 LazyVGrid 不渲染裁剪区外内容的问题
    private var pagingView: some View {
        let cols = viewModel.columnCount(for: targetScreen)
        let pageItems = viewModel.currentPageIndex < viewModel.layout.pages.count
            ? viewModel.layout.pages[viewModel.currentPageIndex]
            : []
        let insertEdge: Edge = viewModel.pageFlipGoingForward ? .trailing : .leading
        let removeEdge: Edge = viewModel.pageFlipGoingForward ? .leading  : .trailing

        return GridPageView(
            items: pageItems,
            apps: viewModel.allApps,
            columns: cols,
            onTapApp: { viewModel.launch($0) }
        )
        .offset(x: dragOffsetX)          // 拖拽中实时预览偏移
        .id(viewModel.currentPageIndex)  // 页码变化时强制替换视图
        .transition(.asymmetric(
            insertion: .move(edge: insertEdge),
            removal:   .move(edge: removeEdge)
        ))
    }
}
