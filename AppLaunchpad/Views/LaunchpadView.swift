import SwiftUI
import AppKit

/// 启动台全屏根视图
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var dragOffsetX: CGFloat = 0
    @State private var isDragging = false
    @State private var expandedFolder: FolderInfo? = nil
    // 直接观察同一个 UserPreferences 单例：行列数/间距/边距均在此读取，
    // 设置面板拖动滑块时会立即触发本视图重新布局（实时生效）。
    @Bindable private var prefs = UserPreferences.shared

    /// 目标显示器：跟随设置中的多显示器模式，与窗口定位（WindowController.primaryScreen）保持一致
    private var targetScreen: NSScreen {
        switch UserPreferences.shared.multiMonitorMode {
        case .primaryScreen:
            return NSScreen.screens.first ?? NSScreen.screens[0]
        case .mouseScreen:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouse) }
                ?? NSScreen.screens.first ?? NSScreen.screens[0]
        }
    }

    /// 根据可用内容尺寸计算图标尺寸，让网格在水平/垂直方向都尽量撑满。
    /// 图标最大尺寸可由用户通过「图标最大尺寸」限制；设为 0 时自动撑满。
    private func computeIconSize(contentSize: CGSize, columns: Int, rows: Int) -> CGFloat {
        let cols = CGFloat(columns)
        let rows = CGFloat(rows)
        let hSpacing = CGFloat(prefs.horizontalSpacing)
        let vSpacing = CGFloat(prefs.verticalSpacing)
        let sidePad = CGFloat(prefs.sidePadding)
        let topPad = CGFloat(prefs.topPadding)
        let bottomPad = CGFloat(prefs.bottomPadding)
        let maxIcon = CGFloat(prefs.iconSizeOverride > 0 ? prefs.iconSizeOverride : 1024)

        let availW = contentSize.width - 2 * sidePad - hSpacing * (cols - 1)
        let cellW = max(40, availW / cols)
        let availH = contentSize.height - topPad - bottomPad - vSpacing * (rows - 1)
        let cellH = max(40, availH / rows)

        // 标签预算：2 行文字 + 6pt 间距。字体大小随图标放大，但最高 16pt，避免过大。
        var iconSize = min(cellW - 24, cellH * 0.9, maxIcon)
        for _ in 0..<5 {
            let fontSize = min(max(10, iconSize * 0.14), 16)
            let labelBudget = 2 * fontSize + 6
            let target = min(cellW - 24, cellH - labelBudget, maxIcon)
            if abs(target - iconSize) < 0.5 { break }
            iconSize = target
        }
        return max(24, iconSize)
    }

    var body: some View {
        GeometryReader { geo in
            // 行列数直接读 prefs（被 @Bindable 观察），保证设置面板拖动滑块时实时刷新。
            // 覆盖值 >=3 用用户指定；否则按屏幕宽高自动。
            let cols = prefs.columnCountOverride >= 3
                ? min(prefs.columnCountOverride, 12)
                : viewModel.autoColumnCount(for: targetScreen)
            let rows = prefs.rowCountOverride >= 3
                ? min(prefs.rowCountOverride, 8)
                : viewModel.autoRowCount(for: targetScreen)
            let iconSize = computeIconSize(contentSize: geo.size, columns: cols, rows: rows)

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
                        Button("关闭启动台") { onDismiss() }
                    }

                // 内容层：搜索栏置顶，网格占满剩余空间，分页指示器在底部
                VStack(spacing: 0) {
                    SearchBarView(text: $viewModel.searchText).padding(.top, prefs.topPadding)
                    contentArea(iconSize: iconSize, cols: cols, rows: rows)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                // 拖拽浮动图标：跟随鼠标自由移动，不参与命中检测
                floatingDragIcon(iconSize: iconSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(appeared ? 1.0 : 0.92)
            .opacity(appeared ? 1.0 : 0)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: appeared)
            // 行列数变化时立即按新的 itemsPerPage 重新分页，否则只改每页 chunk 数不会移动应用到新页。
            .onChange(of: cols) { _, newCols in
                viewModel.reflowLayout(to: newCols * rows)
            }
            .onChange(of: rows) { _, newRows in
                viewModel.reflowLayout(to: cols * newRows)
            }
            // task 在 onAppear 之后、首帧渲染完成后触发，比 asyncAfter(0.01) 更可靠
            .task {
                appeared = false
                try? await Task.sleep(nanoseconds: 8_000_000)  // 8ms，一帧后启动弹入动画
                appeared = true
            }
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
                    withAnimation(.spring(duration: 0.38, bounce: 0.18)) {
                        if goNext { viewModel.goToNextPage() }
                        else      { viewModel.goToPreviousPage() }
                    }
                }
            }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func contentArea(iconSize: CGFloat, cols: Int, rows: Int) -> some View {
        if viewModel.allApps.isEmpty {
            ProgressView().progressViewStyle(.circular).scaleEffect(1.5).tint(.white)
        } else if viewModel.isSearching {
            searchResultsView(iconSize: iconSize, cols: cols, rows: rows)
        } else {
            pagingView(iconSize: iconSize, cols: cols, rows: rows).clipped()
        }
    }

    private var pageIndicatorArea: some View {
        Group {
            if !viewModel.isSearching && viewModel.totalPages > 1 {
                PageIndicatorView(
                    totalPages: viewModel.totalPages,
                    currentPage: viewModel.currentPageIndex,
                    onTap: { viewModel.goToPage($0) }
                )
            } else {
                Color.clear
            }
        }
        .frame(height: CGFloat(prefs.bottomPadding))
    }

    private func searchResultsView(iconSize: CGFloat, cols: Int, rows: Int) -> some View {
        let items = viewModel.searchResults.map { LayoutItem.app(bundleID: $0.bundleID) }
        return Group {
            if items.isEmpty {
                Text("未找到应用").font(.system(size: 18)).foregroundStyle(.white.opacity(0.6))
            } else {
                GridPageView(
                    items: items, apps: viewModel.allApps, folders: [:],
                    columns: cols, rows: rows,
                    hSpacing: CGFloat(prefs.horizontalSpacing), vSpacing: CGFloat(prefs.verticalSpacing),
                    iconSize: iconSize,
                    pageIndex: 0, selectedSlotIndex: viewModel.selectedSearchIndex, isEditMode: false, dragState: DragState(),
                    onTapApp: { viewModel.launch($0) }, onTapFolder: { _ in },
                    onLongPress: {}, onDeleteApp: nil,
                    onBeginDrag: { _, _, _ in }, onUpdateDragTarget: { _, _ in }, onEndDrag: {},
                    onDropOnFolder: nil
                )
            }
        }
    }

    private func pagingView(iconSize: CGFloat, cols: Int, rows: Int) -> some View {
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
            rows: rows,
            hSpacing: CGFloat(prefs.horizontalSpacing), vSpacing: CGFloat(prefs.verticalSpacing),
            iconSize: iconSize,
            pageIndex: pageIdx,
            selectedSlotIndex: viewModel.selectedSlotIndex,
            isEditMode: viewModel.isEditMode,
            dragState: viewModel.dragState,
            onTapApp: { viewModel.launch($0) },
            onTapFolder: { folder in
                guard expandedFolder == nil else { return }
                viewModel.clearSelection()
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
        // 翻页动画：move（水平滑入/出）+ opacity（淡入/出）
        // 淡入淡出消除边缘硬切，spring 弹性让滑动有惯性感
        .transition(.asymmetric(
            insertion: .move(edge: insertEdge).combined(with: .opacity),
            removal:   .move(edge: removeEdge).combined(with: .opacity)
        ))
    }

    // MARK: - 拖拽浮动图标

    /// 跟随鼠标的浮动图标（置于所有内容之上，不拦截事件）
    @ViewBuilder
    private func floatingDragIcon(iconSize: CGFloat) -> some View {
        let ds = viewModel.dragState
        if ds.isDragging,
           let app = viewModel.allApps.first(where: { $0.bundleID == ds.draggedBundleID }) {
            AppIconView(
                app: app,
                iconSize: iconSize,
                isEditMode: false,
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
}
