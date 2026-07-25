import SwiftUI
import AppKit

/// 文件夹展开视图：占屏幕 70% overlay，支持弹簧让位拖拽排序 + 拖出回到主网格。
/// 内部拖拽走自管 make-way（与主网格逻辑一致），但不支持在展开视图内创建子文件夹。
struct FolderExpandedView: View {
    let folder: FolderInfo
    let apps: [AppInfo]
    let iconSize: CGFloat
    let onDismiss: () -> Void
    let onLaunch: (AppInfo) -> Void
    /// 拖出面板交接给主网格：第一次超出面板范围触发。
    /// 父级应：从文件夹移除该 app 并插回主网格、启动主网格拖拽（接管光标，不等待松手）。
    var onDragOutHandoff: ((AppInfo, CGPoint) -> Void)?
    /// 交接后持续移动：把光标位置交给主网格驱动 make-way / 浮动图标。
    var onDragOutMove: ((CGPoint) -> Void)?
    /// 松手：主网格 endDrag 并关闭面板。
    var onDragOutEnd: (() -> Void)?
    var onReorder: (([String]) -> Void)?
    /// 重命名回调：用户在展开面板里改完文件夹名后触发，父级负责调用 FolderController.renameFolder + saveLayout。
    var onRename: ((String) -> Void)? = nil

    // MARK: - 引用类型容器（解决 SwiftUI 手势闭包对值类型 @State 的快照捕获陷阱）

    /// 面板 frame 容器：用 class 而非 CGRect，确保手势闭包始终读到最新值。
    /// @State var panelFrame: CGRect 是值类型，手势在创建时捕获其快照 → 后续 PreferenceKey
    /// 更新后手势闭包里仍是 .zero → 拖出检测永不触发。
    private final class FrameBox { var frame: CGRect = .zero }
    @State private var panelFrameBox = FrameBox()

    // MARK: - 内部拖拽状态

    @State private var orderedIDs: [String]
    /// 被拖 app 在 orderedIDs 中的源索引（nil=未拖拽）
    @State private var dragSourceIndex: Int?
    /// 光标所在的槽位索引（用于 make-way 插入位置）
    @State private var dragCursorIndex: Int = 0
    /// 当前拖拽光标全局位置
    @State private var dragLocation: CGPoint = .zero
    /// 几何存储（引用类型）：仅测量首格全局 frame，供拖拽落点纯几何推导。
    /// 用 class 避免 @State 值变更触发重渲染死循环；面板在拖拽期间不移动，几何稳定。
    @State private var geoStore = FolderGeoStore()
    /// 正在拖出面板范围（→ 面板立即透明）
    @State private var isDraggingOut = false
    /// 背景样式偏好（读 backgroundStyle 以在磨砂/液态玻璃间切换面板背景）
    @State private var prefs = UserPreferences.shared
    /// 重命名状态：是否处于编辑中
    @State private var isRenaming = false
    /// 当前展示的文件夹名（rename 后避免依赖父级重新传值，本地即更新）
    @State private var displayName: String
    /// 编辑中的草稿名
    @State private var draftName: String = ""
    @FocusState private var renameFocused: Bool

    init(folder: FolderInfo, apps: [AppInfo], iconSize: CGFloat,
         onDismiss: @escaping () -> Void, onLaunch: @escaping (AppInfo) -> Void,
         onDragOutHandoff: ((AppInfo, CGPoint) -> Void)? = nil,
         onDragOutMove: ((CGPoint) -> Void)? = nil,
         onDragOutEnd: (() -> Void)? = nil,
         onReorder: (([String]) -> Void)? = nil,
         onRename: ((String) -> Void)? = nil) {
        self.folder = folder
        self.apps = apps
        self.iconSize = iconSize
        self.onDismiss = onDismiss
        self.onLaunch = onLaunch
        self.onDragOutHandoff = onDragOutHandoff
        self.onDragOutMove = onDragOutMove
        self.onDragOutEnd = onDragOutEnd
        self.onReorder = onReorder
        self.onRename = onRename
        self._orderedIDs = State(initialValue: folder.appIDs)
        self._displayName = State(initialValue: folder.name)
    }

    // MARK: - 让位视觉排列

