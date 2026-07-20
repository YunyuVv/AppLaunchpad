import SwiftUI

/// 单页图标网格，支持编辑模式、拖拽排序、文件夹缩略图
struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]
    let folders: [UUID: FolderInfo]
    let columns: Int
    let iconSize: CGFloat          // 由 LaunchpadView 计算后传入，不在此处观察 UserPreferences
    let pageIndex: Int
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

    private var cellWidth: CGFloat { iconSize + 20 }
    private var colSpacing: CGFloat { 20 }
    private var rowSpacing: CGFloat { 28 }

    var body: some View {
        let rows = items.chunked(into: columns)
        return VStack(spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, rowItems in
                HStack(spacing: colSpacing) {
                    ForEach(Array(rowItems.enumerated()), id: \.offset) { colIdx, item in
                        let slotIdx = rowIdx * columns + colIdx
                        iconCell(item: item, slotIndex: slotIdx)
                    }
                    if rowItems.count < columns {
                        ForEach(0..<(columns - rowItems.count), id: \.self) { _ in
                            Color.clear.frame(width: cellWidth)
                        }
                    }
                }
            }
        }
        .onPreferenceChange(SlotFrameKey.self) { newFrames in
            // 仅在帧真正变化时更新，防止 preference → state → render 循环
            if newFrames != slotFrames { slotFrames = newFrames }
        }
    }

    // MARK: - 图标格

    @ViewBuilder
    private func iconCell(item: LayoutItem, slotIndex: Int) -> some View {
        ZStack {
            switch item {
            case .app(let bundleID):
                if let app = apps.first(where: { $0.bundleID == bundleID }) {
                    let isDragged = dragState.isDragging && dragState.draggedBundleID == bundleID
                    let isFolderTarget = dragState.folderTargetID == bundleID

                    AppIconView(
                        app: app,
                        iconSize: iconSize,
                        isEditMode: isEditMode,
                        onTap: { onTapApp(app) },
                        onLongPress: onLongPress,
                        onDelete: app.isMASApp ? { onDeleteApp?(app) } : nil
                    )
                    .opacity(isDragged ? 0.2 : 1.0)
                    .scaleEffect(isFolderTarget ? 1.12 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: iconSize * 0.22)
                            .strokeBorder(Color.white.opacity(isFolderTarget ? 0.85 : 0), lineWidth: 2)
                            .frame(width: iconSize + 8, height: iconSize + 8)
                            .allowsHitTesting(false)
                    )
                    .animation(.spring(duration: 0.25), value: isFolderTarget)
                } else {
                    Color.clear.frame(width: cellWidth)
                }

            case .folder(let id):
                if let folder = folders[id] {
                    FolderThumbnailView(
                        folder: folder, apps: apps,
                        iconSize: iconSize,
                        isEditMode: isEditMode,
                        onTap: { onTapFolder(folder) },
                        onLongPress: onLongPress
                    )
                } else {
                    Color.clear.frame(width: cellWidth)
                }
            }

            if isEditMode {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: cellWidth, height: iconSize + 30)
                    .gesture(cellDragGesture(item: item, slotIndex: slotIndex))
            }
        }
        .background(slotFrameTracker(slotIndex: slotIndex))
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
