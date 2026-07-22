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

    /// 外观参数为 0 时的自动推算值，按目标屏幕尺寸比例给出，保证不同分辨率下都协调。
    /// 与 columns/rows/iconSize 的"0 = 自动"约定一致。
    private func autoHorizontalSpacing() -> CGFloat { max(12, targetScreen.frame.width * 0.018) }
    private func autoVerticalSpacing()   -> CGFloat { max(16, targetScreen.frame.height * 0.022) }
    private func autoSidePadding()       -> CGFloat { max(40, targetScreen.frame.width * 0.06) }
    private func autoTopPadding()        -> CGFloat { max(56, targetScreen.frame.height * 0.07) }
    private func autoBottomPadding()     -> CGFloat { max(46, targetScreen.frame.height * 0.06) }

    /// 取"有效"间距/边距：用户设为 0 时走自动推算，否则用用户指定值。
    private func effectiveHorizontalSpacing() -> CGFloat { prefs.horizontalSpacing == 0 ? autoHorizontalSpacing() : CGFloat(prefs.horizontalSpacing) }
    private func effectiveVerticalSpacing()   -> CGFloat { prefs.verticalSpacing == 0 ? autoVerticalSpacing() : CGFloat(prefs.verticalSpacing) }
    private func effectiveSidePadding()       -> CGFloat { prefs.sidePadding == 0 ? autoSidePadding() : CGFloat(prefs.sidePadding) }
    private func effectiveTopPadding()        -> CGFloat { prefs.topPadding == 0 ? autoTopPadding() : CGFloat(prefs.topPadding) }
    private func effectiveBottomPadding()     -> CGFloat { prefs.bottomPadding == 0 ? autoBottomPadding() : CGFloat(prefs.bottomPadding) }

    /// 根据可用内容尺寸计算图标尺寸，让网格在水平/垂直方向都尽量撑满。
    /// 图标最大尺寸可由用户通过「图标最大尺寸」限制；设为 0 时自动撑满。
    private func computeIconSize(contentSize: CGSize, columns: Int, rows: Int) -> CGFloat {
        let cols = CGFloat(columns)
        let rows = CGFloat(rows)
        let hSpacing = effectiveHorizontalSpacing()
        let vSpacing = effectiveVerticalSpacing()
        let sidePad = effectiveSidePadding()
        let topPad = effectiveTopPadding()
        let bottomPad = effectiveBottomPadding()
        // 自动模式下图标尺寸上限：原生 Launchpad 图标约 60~90pt，
        // 避免大屏/少列数时把图标撑到 130pt+ 显得过大。手动「图标最大尺寸」仍可超过此值。
        let autoMaxIcon: CGFloat = 96
        let maxIcon = CGFloat(prefs.iconSizeOverride > 0 ? prefs.iconSizeOverride : autoMaxIcon)

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
                    SearchBarView(text: $viewModel.searchText).padding(.top, effectiveTopPadding())
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
                        viewModel: viewModel,
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
                        },
                        onAppDragEnded: { app, droppedOutside, loc in
                            if droppedOutside {
                                viewModel.moveAppOutOfFolder(
                                    bundleID: app.bundleID,
                                    dropLocation: loc,
                                    pageIndex: viewModel.currentPageIndex
                                )
                            }
                            // 文件夹内重排已在该手势 onEnded 中 commit；
                            // 拖出或重排后统一刷新/关闭展开视图并重置拖拽状态。
                            // 拖出后文件夹可能已解散或变化，同步最新状态
                            if viewModel.layout.folders[folder.id] == nil {
                                withAnimation { expandedFolder = nil }
                            } else {
                                expandedFolder = viewModel.layout.folders[folder.id]
                            }
                            viewModel.dragState = DragState()
                        }
                    )
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }

                // 拖拽浮动图标：跟随鼠标自由移动，不参与命中检测
                // （启动台网格与文件夹内拖拽共用同一套 DragState，统一在此渲染）
                floatingDragIcon(iconSize: iconSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(appeared ? 1.0 : 0.92)
            .opacity(appeared ? 1.0 : 0)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: appeared)
            // 把网格拖拽手势放到最稳定的根视图层级。这样无论 GridPageView 内部如何重建/翻页，
            // 手势识别器都存活，彻底解决「拖到第二页就卡死」。
            .simultaneousGesture(globalDragGesture)
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

    /// 全局网格拖拽手势：宿主在 LaunchpadView 根视图，比 GridPageView 更稳定，
    /// 翻页时不会随内部网格重建而中断。
    private var globalDragGesture: some Gesture {
        var hasCheckedStart = false
        var startBundleID: String? = nil

        return DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                guard !viewModel.isSearching, expandedFolder == nil else { return }

                if !hasCheckedStart {
                    hasCheckedStart = true
                    // 仅当起点真正落在某个槽位的 frame 内（即压在 app 图标上）才启动拖拽；
                    // 落在 cell 间隙 / 空白 / 文件夹上都不启动，让翻页手势或点击正常处理。
                    if let slot = viewModel.slotAt(value.startLocation),
                       let item = viewModel.itemAt(pageIndex: viewModel.currentPageIndex, slot: slot),
                       case .app(let bundleID) = item {
                        startBundleID = bundleID
                        if !viewModel.isEditMode { viewModel.enterEditMode() }
                        viewModel.beginDrag(bundleID: bundleID, pageIndex: viewModel.currentPageIndex, location: value.startLocation)
                    }
                }

                // 起点不是 app（空白/文件夹）：不启动图标拖拽，让 pagingDragGesture 处理翻页。
                guard startBundleID != nil else { return }

                if let nearest = viewModel.nearestSlot(to: value.location, itemsCount: 0) {
                    viewModel.updateDragTarget(slotIndex: nearest, location: value.location)
                }
            }
            .onEnded { _ in
                guard startBundleID != nil, viewModel.dragState.isDragging else { return }
                if let targetSlot = viewModel.nearestSlot(to: viewModel.dragState.dragLocation, itemsCount: 0),
                   case .folder(let fid) = viewModel.itemAt(pageIndex: viewModel.currentPageIndex, slot: targetSlot) {
                    viewModel.addAppToFolder(bundleID: viewModel.dragState.draggedBundleID, folderID: fid, pageIndex: viewModel.currentPageIndex)
                } else {
                    viewModel.endDrag()
                }
                viewModel.dragState = DragState()   // 兜底重置拖拽态，避免文件夹分支漏清导致浮层残留
                startBundleID = nil
                hasCheckedStart = false
            }
    }

    private var pagingDragGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .global)
            .onChanged { value in
                // 起点压在某个槽位上（app / 文件夹）：交给 globalDragGesture 或点击，
                // 这里让行，不翻页。落在 cell 间隙 / 网格外则正常翻页。
                guard !viewModel.isSearching, !viewModel.isEditMode, expandedFolder == nil,
                      !viewModel.dragState.isDragging,
                      viewModel.slotAt(value.startLocation) == nil else {
                    dragOffsetX = 0
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffsetX = value.translation.width
                isDragging = true
            }
            .onEnded { value in
                guard !viewModel.isSearching, !viewModel.isEditMode, expandedFolder == nil,
                      !viewModel.dragState.isDragging,
                      viewModel.slotAt(value.startLocation) == nil else {
                    dragOffsetX = 0
                    return
                }
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
        .frame(height: effectiveBottomPadding())
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
                    hSpacing: effectiveHorizontalSpacing(), vSpacing: effectiveVerticalSpacing(),
                    iconSize: iconSize,
                    pageIndex: 0, selectedSlotIndex: viewModel.selectedSearchIndex, isEditMode: false, dragState: DragState(),
                    viewModel: viewModel,
                    onTapApp: { viewModel.launch($0) }, onTapFolder: { _ in },
                    onLongPress: {},
                    onBeginDrag: { _, _ in }, onUpdateDragTarget: { _, _ in }, onEndDrag: {},
                    onDropOnFolder: nil
                )
            }
        }
    }

    private func pagingView(iconSize: CGFloat, cols: Int, rows: Int) -> some View {
        let pageIdx = viewModel.currentPageIndex
        // 拖拽中通过 pageItemsWithDrag 实时把被拖图标插入目标槽位，
        // 邻近图标以弹簧动画让位（实时让位效果）。命中测试读固定 dragSlotFrames，
        // 因此目标 app 不会因让位而"逃跑"，文件夹创建依旧可行。松手后 endDrag 才真正改 layout。
        let pageItems = viewModel.pageItemsWithDrag(pageIndex: pageIdx)

        return GridPageView(
            items: pageItems,
            apps: viewModel.allApps,
            folders: viewModel.layout.folders,
            columns: cols,
            rows: rows,
            hSpacing: effectiveHorizontalSpacing(), vSpacing: effectiveVerticalSpacing(),
            iconSize: iconSize,
            pageIndex: pageIdx,
            selectedSlotIndex: viewModel.selectedSlotIndex,
            isEditMode: viewModel.isEditMode,
            dragState: viewModel.dragState,
            viewModel: viewModel,
            onTapApp: { viewModel.launch($0) },
            onTapFolder: { folder in
                guard expandedFolder == nil else { return }
                viewModel.clearSelection()
                withAnimation(.spring(duration: 0.25, bounce: 0.1)) { expandedFolder = folder }
            },
            onLongPress: { viewModel.enterEditMode() },
            onBeginDrag: { id, loc in viewModel.beginDrag(bundleID: id, pageIndex: pageIdx, location: loc) },
            onUpdateDragTarget: { slot, loc in viewModel.updateDragTarget(slotIndex: slot, location: loc) },
            onEndDrag: { viewModel.endDrag() },
            onDropOnFolder: { bundleID, folderID in
                viewModel.addAppToFolder(bundleID: bundleID, folderID: folderID, pageIndex: pageIdx)
            }
        )
        .offset(x: dragOffsetX)
        // 注意：这里刻意不加 `.id(currentPageIndex)`。
        // 原先靠 .id + transition 实现翻页滑动动画，但翻页会改变视图身份，
        // 把正在拖拽的图标（及其手势）整个销毁重建，导致「拖到第二页就卡死」。
        // 现在翻页改为原地切换内容（同实例），并把拖拽手势宿主上移到 GridPageView 层级，
        // 这样翻页时手势不随被拖 app 的视图重建而中断。
        // 代价是翻页动画变为即时切换（功能优先于滑动特效）。
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
