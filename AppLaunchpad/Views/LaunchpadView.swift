import SwiftUI

/// 启动台全屏根视图：背景 + 搜索框 + 多页翻页 + 页码指示器 + 呼出动画
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    let onDismiss: () -> Void

    @State private var appeared = false
    // 翻页时的偏移量（由 WindowController 的 scrollWheel 驱动）
    @State private var dragOffsetX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── 背景（纯视觉，不拦截点击）
                BackgroundView()
                    .allowsHitTesting(false)

                // ── 关闭层：放在内容之前（ZStack 中靠下），空白区域点击时触发
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }

                // ── 内容层：放在关闭层之后（ZStack 最上层），自身拦截点击
                VStack(spacing: 0) {
                    // 搜索框：自身可交互，阻止点击穿透到关闭层
                    SearchBarView(text: $viewModel.searchText)
                        .padding(.top, 56)
                        .onTapGesture {}   // 吸收点击，防止穿透触发 dismiss

                    Spacer()

                    if viewModel.allApps.isEmpty {
                        loadingView
                    } else if viewModel.isSearching {
                        searchResultsView(width: geo.size.width)
                    } else {
                        pagingView(width: geo.size.width)
                    }

                    Spacer()

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
                // VStack 自身没有背景，空白区域点击会穿透到下层 Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1.0 : 0)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: appeared)
        .onAppear { appeared = true }
    }

    // MARK: - 供 WindowController 驱动翻页偏移

    func updateDragOffset(_ offset: CGFloat) {
        dragOffsetX = offset
    }

    // MARK: - Subviews

    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(1.5)
            .tint(.white)
    }

    private func searchResultsView(width: CGFloat) -> some View {
        let cols = viewModel.columnCount(for: NSScreen.screens.first ?? NSScreen.screens[0])
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

    private func pagingView(width: CGFloat) -> some View {
        let cols = viewModel.columnCount(for: NSScreen.screens.first ?? NSScreen.screens[0])
        return HStack(spacing: 0) {
            ForEach(0..<viewModel.totalPages, id: \.self) { i in
                let items = i < viewModel.layout.pages.count ? viewModel.layout.pages[i] : []
                GridPageView(items: items, apps: viewModel.allApps, columns: cols,
                             onTapApp: { viewModel.launch($0) })
                    .frame(width: width)
            }
        }
        .offset(x: -CGFloat(viewModel.currentPageIndex) * width + dragOffsetX)
        .animation(.spring(duration: 0.3, bounce: 0.1), value: viewModel.currentPageIndex)
        .animation(.interactiveSpring(response: 0.25), value: dragOffsetX)
    }
}
