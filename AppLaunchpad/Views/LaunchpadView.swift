import SwiftUI

/// 启动台全屏根视图
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var dragOffsetX: CGFloat = 0
    @State private var isDragging = false
    @State private var expandedFolder: FolderInfo? = nil

    private var pageWidth: CGFloat { NSScreen.screens.first?.frame.width ?? 1440 }
    private var targetScreen: NSScreen { NSScreen.screens.first ?? NSScreen.screens[0] }

    var body: some View {
        ZStack {
            BackgroundView().allowsHitTesting(false)

            // 关闭/退出编辑/收起文件夹层
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
                    onBeginDrag: { _, _ in }, onUpdateDragTarget: { _ in }, onEndDrag: {},
                    onDropOnFolder: nil
                )
            }
        }
    }

    private var pagingView: some View {
        let cols = viewModel.columnCount(for: targetScreen)
        let pageIdx = viewModel.currentPageIndex
        let pageItems = viewModel.isEditMode
            ? viewModel.pageItemsWithDrag(pageIndex: pageIdx)
            : (pageIdx < viewModel.layout.pages.count ? viewModel.layout.pages[pageIdx] : [])
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
            onBeginDrag: { id, slot in viewModel.beginDrag(bundleID: id, pageIndex: pageIdx, slotIndex: slot) },
            onUpdateDragTarget: { viewModel.updateDragTarget(slotIndex: $0) },
            onEndDrag: { viewModel.endDrag() },
            onDropOnFolder: { bundleID, folderID in
                viewModel.addAppToFolder(bundleID: bundleID, folderID: folderID, pageIndex: pageIdx)
            }
        )
        .offset(x: dragOffsetX)
        .id(viewModel.currentPageIndex)
        .transition(.asymmetric(insertion: .move(edge: insertEdge), removal: .move(edge: removeEdge)))
    }
}