    /// 当前视觉排列（拖拽中应用 make-way：移除源 → 插入到 cursorIndex）
    private var visualIDs: [String] {
        guard let src = dragSourceIndex, src < orderedIDs.count else { return orderedIDs }
        var ids = orderedIDs
        let item = ids.remove(at: src)
        let to = min(max(dragCursorIndex, 0), ids.count)
        ids.insert(item, at: to)
        return ids
    }

    var body: some View {
        let visualApps = visualIDs.compactMap { id in apps.first { $0.bundleID == id } }
        // 在 body 阶段 geometry 已知前先按 cell 宽 + 间距估一版（仅用于首帧占位，几何就绪后 appGrid 内部按真实 panelW 重算）
        // columns 改为在 appGrid 内部基于 panelW 实时计算
        let draggedApp = dragSourceIndex.flatMap { src in
            src < orderedIDs.count ? apps.first { $0.bundleID == orderedIDs[src] } : nil
        }

        ZStack {
            // 背景虚化层（方案 C：跟随全局背景样式自适应）：
            // 磨砂模式 → .withinWindow 毛玻璃（模糊窗口内主网格）；
            // 玻璃模式 → NSGlassEffectView 液态玻璃（折射其下网格，与全屏背景一致）。
            // 点击空白处关闭手势挂在最底层 backdrop 上，dim 层放行命中。
            FolderBackdropView(isGlass: prefs.backgroundStyle == 1)
                .ignoresSafeArea()
                .onTapGesture {
                    // 编辑态点背景：先保存/退出编辑，再关闭面板
                    if isRenaming { commitRename() }
                    onDismiss()
                }
            // 轻压暗层：虚化本身已降噪，压暗度低于原 0.45；
            // 玻璃模式更轻（0.2）以保留折射感，磨砂模式 0.3 补偿二次模糊偏柔。
            Color.black.opacity(prefs.backgroundStyle == 1 ? 0.2 : 0.3)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            GeometryReader { geo in
                // 面板取屏宽 55%（之前 70% 偏胖）：narrower → 同屏宽下每行自然容纳列数变少，
                // 完全由面板宽/格宽/间距动态决定，没有人为列数上限。
                let panelW = geo.size.width * 0.55
                let panelH = geo.size.height * 0.8
                // 面板顶部预留：避开屏幕顶部的搜索框（其底部约在 autoTopPadding + 搜索栏高(~38) 处），
                // 并额外留 18pt 间距，避免面板贴住/压住搜索框。与 LaunchpadView.autoTopPadding 同公式。
                let topInset = max(56, geo.size.height * 0.07) + 56

                // 面板内容（与几何/手势无关，仅作渲染层，两种背景样式共用）
                let folderContent = VStack(spacing: 0) {
                    titleView(panelW: panelW)
                        .padding(.top, 28)
                        .padding(.bottom, 20)

                    appGrid(panelW: panelW, panelH: panelH, visualApps: visualApps)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                        // 编辑态点面板内容区（app 网格空白/图标）→ 退出编辑：名字变则保存，不变等同取消。
                        // 点标题输入框内部不会冒泡到此（兄弟视图），不影响光标定位。
                        .onTapGesture { if isRenaming { commitRename() } }
                }

                // 背景样式：液态玻璃 → 内容包进 NSGlassEffectView.contentView；
                // 磨砂玻璃（默认）→ 沿用 .ultraThinMaterial + 白色描边。
                // 两种模式共用同一几何（frame/position），仅外层渲染容器不同，
                // 拖拽/落点几何逻辑不受影响。
                Group {
                    if prefs.backgroundStyle == 1 {
                        GlassHostingView(cornerRadius: 16) {
                            folderContent
                        }
                    } else {
                        folderContent
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                }
                .frame(width: panelW, height: panelH)
                .position(x: geo.size.width / 2, y: topInset + panelH / 2)
                // 面板 frame = 外层 GeometryReader 填满全屏 → 计算 70% 居中区域的全局坐标。
                // 用 onAppear 写入引用类型 FrameBox，手势闭包通过指针始终读到最新值
                // （避免值类型 @State 被手势创建时快照捕获 → 永远是 .zero 的经典陷阱）。
                .onAppear {
                    let globalOrigin = geo.frame(in: .global).origin
                    panelFrameBox.frame = CGRect(
                        x: globalOrigin.x + (geo.size.width - panelW) / 2,
                        y: globalOrigin.y + topInset,
                        width: panelW, height: panelH
                    )
                }

                // 浮动图标
                if let app = draggedApp {
                    AppIconView(app: app, iconSize: iconSize, isEditMode: false,
                                onTap: {}, onLongPress: {})
                        .scaleEffect(1.12)
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                        .allowsHitTesting(false)
                        .position(dragLocation)
                }
            }
        }
        // 拖出后整体透明（视觉上关闭面板），但保留在视图层级中以保证拖拽手势不断开，
        // 从而能继续接管主网格拖拽。注意：绝不能用 allowsHitTesting(false)，否则手势宿主
        // 失去命中 → 手势立即结束，无法实现「不松手交接」。
        .opacity(isDraggingOut ? 0 : 1)
        .transition(.opacity)
    }

    // MARK: - 标题（可点按重命名）

    @ViewBuilder
    private func titleView(panelW: CGFloat) -> some View {
        let maxW: CGFloat = min(panelW * 0.85, 360)
        // 两种状态共用同一固定尺寸容器（maxW × 32），且编辑态不再有「完成/取消」按钮，
        // 因此点标题进编辑、点外部失焦自动保存，宽高始终不变、UI 零跳动。
        ZStack {
            if isRenaming {
                TextField("文件夹名称", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: maxW)
                    .focused($renameFocused)
                    .onSubmit { commitRename() }            // 回车 = 保存
                    .onExitCommand { cancelRename() }        // Esc = 取消
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.12))
                    )
                    .transition(.opacity)
            } else {
                Button {
                    startRename()
                } label: {
                    Text(displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .help("点按可重命名，点外部自动保存")
                .transition(.opacity)
            }
        }
        .frame(width: maxW, height: 32)
        .animation(.easeInOut(duration: 0.15), value: isRenaming)
        // 焦点离开（点击外部 / 切到别处）→ 自动保存，无需任何按钮
        .onChange(of: renameFocused) { _, isFocused in
            if !isFocused { commitRename() }
        }
    }

