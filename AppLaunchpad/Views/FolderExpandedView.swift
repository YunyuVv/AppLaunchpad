import SwiftUI

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
    /// 各 app cell 的全局 frame
    @State private var cellFrames: [String: CGRect] = [:]
    /// 正在拖出面板范围（→ 面板立即透明）
    @State private var isDraggingOut = false

    init(folder: FolderInfo, apps: [AppInfo], iconSize: CGFloat,
         onDismiss: @escaping () -> Void, onLaunch: @escaping (AppInfo) -> Void,
         onDragOutHandoff: ((AppInfo, CGPoint) -> Void)? = nil,
         onDragOutMove: ((CGPoint) -> Void)? = nil,
         onDragOutEnd: (() -> Void)? = nil,
         onReorder: (([String]) -> Void)? = nil) {
        self.folder = folder
        self.apps = apps
        self.iconSize = iconSize
        self.onDismiss = onDismiss
        self.onLaunch = onLaunch
        self.onDragOutHandoff = onDragOutHandoff
        self.onDragOutMove = onDragOutMove
        self.onDragOutEnd = onDragOutEnd
        self.onReorder = onReorder
        self._orderedIDs = State(initialValue: folder.appIDs)
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
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            GeometryReader { geo in
                // 面板取屏宽 55%（之前 70% 偏胖）：narrower → 同屏宽下每行自然容纳列数变少，
                // 完全由面板宽/格宽/间距动态决定，没有人为列数上限。
                let panelW = geo.size.width * 0.55
                let panelH = geo.size.height * 0.7

                VStack(spacing: 0) {
                    Text(folder.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 28)
                        .padding(.bottom, 20)

                    appGrid(panelW: panelW, panelH: panelH, visualApps: visualApps)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                }
                .frame(width: panelW, height: panelH)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                )
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                // 面板 frame = 外层 GeometryReader 填满全屏 → 计算 70% 居中区域的全局坐标。
                // 用 onAppear 写入引用类型 FrameBox，手势闭包通过指针始终读到最新值
                // （避免值类型 @State 被手势创建时快照捕获 → 永远是 .zero 的经典陷阱）。
                .onAppear {
                    let globalOrigin = geo.frame(in: .global).origin
                    panelFrameBox.frame = CGRect(
                        x: globalOrigin.x + (geo.size.width - panelW) / 2,
                        y: globalOrigin.y + (geo.size.height - panelH) / 2,
                        width: panelW, height: panelH
                    )
                }

                // 浮动图标
                if let app = draggedApp {
                    AppIconView(app: app, iconSize: iconSize, isEditMode: false,
                                onTap: {}, onLongPress: {}, onDelete: nil)
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

    // MARK: - App Grid

    /// 每 cell 视觉宽度 = 图标 + 左右各 8pt 内边距；与 AppIconView.cellWidth 保持一致。
    private var cellVisualWidth: CGFloat { iconSize + 16 }
    /// 列间距 = HStack spacing（保持与原实现一致）。
    private let hSpacing: CGFloat = 24
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
                            AppIconView(app: app, iconSize: iconSize, isEditMode: false,
                                        onTap: { onLaunch(app) },
                                        onLongPress: {},
                                        onDelete: nil)
                                .opacity(isDragged ? 0.0 : 1.0)
                                .background(
                                    GeometryReader { cg in
                                        Color.clear.preference(
                                            key: CellFrameKey.self,
                                            value: [app.bundleID: cg.frame(in: .global)]
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
            .frame(maxWidth: .infinity, maxHeight: availableH, alignment: .topLeading)
            // 弹簧让位动画（与主网格 GridPageView 参数一致）
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: visualApps.map(\.bundleID))
        }
        // 限制 ScrollView 高度，否则 VStack 的 maxHeight:.infinity 拿不到视口约束。
        .frame(height: availableH)
        .scrollDisabled(dragSourceIndex != nil)
        .onPreferenceChange(CellFrameKey.self) { frames in
            cellFrames.merge(frames) { _, new in new }
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

                // 内部 make-way：通过 cellFrames hit-test 更新目标槽位
                if let targetID = hitTestApp(at: value.location),
                   let targetIdx = orderedIDs.firstIndex(of: targetID) {
                    dragCursorIndex = targetIdx
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

                // 内部重排
                guard let src = dragSourceIndex, src < orderedIDs.count else { return }
                let targetID = hitTestApp(at: value.location)
                let dst = targetID.flatMap { orderedIDs.firstIndex(of: $0) } ?? src
                guard dst != src else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    let item = orderedIDs.remove(at: src)
                    orderedIDs.insert(item, at: min(dst, orderedIDs.count))
                }
                onReorder?(orderedIDs)
            }
    }

    private func hitTestApp(at location: CGPoint) -> String? {
        for (bundleID, frame) in cellFrames where frame.contains(location) {
            return bundleID
        }
        return nil
    }
}

// MARK: - Preference Keys

private struct CellFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
