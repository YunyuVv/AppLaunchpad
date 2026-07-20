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
    let onDropOnFolder: ((String, UUID) -> Void)?  // (bundleID, folderID) 拖 app 进文件夹

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
        .gesture(isEditMode ? dragGesture : nil)
    }

    @ViewBuilder
    private func iconCell(item: LayoutItem, slotIndex: Int) -> some View {
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
                .opacity(isDragged ? 0.85 : 1.0)
                .zIndex(isDragged ? 1 : 0)
                .animation(.spring(duration: 0.2), value: dragState.targetSlotIndex)
                .animation(.spring(duration: 0.2), value: isDragged)
                .background(slotFrameTracker(slotIndex: slotIndex))
            } else {
                Color.clear.frame(width: 100)
            }

        case .folder(let id):
            if let folder = folders[id] {
                FolderThumbnailView(
                    folder: folder,
                    apps: apps,
                    isEditMode: isEditMode,
                    onTap: { onTapFolder(folder) },
                    onLongPress: onLongPress
                )
                .background(slotFrameTracker(slotIndex: slotIndex))
            } else {
                Color.clear.frame(width: 100)
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

    // MARK: - 拖拽手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                if !dragState.isDragging {
                    if let (slotIdx, bundleID) = appSlotAt(location: value.startLocation) {
                        onBeginDrag(bundleID, slotIdx)
                    }
                } else if let nearest = nearestSlot(to: value.location) {
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

    private func appSlotAt(location: CGPoint) -> (Int, String)? {
        for (idx, frame) in slotFrames {
            if frame.contains(location), idx < items.count,
               case .app(let id) = items[idx] { return (idx, id) }
        }
        return nil
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