    private func startRename() {
        draftName = displayName
        isRenaming = true
        // TextField 进入视图树后再聚焦，避免首帧还没挂载就拿不到焦点
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        guard isRenaming else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? displayName : trimmed
        if finalName != displayName {
            displayName = finalName
            onRename?(finalName)
        }
        isRenaming = false
        renameFocused = false
    }

    private func cancelRename() {
        isRenaming = false
        renameFocused = false
    }

    // MARK: - App Grid

    /// 每 cell 视觉宽度 = 图标 + 左右各 8pt 内边距；与 AppIconView.cellWidth 保持一致。
    private var cellVisualWidth: CGFloat { iconSize + 16 }
    /// 列间距 = HStack spacing（保持与原实现一致）。
    private let hSpacing: CGFloat = 24
    /// 行间距 = VStack spacing（保持与原实现一致）。
    private let vSpacing: CGFloat = 24
    /// 内容左右内边距（与 .padding(.horizontal, 28) 对齐）。
    private let sidePad: CGFloat = 28

    /// 仿 LaunchNext：按可用宽度 + 单 cell 宽（含内边距与列间距）反推最大可容纳列数。
    /// 不人为封顶列数（之前 `min(8, ...)` 是硬上限，违背"列数应随面板宽度自决定"的产品诉求）；
    /// 仅保留 `min(cols, count)` 和 `max(1, ...)` 下限，避免出现空行/超量。
    private static func computeColumns(panelW: CGFloat, cellW: CGFloat, hSpacing: CGFloat,
                                        sidePad: CGFloat, count: Int) -> Int {
        guard panelW > 0, cellW > 0, count > 0 else { return 1 }
        let available = max(0, panelW - 2 * sidePad)
        let cols = Int((available + hSpacing) / (cellW + hSpacing))
        return max(1, min(cols, count))
    }

    // MARK: - 几何落点（仿主网格 GridGeometry，替代逐格 frame 命中测试）

    /// 文件夹面板网格几何（全局坐标系），供拖拽落点纯几何推导。
    /// 与主网格 GridGeometry.slotUnderCursor 同算法：均匀格点、间隙中点切列/行，无盲区、零延迟。
    private struct FolderGeometry {
        let origin: CGPoint
        let columns: Int
        let rows: Int
        let cellW: CGFloat
        let cellH: CGFloat
        let hSpacing: CGFloat
        let vSpacing: CGFloat

