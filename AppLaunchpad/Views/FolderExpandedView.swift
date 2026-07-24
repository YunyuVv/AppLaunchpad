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

    private let gridColumns: Int = 5

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
        let columns = min(gridColumns, max(1, visualApps.count))
        let draggedApp = dragSourceIndex.flatMap { src in
            src < orderedIDs.count ? apps.first { $0.bundleID == orderedIDs[src] } : nil
        }

        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            GeometryReader { geo in
                let panelW = geo.size.width * 0.7
                let panelH = geo.size.height * 0.7

                VStack(spacing: 0) {
                    Text(folder.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 28)
                        .padding(.bottom, 20)

                    appGrid(columns: columns, visualApps: visualApps)
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

    private func appGrid(columns: Int, visualApps: [AppInfo]) -> some View {
        let rows = visualApps.chunked(into: columns)
        return ScrollView {
            VStack(spacing: 24) {
                ForEach(0..<rows.count, id: \.self) { rowIdx in
                    HStack(spacing: 24) {
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
                        if rows[rowIdx].count < columns {
                            ForEach(0..<(columns - rows[rowIdx].count), id: \.self) { _ in
                                Color.clear.frame(width: iconSize + 16, height: iconSize + 24)
                            }
                        }
                        Spacer()
                    }
                }
            }
            // 弹簧让位动画（与主网格 GridPageView 参数一致）
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: visualApps.map(\.bundleID))
        }
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
