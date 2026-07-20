import SwiftUI

/// 单页图标网格，支持编辑模式、拖拽排序（浮动图标由 LaunchpadView 渲染）、文件夹缩略图
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
    /// (bundleID, slotIndex, startLocation)
    let onBeginDrag: (String, Int, CGPoint) -> Void
    /// (nearestSlotIndex, currentLocation)
    let onUpdateDragTarget: (Int, CGPoint) -> Void
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
                        isEditMode: isEditMode,
                        onTap: { onTapApp(app) },
                        onLongPress: onLongPress,
                        onDelete: app.isMASApp ? { onDeleteApp?(app) } : nil
                    )
                    // 被拖图标：幽灵占位（原位保持不动）
                    .opacity(isDragged ? 0.2 : 1.0)
                    // 文件夹创建目标：放大 + 亮圈
                    .scaleEffect(isFolderTarget ? 1.12 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Color.white.opacity(isFolderTarget ? 0.85 : 0), lineWidth: 2)
                            .frame(width: 88, height: 88)
                            .allowsHitTesting(false)
                    )
                    .animation(.spring(duration: 0.25), value: isFolderTarget)
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

            // 编辑模式：透明覆盖层捕获拖拽事件
            if isEditMode {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 100, height: 130)
                    .gesture(cellDragGesture(item: item, slotIndex: slotIndex))
            }
        }
        .background(slotFrameTracker(slotIndex: slotIndex))
    }

    // MARK: - 拖拽手势（格子级别）

    private func cellDragGesture(item: LayoutItem, slotIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                if !dragState.isDragging {
                    if case .app(let bundleID) = item {
                        onBeginDrag(bundleID, slotIndex, value.startLocation)
                    }
                }
                if let nearest = nearestSlot(to: value.location) {
                    onUpdateDragTarget(nearest, value.location)
                }
            }
            .onEnded { value in
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