        func slotUnderCursor(_ p: CGPoint) -> Int {
            let lx = p.x - origin.x
            let ly = p.y - origin.y
            let strideX = cellW + hSpacing
            let strideY = cellH + vSpacing
            guard strideX > 0, strideY > 0, columns > 0, rows > 0 else { return 0 }
            let rawCol = Int((lx + hSpacing / 2) / strideX)
            let rawRow = Int((ly + vSpacing / 2) / strideY)
            let col = min(max(rawCol, 0), columns - 1)
            let row = min(max(rawRow, 0), rows - 1)
            return row * columns + col
        }
    }

    /// 几何存储：仅持有首格全局 frame（由 PreferenceKey 测量一次写入）。
    /// 引用类型 + @State 持有，不重新赋值 → 不触发重渲染；拖拽期间面板不动，几何稳定。
    private final class FolderGeoStore { var firstCell: CGRect = .zero }

    private var currentColumns: Int {
        let pw = panelFrameBox.frame.width
        return Self.computeColumns(panelW: pw, cellW: cellVisualWidth,
                                   hSpacing: hSpacing, sidePad: sidePad, count: orderedIDs.count)
    }
    private var currentRows: Int {
        let c = currentColumns
        return c > 0 ? Int((orderedIDs.count + c - 1) / c) : 1
    }
    /// 由首格测量的全局 frame 推导几何；拖拽期间面板不移动，几何稳定。返回 nil 表示尚未测量好。
    private func folderGeometryNow(columns: Int, rowsCount: Int) -> FolderGeometry? {
        let f = geoStore.firstCell
        guard f != .zero, columns > 0, rowsCount > 0 else { return nil }
        return FolderGeometry(origin: f.origin, columns: columns, rows: rowsCount,
                              cellW: f.width, cellH: f.height,
                              hSpacing: hSpacing, vSpacing: vSpacing)
    }

