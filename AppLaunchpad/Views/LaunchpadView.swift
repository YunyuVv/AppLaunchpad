import SwiftUI

/// 启动台全屏根视图
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var dragOffsetX: CGFloat = 0

    // 直接从主屏幕取宽度，避免 GeometryReader 在 NSHostingView 中返回错误尺寸
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

            // ── 关闭层：空白区域点击触发
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            // ── 内容层（最上层，自身拦截点击）
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
            // 每次出现都重置动画，确保重复显示时也有动画
            appeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                appeared = true
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.allApps.isEmpty {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(.white)
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
                Text("未找到应用")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                GridPageView(items: items, apps: viewModel.allApps, columns: cols,
                             onTapApp: { viewModel.launch($0) })
            }
        }
    }

    /// 多页横向滑动视图，宽度直接用屏幕宽度，不依赖 GeometryReader
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
        // 鼠标拖拽翻页（minimumDistance 保证点击图标不误触）
        .gesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffsetX = value.translation.width
                }
                .onEnded { value in
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                        dragOffsetX = 0
                    }
                    let threshold: CGFloat = 50
                    if value.translation.width < -threshold {
                        viewModel.goToNextPage()
                    } else if value.translation.width > threshold {
                        viewModel.goToPreviousPage()
                    }
                }
        )
    }
}
