import SwiftUI

/// 单页图标网格，支持编辑模式、拖拽排序、文件夹缩略图
struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]
    let folders: [UUID: FolderInfo]
    let columns: Int
    let rows: Int                // 每页最大行数，由 LaunchpadView 根据屏幕高度传入
    let hSpacing: CGFloat        // 列间距，由父级传入以实时响应设置
    let vSpacing: CGFloat        // 行间距，由父级传入以实时响应设置
    let iconSize: CGFloat          // 由 LaunchpadView 计算后传入，不在此处观察 UserPreferences
    let pageIndex: Int
    let selectedSlotIndex: Int?          // 键盘导航选中态（nil = 无选中）
    let isEditMode: Bool
    let dragState: DragState
    let viewModel: LaunchpadViewModel
    let onTapApp: (AppInfo) -> Void
    let onTapFolder: (FolderInfo) -> Void
    let onLongPress: () -> Void
    let onBeginDrag: (String, CGPoint) -> Void
    let onUpdateDragTarget: (Int, CGPoint) -> Void
    let onEndDrag: () -> Void
    let onDropOnFolder: ((String, UUID) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let rows = items.chunked(into: columns)
            let safeRows = max(1, self.rows)
            let cellW = (geo.size.width - hSpacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellH = (geo.size.height - vSpacing * CGFloat(safeRows - 1)) / CGFloat(safeRows)
            // 图标尺寸已由 LaunchpadView 根据 cell 大小和标签预算计算，
            // 这里仅做最后的安全限幅，避免手动设置过大时溢出单元格。
            let effectiveIconSize = min(max(iconSize, 24), cellW - 16, cellH - 16)

            VStack(spacing: vSpacing) {
                ForEach(0..<rows.count, id: \.self) { rowIdx in
                    let rowItems = rows[rowIdx]
                    HStack(spacing: hSpacing) {
                        // 用图标本身（LayoutItem）作为稳定身份，让同一 app 在重排/刷新时尽量复用视图。
                        ForEach(Array(rowItems.enumerated()), id: \.element) { colIdx, item in
                            let slotIdx = rowIdx * columns + colIdx
                            iconCell(item: item, slotIndex: slotIdx, cellWidth: cellW, cellHeight: cellH, effectiveIconSize: effectiveIconSize)
                        }
                        if rowItems.count < columns {
                            ForEach(0..<(columns - rowItems.count), id: \.self) { _ in
                                Color.clear.frame(width: cellW, height: cellH)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // 拖拽中目标槽位变化 → 邻近图标以弹簧动画让位（实时让位效果）。
            // 仅随 targetSlotIndex 触发：非拖拽时翻页/重排不会误触发弹簧，保持「即时切换」体验。
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: dragState.targetSlotIndex)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(SlotFrameKey.self) { newFrames in
                // 仅在帧真正变化时更新，防止 preference → state → render 循环
                if newFrames != viewModel.slotFrames { viewModel.slotFrames = newFrames }
            }
        }
    }

    // MARK: - 图标格

    @ViewBuilder
    private func iconCell(item: LayoutItem, slotIndex: Int, cellWidth: CGFloat, cellHeight: CGFloat, effectiveIconSize: CGFloat) -> some View {
        ZStack {
            switch item {
            case .app(let bundleID):
                if let app = apps.first(where: { $0.bundleID == bundleID }) {
                    // folderCandidateID 在进度走满前即指向真正的目标 app，避免实时让位后
                    // 进度环误画在被拖 app 自己的 ghost 上。
                    let isDragged = dragState.isDragging && dragState.draggedBundleID == bundleID
                    let isFolderTarget = !isDragged
                                      && (dragState.folderCandidateID == bundleID
                                          || dragState.folderTargetID == bundleID)
                    let isSelected = !dragState.isDragging && selectedSlotIndex == slotIndex
                    let folderProgressValue: Double = {
                        guard dragState.isDragging, !isDragged else { return 0 }
                        if dragState.folderTargetID == bundleID { return 1 }
                        if dragState.folderCandidateID == bundleID { return dragState.folderProgress }
                        return 0
                    }()

                    AppIconView(
                        app: app,
                        iconSize: effectiveIconSize,
                        isEditMode: isEditMode,
                        onTap: { onTapApp(app) },
                        onLongPress: onLongPress,
                        onDelete: nil
                    )
                    .scaleEffect(isFolderTarget ? 1.12 : (isSelected ? 1.06 : 1.0))
                    .overlay(
                        ZStack {
                            // 即时标识环：悬停到 app 上立即显示完整蓝圈，
                            // 作为"将创建文件夹"的明确标识（不随进度从 0 渐显）。
                            if isFolderTarget {
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 4)
                                    .frame(width: effectiveIconSize * 0.92, height: effectiveIconSize * 0.92)
                                    .offset(y: -(effectiveIconSize * 0.14 + 3))
                                    .allowsHitTesting(false)
                            }
                            // 0.7s 确认倒计时的内弧（仅作微妙提示，补充在标识环内圈）
                            folderProgressRing(value: folderProgressValue, iconSize: effectiveIconSize)
                        }
                    )
                    // 被拖 app 在网格中隐藏，只保留跟随鼠标的浮层图标。
                    // opacity 必须放在 overlay 之后，否则 overlay（进度环）不会随内容一起隐藏。
                    .opacity(isDragged ? 0.0 : 1.0)
                    .animation(.spring(duration: 0.25), value: isFolderTarget)
                    .animation(.easeOut(duration: 0.12), value: isSelected)
                } else {
                    Color.clear.frame(width: cellWidth, height: cellHeight)
                }

            case .folder(let id):
                if let folder = folders[id] {
                    let isSelected = !dragState.isDragging && selectedSlotIndex == slotIndex
                    let isFolderHover = dragState.folderHoverID == id
                    FolderThumbnailView(
                        folder: folder, apps: apps,
                        iconSize: effectiveIconSize,
                        isEditMode: isEditMode,
                        isSelected: isSelected,
                        onTap: { onTapFolder(folder) },
                        onLongPress: onLongPress
                    )
                    .scaleEffect(isFolderHover ? 1.12 : 1.0)
                    .overlay(
                        Group {
                            if isFolderHover {
                                RoundedRectangle(cornerRadius: effectiveIconSize * 0.22)
                                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                                    .frame(width: effectiveIconSize + 8, height: effectiveIconSize + 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    )
                    // 注：文件夹本身不参与拖拽（避免「创建后文件夹被拖动滑动」的观感），
                    // 仅保留点击打开 / 长按进编辑模式。
                } else {
                    Color.clear.frame(width: cellWidth, height: cellHeight)
                }
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        .background(slotFrameTracker(slotIndex: slotIndex))
    }

    // MARK: - 拖拽到文件夹的进度环

    /// 拖拽时悬停在某个图标上、准备将其归入文件夹的进度环。
    /// 仅在 value > 0 时绘制；value 达到 1 表示已触发入文件夹动作。
    @ViewBuilder
    private func folderProgressRing(value: Double, iconSize: CGFloat) -> some View {
        if value > 0 {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: iconSize * 0.92, height: iconSize * 0.92)
            .offset(y: -(iconSize * 0.14 + 3))   // 把圆环上移到图标中心（标签在图标下方）
            .allowsHitTesting(false)
        }
    }

    // MARK: - 拖拽

    private func slotFrameTracker(slotIndex: Int) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SlotFrameKey.self,
                value: [slotIndex: geo.frame(in: .global)]
            )
        }
    }

    private func nearestSlot(to point: CGPoint) -> Int? {
        viewModel.slotFrames.min { a, b in
            hypot(a.value.midX - point.x, a.value.midY - point.y) <
            hypot(b.value.midX - point.x, b.value.midY - point.y)
        }?.key
    }
}

private struct SlotFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