    private func appGrid(panelW: CGFloat, panelH: CGFloat, visualApps: [AppInfo]) -> some View {
        let columns = Self.computeColumns(panelW: panelW, cellW: cellVisualWidth,
                                          hSpacing: hSpacing, sidePad: sidePad,
                                          count: visualApps.count)
        let rows = visualApps.chunked(into: columns)
        // ScrollView 可用高度 = 面板高 - 标题区(padding.top 28 + 文字 ~18 + padding.bottom 20) - 内容底 padding 28
        // 留作后续按面板标题字号微调；视觉对齐面板内网格上下居中。
        let headerH: CGFloat = 28 + 18 + 20
        let bottomPad: CGFloat = 28
        let availableH = max(0, panelH - headerH - bottomPad)
        return ScrollView {
            VStack(spacing: 24) {
                ForEach(0..<rows.count, id: \.self) { rowIdx in
                    HStack(spacing: hSpacing) {
                        ForEach(rows[rowIdx]) { app in
                            let isDragged = dragSourceIndex != nil
                                && orderedIDs.firstIndex(of: app.bundleID) == dragSourceIndex
                            let isFirst = rowIdx == 0 && rows[rowIdx].first?.bundleID == app.bundleID
                            AppIconView(app: app, iconSize: iconSize, isEditMode: false,
                                        onTap: { onLaunch(app) },
                                        onLongPress: {})
                                .opacity(isDragged ? 0.0 : 1.0)
                                .background(
                                    // 仅首格：测量其全局 frame，供纯几何落点（替代逐格 cellFrames 命中测试）
                                    GeometryReader { cg in
                                        Color.clear.preference(
                                            key: FirstCellFrameKey.self,
                                            value: isFirst ? cg.frame(in: .global) : .zero
                                        )
                                    }
                                )
                                .highPriorityGesture(dragGesture(for: app))
                        }
                    }
                    // 整面板左上对齐：满行从左起铺到右侧（不强制右对齐），不满行也从最左起。
                    // 避免之前 .center 居中导致「第 2 行 1-2 个 icon 出现在中间」的不自然视觉。
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // 顶端左对齐（行数少时不再垂直居中，符合原生 Launchpad 风格）：
            // 满行自然从左起排到右；不满行也从最左起，新加 app 继续在下一行最左出现。
            // 注意：此处不可加 maxHeight 上限——会让内容被截断而非滚动；
            // ScrollView 的视口高度由下方 .frame(height: availableH) 约束，内容超出即纵向滚动。
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // 弹簧让位动画（与主网格 GridPageView 参数一致）
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: visualApps.map(\.bundleID))
        }
        // 限制 ScrollView 高度，否则 VStack 的 maxHeight:.infinity 拿不到视口约束。
        .frame(height: availableH)
        .scrollDisabled(dragSourceIndex != nil)
        .onPreferenceChange(FirstCellFrameKey.self) { rect in
            geoStore.firstCell = rect
        }
    }

    // MARK: - Drag Gesture

    private func dragGesture(for app: AppInfo) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                if dragSourceIndex == nil {
                    dragSourceIndex = orderedIDs.firstIndex(of: app.bundleID)
                }
                dragLocation = value.location

                // 交接给主网格：一旦拖出面板范围，立即关闭面板并接管主网格拖拽，
                // 不等待松手（用户要在主网格继续调整顺序）。
                if !isDraggingOut,
                   panelFrameBox.frame != .zero,
                   !panelFrameBox.frame.contains(value.location) {
                    isDraggingOut = true
                    onDragOutHandoff?(app, value.location)
                    return
                }
                guard !isDraggingOut else {
                    // 交接后：把光标位置持续交给主网格驱动 make-way / 浮动图标
                    onDragOutMove?(value.location)
                    return
                }

                // 内部 make-way：纯几何落点（与主网格一致，间隙里也连续、零延迟、无盲区）
                let cols = currentColumns
                let rws = currentRows
                if let geo = folderGeometryNow(columns: cols, rowsCount: rws) {
                    dragCursorIndex = geo.slotUnderCursor(value.location)
                }
            }
            .onEnded { value in
                defer {
                    dragSourceIndex = nil
                    isDraggingOut = false
                }

                // 已交接给主网格：松手时由主网格完成落位并关闭面板
                if isDraggingOut {
                    onDragOutEnd?()
                    return
                }

                // 内部重排：几何落点决定目标槽位（与主网格一致）
                guard let src = dragSourceIndex, src < orderedIDs.count else { return }
                let cols = currentColumns
                let rws = currentRows
                let slot = folderGeometryNow(columns: cols, rowsCount: rws)?.slotUnderCursor(value.location)
                let dst = slot.flatMap { min(max($0, 0), orderedIDs.count - 1) } ?? src
                guard dst != src else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    let item = orderedIDs.remove(at: src)
                    orderedIDs.insert(item, at: min(dst, orderedIDs.count))
                }
                onReorder?(orderedIDs)
            }
    }
}

// MARK: - Preference Keys

/// 仅测量首格全局 frame（供纯几何落点推导），非逐格命中测试。
private struct FirstCellFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let v = nextValue()
        if v != .zero { value = v }
    }
}

// MARK: - 文件夹背景虚化层（方案 C）

/// 文件夹面板背后的虚化层：模糊/折射「窗口内的主网格」（非桌面），风格跟随全局背景样式。
/// - 磨砂模式：`NSVisualEffectView(blendingMode: .withinWindow, material: .fullScreenUI)`
///   模糊窗口自身内容（与主网格同窗口，故能虚化它），是 macOS 菜单/弹窗虚化自身内容的标准做法。
/// - 玻璃模式：`NSGlassEffectView` 液态玻璃，折射其下的网格，与全屏背景的玻璃观感一致。
/// 注：全屏背景 `BackgroundView` 用的是 `.behindWindow`（模糊桌面），与本层 `.withinWindow`（模糊
/// 窗口内网格）是不同的混合模式，不可混用——文件夹背后要虚化的是窗口内的主网格，必须用 withinWindow。
private struct FolderBackdropView: NSViewRepresentable {
    var isGlass: Bool

    func makeNSView(context: Context) -> NSView {
        if isGlass {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 0      // 全屏无圆角
            glass.tintColor = nil       // 跟随系统环境
            glass.style = .regular      // 常规折射玻璃
            return glass
        } else {
            let vev = NSVisualEffectView()
            vev.material = .fullScreenUI
            vev.blendingMode = .withinWindow   // 模糊窗口内主网格（关键）
            vev.state = .active
            return vev
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
