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
    let onTapApp: (AppInfo) -> Void
    let onTapFolder: (FolderInfo) -> Void
    let onLongPress: () -> Void
    let onDeleteApp: ((AppInfo) -> Void)?
    let onBeginDrag: (String, Int, CGPoint) -> Void
    let onUpdateDragTarget: (Int, CGPoint) -> Void
    let onEndDrag: () -> Void
    let onDropOnFolder: ((String, UUID) -> Void)?

    @State private var slotFrames: [Int: CGRect] = [:]

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
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, rowItems in
                    HStack(spacing: hSpacing) {
                        ForEach(Array(rowItems.enumerated()), id: \.offset) { colIdx, item in
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(SlotFrameKey.self) { newFrames in
                // 仅在帧真正变化时更新，防止 preference → state → render 循环
                if newFrames != slotFrames { slotFrames = newFrames }
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
                    let isDragged = dragState.isDragging && dragState.draggedBundleID == bundleID
                    let isFolderTarget = dragState.folderTargetID == bundleID
                    let isSelected = !dragState.isDragging && selectedSlotIndex == slotIndex
                    let folderProgressValue: Double = {
                        guard dragState.isDragging, dragState.targetSlotIndex == slotIndex else { return 0 }
                        return dragState.folderTargetID == bundleID ? 1 : dragState.folderProgress
                    }()

                    AppIconView(
                        app: app,
                        iconSize: effectiveIconSize,
                        isEditMode: isEditMode,
                        onTap: { onTapApp(app) },
                        onLongPress: onLongPress,
                        onDelete: app.isMASApp ? { onDeleteApp?(app) } : nil
                    )
                    .opacity(isDragged ? 0.2 : 1.0)
                    .scaleEffect(isFolderTarget ? 1.12 : (isSelected ? 1.06 : 1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: effectiveIconSize * 0.22)
                            .strokeBorder(
                                Color.white.opacity(isSelected ? 0.9 : (isFolderTarget ? 0.85 : 0)),
                                lineWidth: isSelected ? 3 : 2
                            )
                            .frame(width: effectiveIconSize + (isSelected ? 12 : 8), height: effectiveIconSize + (isSelected ? 12 : 8))
                            .allowsHitTesting(false)
                    )
                    .overlay(folderProgressRing(value: folderProgressValue, iconSize: effectiveIconSize))
                    .animation(.spring(duration: 0.25), value: isFolderTarget)
                    .animation(.easeOut(duration: 0.12), value: isSelected)
                } else {
                    Color.clear.frame(width: cellWidth, height: cellHeight)
                }

            case .folder(let id):
                if let folder = folders[id] {
                    let isSelected = !dragState.isDragging && selectedSlotIndex == slotIndex
                    FolderThumbnailView(
                        folder: folder, apps: apps,
                        iconSize: effectiveIconSize,
                        isEditMode: isEditMode,
                        isSelected: isSelected,
                        onTap: { onTapFolder(folder) },
                        onLongPress: onLongPress
                    )
                } else {
                    Color.clear.frame(width: cellWidth, height: cellHeight)
                }
            }

            if isEditMode {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: cellWidth, height: cellHeight)
                    .gesture(cellDragGesture(item: item, slotIndex: slotIndex))
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

    private func cellDragGesture(item: LayoutItem, slotIndex: Int) -> some Gesture {
        var hasBegunDrag = false
        return DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                if !hasBegunDrag {
                    hasBegunDrag = true
                    if case .app(let bundleID) = item {
                        onBeginDrag(bundleID, slotIndex, value.startLocation)
                    }
                }
                if let nearest = nearestSlot(to: value.location) {
                    onUpdateDragTarget(nearest, value.location)
                }
            }
            .onEnded { value in
                if let targetSlot = nearestSlot(to: value.location),
                   targetSlot < items.count,
                   case .folder(let fid) = items[targetSlot],
                   case .app(let bundleID) = item {
                    onDropOnFolder?(bundleID, fid)
                } else {
                    onEndDrag()
                }
            }
    }

    private func slotFrameTracker(slotIndex: Int) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SlotFrameKey.self,
                value: [slotIndex: geo.frame(in: .global)]
            )
        }
    }

    private func nearestSlot(to point: CGPoint) -> Int? {
        slotFrames.min { a, b in
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
