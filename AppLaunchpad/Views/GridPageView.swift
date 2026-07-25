import SwiftUI

/// 单页图标网格，支持编辑模式、拖拽排序
struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]
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
    let onLongPress: () -> Void
    let onBeginDrag: (String, CGPoint) -> Void
    let onUpdateDragTarget: (Int, CGPoint) -> Void
    let onEndDrag: () -> Void
    let onTapFolder: (UUID) -> Void

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
// 拖拽中几何落点（cursorSlot）变化 → 邻近图标以弹簧动画让位（实时让位效果）。
// 关键：value 跟随 items 数组（pageItemsWithDrag 返回的让位布局）。
// 让位布局与 endDrag 写入的最终布局顺序一致（都是 insert at to），
// 因此松手瞬间 items 数组不变 → 此动画不再触发 → 不会出现「松手后整网 spring
// 把图标弹到非最终位置」的残影。非拖拽时翻页/重排也不会误触发弹簧。
.animation(.spring(response: 0.3, dampingFraction: 0.9), value: items)
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - 图标格

    @ViewBuilder
    private func iconCell(item: LayoutItem, slotIndex: Int, cellWidth: CGFloat, cellHeight: CGFloat, effectiveIconSize: CGFloat) -> some View {
        let isSelected = !dragState.isDragging && selectedSlotIndex == slotIndex

        switch item {
        case .app(let bundleID):
            // 关键：每个格子必须固定为 cellW × cellH，使视觉网格与拖拽几何
            // (GridGeometry 的均匀格点) 严格对齐。否则图标缩成内容尺寸、行高/列宽
            // 不一致，会出现「布局乱了 / 没全屏 / 拖拽落点对不上」三类问题。
            ZStack {
                if let app = apps.first(where: { $0.bundleID == bundleID }) {
                    let isDragged = dragState.isDragging && dragState.draggedBundleID == bundleID
                    let isHoverTarget = dragState.hoverTargetBundleID == bundleID

                    AppIconView(
                        app: app,
                        iconSize: effectiveIconSize,
                        isEditMode: isEditMode,
                        onTap: { onTapApp(app) },
                        onLongPress: onLongPress,
                        onDeleteApp: { viewModel.deleteApp(app) }
                    )
                    .scaleEffect(isHoverTarget ? 1.15 : (isSelected ? 1.06 : 1.0))
                    .opacity(isDragged ? 0.0 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isHoverTarget)
                    .animation(.easeOut(duration: 0.12), value: isSelected)
                }
            }
            .frame(width: cellWidth, height: cellHeight)

        case .folder(let folderID):
            if let folder = viewModel.folderInfo(for: folderID) {
                let isHoverTarget = dragState.hoverTargetFolderID == folderID
                // 与 app case 对称：拖拽中的源文件夹在网格里完全透明（lift state），
                // 只让跟随光标的 chrome-free 浮窗可见，避免「两个 Books」残影。
                let isDragged = dragState.isDragging && dragState.draggedFolderID == folderID
                FolderThumbnailView(
                    folder: folder,
                    apps: apps,
                    iconSize: effectiveIconSize,
                    isEditMode: isEditMode,
                    isSelected: isSelected,
                    onTap: { onTapFolder(folderID) },
                    onLongPress: onLongPress,
                    onDelete: { viewModel.deleteFolder(folderID, expandToPage: pageIndex) }
                )
                .scaleEffect(isHoverTarget ? 1.15 : 1.0)
                .opacity(isDragged ? 0.0 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHoverTarget)
                .frame(width: cellWidth, height: cellHeight)
            } else {
                Color.clear.frame(width: cellWidth, height: cellHeight)
            }
        }
    }

    // MARK: - 拖拽

    // 注：网格拖拽的落点统一由 LaunchpadViewModel 的 GridGeometry 几何推导，
    // 不再在此收集 measured frame（测量帧 + 让位动画会互相打架导致落点振荡）。

}
