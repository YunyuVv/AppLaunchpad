import SwiftUI

/// 单页图标网格，支持编辑模式、拖拽排序、文件夹缩略图
struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]
    let folders: [UUID: FolderInfo]
    let columns: Int
    let pageIndex: Int
    let isEditMode: Bool
    let dragState: DragState
    let onTapApp: (AppInfo) -> Void
    let onTapFolder: (FolderInfo) -> Void
    let onLongPress: () -> Void
    let onDeleteApp: ((AppInfo) -> Void)?
    let onBeginDrag: (String, Int) -> Void
    let onUpdateDragTarget: (Int) -> Void
    let onEndDrag: () -> Void
    let onDropOnFolder: ((String, UUID) -> Void)?

    @State private var slotFrames: [Int: CGRect] = [:]

    var body: some View {
        let rows = items.chunked(into: columns)
        return VStack(spacing: 30) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, rowItems in
                HStack(spacing: 20) {
                    ForEach(Array(rowItems.enumerated()), id: \.offset) { colIdx, item in
                        let slotIdx = rowIdx * columns + colIdx
                        iconCell(item: item, slotIndex: slotIdx)
                    }
                    if rowItems.count < columns {
                        ForEach(0..<(columns - rowItems.count), id: \.self) { _ in
                            Color.clear.frame(width: 100)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 60)
        .onPreferenceChange(SlotFrameKey.self) { slotFrames = $0 }
        // 拖拽手势移到每个格子内部（见 iconCell），不在 VStack 层面处理
    }

    // MARK: - 图标格

    @ViewBuilder
    private func iconCell(item: LayoutItem, slotIndex: Int) -> some View {
        ZStack {
            switch item {
            case .app(let bundleID):
                if let app = apps.first(where: { $0.bundleID == bundleID }) {
                    let isDragged = dragState.isDragging && dragState.draggedBundleID == bundleID
                    AppIconView(
                        app: app,
                        isEditMode: isEditMode,
                        onTap: { onTapApp(app) },
                        onLongPress: onLongPress,
                        onDelete: app.isMASApp ? { onDeleteApp?(app) } : nil
                    )
                    .scaleEffect(isDragged ? 1.15 : 1.0)
                    .opacity(isDragged ? 0.8 : 1.0)
                    .zIndex(isDragged ? 1 : 0)
                    .animation(.spring(duration: 0.2), value: dragState.targetSlotIndex)
                    .animation(.spring(duration: 0.2), value: isDragged)
                } else {
                    Color.clear.frame(width: 100)
                }

            case .folder(let id):
                if let folder = folders[id] {
                    FolderThumbnailView(
                        folder: folder, apps: apps,
                        isEditMode: isEditMode,
                        onTap: { onTapFolder(folder) },
                        onLongPress: onLongPress
                    )
                } else {
                    Color.clear.frame(width: 100)
                }
            }

            // 编辑模式下：透明覆盖层专门负责捕获拖拽事件
            // 放在最上层，直接绑定 slotIndex，无需从坐标反查槽位
            if isEditMode {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 100, height: 130)
                    .gesture(cellDragGesture(item: item, slotIndex: slotIndex))
            }
        }
        .background(slotFrameTracker(slotIndex: slotIndex))
    }

    // MARK: - 每个格子的拖拽手势

    private func cellDragGesture(item: LayoutItem, slotIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                if !dragState.isDragging {
                    // 拖拽起点：直接用格子已知的 bundleID 和 slotIndex，无需坐标反查
                    if case .app(let bundleID) = item {
                        onBeginDrag(bundleID, slotIndex)
                    }
                }
                // 实时更新目标槽位（通过全局坐标找最近格子）
                if let nearest = nearestSlot(to: value.location) {
                    onUpdateDragTarget(nearest)
                }
            }
            .onEnded { value in
                // 检查是否拖到了文件夹上
                if dragState.isDragging,
                   let targetSlot = nearestSlot(to: value.location),
                   targetSlot < items.count,
                   case .folder(let fid) = items[targetSlot] {
                    onDropOnFolder?(dragState.draggedBundleID, fid)
                } else {
                    onEndDrag()
                }
            }
    }

    // MARK: - 辅助

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
