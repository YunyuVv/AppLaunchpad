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
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) { dragOffsetX = 0 }
                let threshold: CGFloat = 50
                if value.translation.width < -threshold {
                    viewModel.goToNextPage()
                } else if value.translation.width > threshold {
                    viewModel.goToPreviousPage()
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

    /// 多页视图：HStack 全量渲染所有页，offset 偏移实现翻页动画
    private var pagingView: some View {
        let cols = viewModel.columnCount(for: targetScreen)
        let w = pageWidth
        return HStack(spacing: 0) {
            ForEach(0..<viewModel.totalPages, id: \.self) { i in
                let items = i < viewModel.layout.pages.count ? viewModel.layout.pages[i] : []
                GridPageView(items: items, apps: viewModel.allApps, columns: cols,
                             onTapApp: { viewModel.launch($0) })
                    .frame(width: w)
            }
        }
        .frame(width: w, alignment: .leading)
        .clipped()
        .offset(x: -CGFloat(viewModel.currentPageIndex) * w + dragOffsetX)
        .animation(.spring(duration: 0.3, bounce: 0.1), value: viewModel.currentPageIndex)
        .animation(.interactiveSpring(response: 0.25), value: dragOffsetX)
    }
}
