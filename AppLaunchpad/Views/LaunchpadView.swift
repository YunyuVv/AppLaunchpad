import SwiftUI
import AppKit

/// 启动台全屏根视图
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var dragOffsetX: CGFloat = 0
    @State private var isDragging = false
    @State private var expandedFolderID: UUID? = nil
    /// 翻页过渡动画：方向性滑入 + 淡入（无需双页渲染）
    @State private var pageTransitionOffset: CGFloat = 0
    @State private var pageTransitionOpacity: Double = 1.0
    /// 拖拽翻页松手时的连续滑入起点；非 nil 表示本次翻页由拖拽触发
    /// （相邻页在拖拽中已可见，故新页无需淡入，直接从相邻页位置滑入）。
    @State private var pendingFlipStart: CGFloat? = nil
    /// 拖拽起手状态：用 @GestureState 而非手势闭包内的局部变量。
    /// 原因：globalDragGesture 是计算属性，拖拽中 @Observable 频繁触发 body 重算会让手势
    /// 被反复重建，闭包局部变量随之被重置 → 松手时 onEnded 跑在"新实例"上、startBundleID 为 nil
    /// → guard 失败、endDrag 不执行 → app 不落位 + isDragging 卡死（"松手后无法点击"）。
    /// @GestureState 是视图级状态，跨手势重建保留，且专为拖拽设计、写它不会中断手势。
    @GestureState private var dragStart: (checked: Bool, bundleID: String?, folderID: UUID?) = (false, nil, nil)
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

                // 关闭/退出编辑，右键弹出上下文菜单
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.isEditMode {
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

                // 拖拽浮动图标：跟随鼠标自由移动，不参与命中检测
                floatingDragIcon(iconSize: iconSize)

                // 文件夹展开视图 overlay
                if let folderID = expandedFolderID,
                   let folder = viewModel.folderInfo(for: folderID) {
                    FolderExpandedView(
                        folder: folder,
                        apps: viewModel.allApps,
                        iconSize: iconSize,
                        onDismiss: { expandedFolderID = nil },
                        onLaunch: { viewModel.launch($0) },
                        onDragOutHandoff: { app, location in
                            // 从文件夹移除并插回主网格（文件夹所在页），接管主网格拖拽
                            let page = viewModel.folderController.removeAppAndReinsert(app.bundleID, fromFolder: folderID)
                            viewModel.saveLayout()
                            if !viewModel.isEditMode { viewModel.enterEditMode() }
                            viewModel.beginDrag(bundleID: app.bundleID, pageIndex: page, location: location)
                        },
                        onDragOutMove: { location in
                            viewModel.updateDragTarget(location: location)
                        },
                        onDragOutEnd: {
                            viewModel.endDrag()
                            expandedFolderID = nil
                        },
                        onReorder: { newIDs in
                            var f = folder
                            f.appIDs = newIDs
                            viewModel.data.layout.folders[folderID] = f
                            viewModel.saveLayout()
                        }
                    )
                    .zIndex(1000)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(appeared ? 1.0 : 0.92)
            .opacity(appeared ? 1.0 : 0)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: appeared)
            // 松手时统一用 spring 驱动整个视图树（iconCell 让位回位 + floatingDragIcon transition 移除），
            // 让浮动图标朝目标 cell 弹性滑过去再渐隐（与原生 Launchpad 视觉一致），
            // 避免 transition 渐隐过程中残影停在光标位置造成「停在附近、没落正中心」的错觉。
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.82), value: viewModel.dragState.isDragging)
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
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .updating($dragStart) { value, state, _ in
                guard !viewModel.isSearching else { return }

                if !state.checked {
                    state.checked = true
                    // 起点压在 app 图标上 → 启动 app 拖拽
                    if let bundleID = viewModel.appAtIconPoint(value.startLocation) {
                        state.bundleID = bundleID
                        if !viewModel.isEditMode { viewModel.enterEditMode() }
                        viewModel.beginDrag(bundleID: bundleID, pageIndex: viewModel.currentPageIndex, location: value.startLocation)
                    }
                    // 起点压在文件夹图标上 → 启动文件夹拖拽（仅重排，不合并/嵌套）
                    else if let folderID = viewModel.folderAtIconPoint(value.startLocation) {
                        state.folderID = folderID
                        if !viewModel.isEditMode { viewModel.enterEditMode() }
                        viewModel.beginDrag(folderID: folderID, pageIndex: viewModel.currentPageIndex, location: value.startLocation)
                    }
                }

                // 起点不是有效项（空白/间隙）：不启动图标拖拽，让 pagingDragGesture 处理翻页。
                guard state.bundleID != nil || state.folderID != nil else { return }

                // 落点纯几何推导：由光标坐标 + 固定网格几何算出 cursorSlot，
                // 不再用 measured frame / 快照 / 最近中心点，避免让位动画导致落点漂移。
                viewModel.updateDragTarget(location: value.location)
            }
            .onEnded { value in
                // 松手落主体责任：dragState.isDragging 为 true 即说明拖拽已启动
                //（draggedBundleID 为 String 非 optional，判 nil 永真、无意义）。
                guard viewModel.dragState.isDragging else { return }
                // 用松手瞬间的精确坐标再算一次落点，消除「最后一步 onChanged 与松手位置
                // 存在一格偏差」导致的偏移（落不到正位 / 有点偏离）。
                viewModel.updateDragTarget(location: value.location)
                // 落地：easeOut 渐隐浮动图标 + GridPageView spring 重排入位，纯融合无轨迹
                withAnimation(.easeOut(duration: 0.28)) {
                    viewModel.endDrag()
                }
            }
    }

    private var pagingDragGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .global)
            .onChanged { value in
                // 起点压在任何图标（app 或文件夹）：交给 globalDragGesture 或点击，这里让行，不翻页。
                // 落在 cell 间隙 / 网格外则正常翻页。
                guard !viewModel.isSearching, !viewModel.isEditMode,
                      !viewModel.dragState.isDragging,
                      !viewModel.anyItemAtIconPoint(value.startLocation) else {
                    dragOffsetX = 0
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffsetX = value.translation.width
                isDragging = true
            }
            .onEnded { value in
                guard !viewModel.isSearching, !viewModel.isEditMode,
                      !viewModel.dragState.isDragging,
                      !viewModel.anyItemAtIconPoint(value.startLocation) else {
                    dragOffsetX = 0
                    return
                }
                isDragging = false
                let threshold: CGFloat = 50
                let startX = value.translation.width
                let goingNext = startX < -threshold
                let goingPrev = startX > threshold
                let current = viewModel.currentPageIndex
                let total = viewModel.totalPages
                let target = goingNext ? min(current + 1, total - 1)
                            : goingPrev ? max(current - 1, 0)
                            : current
                if target == current {
                    // 未越过阈值：当前页从拖拽位置弹簧回到正中（无翻页）。
                    pageTransitionOffset = startX
                    pageTransitionOpacity = 1.0
                    withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                        pageTransitionOffset = 0
                    }
                } else {
                    // 越过阈值：新页从"相邻页当时的位置"连续滑入。
                    // 关键：必须在 goToPage 之前同步设好过渡起点（pageTransitionOffset/opacity），
                    // 否则 body 会在 onChange 异步回调前先用旧偏移(0)渲染新当前页一帧 → 闪现正中（闪烁）。
                    // 同步设到 start 后，body 第一帧新页位置 = 拖拽中相邻页位置（dragOffsetX±W），完全衔接。
                    let W = viewModel.gridGeometry?.size.width ?? 0
                    let start = goingNext ? (startX + W) : (startX - W)
                    pendingFlipStart = start
                    pageTransitionOffset = start
                    pageTransitionOpacity = 1.0
                    viewModel.goToPage(target)
                }
                dragOffsetX = 0
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
                    items: items, apps: viewModel.allApps,
                    columns: cols, rows: rows,
                    hSpacing: effectiveHorizontalSpacing(), vSpacing: effectiveVerticalSpacing(),
                    iconSize: iconSize,
                    pageIndex: 0, selectedSlotIndex: viewModel.selectedSearchIndex, isEditMode: false, dragState: DragState(),
                    viewModel: viewModel,
                    onTapApp: { viewModel.launch($0) },
                    onLongPress: {},
                    onBeginDrag: { _, _ in }, onUpdateDragTarget: { _, _ in }, onEndDrag: {},
                    onTapFolder: { _ in }
                )
            }
        }
    }

    private func pagingView(iconSize: CGFloat, cols: Int, rows: Int) -> some View {
        let pageIdx = viewModel.currentPageIndex
        // 拖拽中通过 pageItemsWithDrag 实时把被拖图标移到几何落点（cursorSlot），
        // 邻近图标以弹簧动画让位（实时让位效果）。落点由 GridGeometry 纯几何推导，
        // 不依赖 measured frame / 快照，因此目标不会因让位而"逃跑"或漂移。
        // 松手后 endDrag 用同一 move 语义落点，零跳变。
        let pageItems = viewModel.pageItemsWithDrag(pageIndex: pageIdx)
        let hSpacing = effectiveHorizontalSpacing()
        let vSpacing = effectiveVerticalSpacing()

        return GeometryReader { geo in
            let gRect = geo.frame(in: .global)
            let cellW = (gRect.width - hSpacing * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (gRect.height - vSpacing * CGFloat(rows - 1)) / CGFloat(rows)
            // 写入网格几何（@ObservationIgnored，变更不触发重渲染）。
            // 拖拽期间网格容器不移动，该几何稳定，落点完全确定。
            // 注意：@ViewBuilder 内不能写裸赋值语句，用闭包调用 + let _ = 触发副作用。
            let _ = {
                viewModel.gridGeometry = GridGeometry(
                    origin: gRect.origin,
                    size: gRect.size,
                    columns: cols,
                    rows: rows,
                    cellW: cellW,
                    cellH: cellH,
                    hSpacing: hSpacing,
                    vSpacing: vSpacing,
                    iconSize: iconSize
                )
            }()
            let currentPage = GridPageView(
                items: pageItems,
                apps: viewModel.allApps,
                columns: cols,
                rows: rows,
                hSpacing: hSpacing, vSpacing: vSpacing,
                iconSize: iconSize,
                pageIndex: pageIdx,
                selectedSlotIndex: viewModel.selectedSlotIndex,
                isEditMode: viewModel.isEditMode,
                dragState: viewModel.dragState,
                viewModel: viewModel,
                onTapApp: { viewModel.launch($0) },
                onLongPress: { viewModel.enterEditMode() },
                onBeginDrag: { id, loc in viewModel.beginDrag(bundleID: id, pageIndex: pageIdx, location: loc) },
                onUpdateDragTarget: { _, loc in viewModel.updateDragTarget(location: loc) },
                onEndDrag: { viewModel.endDrag() },
                onTapFolder: { expandedFolderID = $0 }
            )
            if isDragging, dragOffsetX != 0 {
                // 空白拖拽翻页进行中：当前页 + 相邻页并排，随拖拽平移，无空窗。
                // 相邻页为纯展示（空回调 + 空 dragState），不触发 make-way，不影响落点。
                let W = gRect.width
                let total = viewModel.totalPages
                let hasNext = pageIdx < total - 1
                let hasPrev = pageIdx > 0
                ZStack(alignment: .topLeading) {
                    currentPage.offset(x: dragOffsetX)
                    if hasNext, dragOffsetX < 0 {
                        GridPageView(
                            items: viewModel.pageItemsWithDrag(pageIndex: pageIdx + 1),
                            apps: viewModel.allApps,
                            columns: cols, rows: rows,
                            hSpacing: hSpacing, vSpacing: vSpacing,
                            iconSize: iconSize,
                            pageIndex: pageIdx + 1,
                            selectedSlotIndex: viewModel.selectedSlotIndex,
                            isEditMode: false, dragState: DragState(),
                            viewModel: viewModel,
                            onTapApp: { _ in }, onLongPress: {},
                            onBeginDrag: { _, _ in }, onUpdateDragTarget: { _, _ in }, onEndDrag: {},
                            onTapFolder: { _ in }
                        )
                        .offset(x: dragOffsetX + W)
                    }
                    if hasPrev, dragOffsetX > 0 {
                        GridPageView(
                            items: viewModel.pageItemsWithDrag(pageIndex: pageIdx - 1),
                            apps: viewModel.allApps,
                            columns: cols, rows: rows,
                            hSpacing: hSpacing, vSpacing: vSpacing,
                            iconSize: iconSize,
                            pageIndex: pageIdx - 1,
                            selectedSlotIndex: viewModel.selectedSlotIndex,
                            isEditMode: false, dragState: DragState(),
                            viewModel: viewModel,
                            onTapApp: { _ in }, onLongPress: {},
                            onBeginDrag: { _, _ in }, onUpdateDragTarget: { _, _ in }, onEndDrag: {},
                            onTapFolder: { _ in }
                        )
                        .offset(x: dragOffsetX - W)
                    }
                }
            } else {
                currentPage
                    .offset(x: pageTransitionOffset)
                    .opacity(pageTransitionOpacity)
            }
        }
        .clipped()
        .onChange(of: viewModel.currentPageIndex) { oldValue, newValue in
            guard oldValue != newValue else { return }
            // 统一翻页观感：所有路径都用「整页宽方向性滑动、无淡入」，与鼠标拖拽同语言。
            // - 拖拽触发：新页从相邻页当时位置连续滑入（pendingFlipStart = dragOffsetX ± 页宽）；
            // - 外部翻页（指示器/键盘/触控板/滚轮）：新页从「整页宽」位置滑入（start = ±W）。
            // 整页起步即在屏幕外，无需淡入遮硬边，故 opacity 始终保 1.0。
            let W = viewModel.gridGeometry?.size.width ?? 0
            let start = pendingFlipStart ?? (viewModel.pageFlipGoingForward ? W : -W)
            pendingFlipStart = nil
            pageTransitionOffset = start
            pageTransitionOpacity = 1.0
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                pageTransitionOffset = 0
                pageTransitionOpacity = 1.0
            }
        }
        // 注意：这里刻意不加 `.id(currentPageIndex)`。
        // 原先靠 .id + transition 实现翻页滑动动画，但翻页会改变视图身份，
        // 把正在拖拽的图标（及其手势）整个销毁重建，导致「拖到第二页就卡死」。
        // 现在翻页改为单页渲染 + 拖拽中渲染相邻页 + onChange 方向性滑入，手势不受影响。
    }

    // MARK: - 拖拽浮动图标

    /// 跟随鼠标的浮动图标（置于所有内容之上，不拦截事件）
    @ViewBuilder
    private func floatingDragIcon(iconSize: CGFloat) -> some View {
        let ds = viewModel.dragState
        if ds.isDragging {
            // 文件夹拖拽：显示 FolderThumbnailView 作为浮动图标
            if ds.draggedItemType == .folder,
               let folderID = ds.draggedFolderID,
               let folder = viewModel.folderInfo(for: folderID) {
                FolderThumbnailView(
                    folder: folder,
                    apps: viewModel.allApps,
                    iconSize: iconSize,
                    isEditMode: false,
                    isSelected: false,
                    onTap: {}, onLongPress: {}, onDelete: nil,
                    showName: false,
                    showDeleteButton: false
                )
                .scaleEffect(1.12)
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                .allowsHitTesting(false)
                .position(ds.dragLocation)
                .zIndex(999)
                .transition(.opacity)
            }
            // App 拖拽：显示 AppIconView 作为浮动图标
            else if let app = viewModel.allApps.first(where: { $0.bundleID == ds.draggedBundleID }) {
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
}
