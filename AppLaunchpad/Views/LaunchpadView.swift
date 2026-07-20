import SwiftUI

/// 启动台全屏根视图
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void   // 保留兼容，不再使用外部窗口

    @State private var appeared = false
    @State private var dragOffsetX: CGFloat = 0
    @State private var isDragging = false
    @State private var expandedFolder: FolderInfo? = nil
    @State private var showSettingsOverlay = false   // 面板内设置浮层

    private var pageWidth: CGFloat { NSScreen.screens.first?.frame.width ?? 1440 }
    private var targetScreen: NSScreen { NSScreen.screens.first ?? NSScreen.screens[0] }

    var body: some View {
        ZStack {
            BackgroundView().allowsHitTesting(false)

            // 关闭/退出编辑/收起文件夹层，右键弹出上下文菜单
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if expandedFolder != nil {
                        withAnimation(.spring(duration: 0.25)) { expandedFolder = nil }
                    } else if viewModel.isEditMode {
                        viewModel.exitEditMode()
                    } else {
                        onDismiss()
                    }
                }
                .simultaneousGesture(pagingDragGesture)
                .contextMenu {
                    if viewModel.isEditMode {
                        Button("完成编辑") { viewModel.exitEditMode() }
                        Divider()
                    }
                    Button("设置...") { openSettings() }
                    Divider()
                    Button("关闭启动台") { onDismiss() }
                }

            // 内容层
            VStack(spacing: 0) {
                SearchBarView(text: $viewModel.searchText).padding(.top, 56)
                Spacer()
                contentArea
                Spacer()
                pageIndicatorArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 文件夹展开浮层
            if let folder = expandedFolder {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                FolderExpandedView(
                    folder: folder,
                    apps: viewModel.allApps,
                    isEditMode: viewModel.isEditMode,
                    onTapApp: { app in
                        withAnimation { expandedFolder = nil }
                        viewModel.launch(app)
                    },
                    onRemoveApp: { bundleID in
                        viewModel.removeAppFromFolder(
                            bundleID: bundleID,
                            folderID: folder.id,
                            pageIndex: viewModel.currentPageIndex
                        )
                        // 若文件夹解散，关闭展开视图
                        if viewModel.layout.folders[folder.id] == nil {
                            withAnimation { expandedFolder = nil }
                        } else {
                            expandedFolder = viewModel.layout.folders[folder.id]
                        }
                    },
                    onRename: { newName in
                        viewModel.renameFolder(id: folder.id, newName: newName)
                        expandedFolder = viewModel.layout.folders[folder.id]
                    }
                )
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            // 设置浮层（面板内渲染，不依赖外部 NSWindow）
            if showSettingsOverlay {
                settingsOverlay
            }

            // 拖拽浮动图标：跟随鼠标自由移动，不参与命中检测
            floatingDragIcon
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

    // MARK: - 全屏拖拽翻页（非编辑模式）

    private var pagingDragGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                guard !viewModel.isSearching, !viewModel.isEditMode, expandedFolder == nil else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffsetX = value.translation.width
                isDragging = true
            }
            .onEnded { value in
                guard !viewModel.isSearching, !viewModel.isEditMode, expandedFolder == nil else { return }
                isDragging = false
                let threshold: CGFloat = 50
                let goNext = value.translation.width < -threshold
                let goPrev = value.translation.width > threshold
                dragOffsetX = 0
                if goNext || goPrev {
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                        if goNext { viewModel.goToNextPage() }
                        else      { viewModel.goToPreviousPage() }
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
            pagingView.clipped()
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
                GridPageView(
                    items: items, apps: viewModel.allApps, folders: [:],
                    columns: cols, pageIndex: 0, isEditMode: false, dragState: DragState(),
                    onTapApp: { viewModel.launch($0) }, onTapFolder: { _ in },
                    onLongPress: {}, onDeleteApp: nil,
                    onBeginDrag: { _, _, _ in }, onUpdateDragTarget: { _, _ in }, onEndDrag: {},
                    onDropOnFolder: nil
                )
            }
        }
    }

    private var pagingView: some View {
        let cols = viewModel.columnCount(for: targetScreen)
        let pageIdx = viewModel.currentPageIndex
        // 拖拽中始终使用原始布局（不做让位预览），松手后才动画归位
        // 这样 B 不会在 A 靠近时逃跑，文件夹创建才可行
        let pageItems = pageIdx < viewModel.layout.pages.count
            ? viewModel.layout.pages[pageIdx]
            : []
        let insertEdge: Edge = viewModel.pageFlipGoingForward ? .trailing : .leading
        let removeEdge: Edge = viewModel.pageFlipGoingForward ? .leading  : .trailing

        return GridPageView(
            items: pageItems,
            apps: viewModel.allApps,
            folders: viewModel.layout.folders,
            columns: cols,
            pageIndex: pageIdx,
            isEditMode: viewModel.isEditMode,
            dragState: viewModel.dragState,
            onTapApp: { viewModel.launch($0) },
            onTapFolder: { folder in
                guard expandedFolder == nil else { return }
                withAnimation(.spring(duration: 0.25, bounce: 0.1)) { expandedFolder = folder }
            },
            onLongPress: { viewModel.enterEditMode() },
            onDeleteApp: { _ in },
            onBeginDrag: { id, slot, loc in viewModel.beginDrag(bundleID: id, pageIndex: pageIdx, slotIndex: slot, location: loc) },
            onUpdateDragTarget: { slot, loc in viewModel.updateDragTarget(slotIndex: slot, location: loc) },
            onEndDrag: { viewModel.endDrag() },
            onDropOnFolder: { bundleID, folderID in
                viewModel.addAppToFolder(bundleID: bundleID, folderID: folderID, pageIndex: pageIdx)
            }
        )
        .offset(x: dragOffsetX)
        .id(viewModel.currentPageIndex)
        .transition(.asymmetric(insertion: .move(edge: insertEdge), removal: .move(edge: removeEdge)))
    }

    // MARK: - 拖拽浮动图标

    /// 跟随鼠标的浮动图标（置于所有内容之上，不拦截事件）
    @ViewBuilder
    private var floatingDragIcon: some View {
        let ds = viewModel.dragState
        if ds.isDragging,
           let app = viewModel.allApps.first(where: { $0.bundleID == ds.draggedBundleID }) {
            AppIconView(
                app: app,
                isEditMode: false,   // 浮动图标不显示抖动/删除按钮
                onTap: {},
                onLongPress: {},
                onDelete: nil
            )
            .scaleEffect(1.12)
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
            .allowsHitTesting(false)
            .position(ds.dragLocation)
            .zIndex(999)
            .transition(.opacity)
        }
    }

    // MARK: - 辅助

    private func openSettings() {
        withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
            showSettingsOverlay = true
        }
    }

    // MARK: - 设置浮层（面板内渲染，不依赖外部 NSWindow / presentationOptions）

    private var settingsOverlay: some View {
        ZStack {
            // 背景遮罩，点击关闭
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(duration: 0.25)) { showSettingsOverlay = false }
                }

            // 设置卡片
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Text("设置")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.25)) { showSettingsOverlay = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                SettingsView()
                    .frame(height: 300)
            }
            .frame(width: 480)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
            .contentShape(Rectangle())
            .onTapGesture {}    // 阻止点击穿透到背景
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .zIndex(500)
    }
}
