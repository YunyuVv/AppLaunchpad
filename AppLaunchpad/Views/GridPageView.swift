import SwiftUI

/// 单页图标网格，支持编辑模式和拖拽排序
struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]
    let columns: Int
    let pageIndex: Int
    let isEditMode: Bool
    let dragState: DragState
    let onTapApp: (AppInfo) -> Void
    let onLongPress: () -> Void
    let onDeleteApp: ((AppInfo) -> Void)?
    let onBeginDrag: (String, Int) -> Void      // (bundleID, slotIndex)
    let onUpdateDragTarget: (Int) -> Void        // slotIndex
    let onEndDrag: () -> Void

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
                    // 补齐最后一行
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
        // 编辑模式下的拖拽手势（覆盖整个网格区域）
        .gesture(isEditMode ? dragGesture : nil)
    }

    // MARK: - 单个图标格

    @ViewBuilder
    private func iconCell(item: LayoutItem, slotIndex: Int) -> some View {
        if case .app(let bundleID) = item,
           let app = apps.first(where: { $0.bundleID == bundleID }) {
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
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SlotFrameKey.self,
                        value: [slotIndex: geo.frame(in: .global)]
                    )
                }
            )
        } else {
            Color.clear.frame(width: 100)
        }
    }

    // MARK: - 拖拽手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                if !dragState.isDragging {
                    // 找出手势起始位置对应的槽位和 app
                    if let (slotIdx, bundleID) = slotAt(location: value.startLocation) {
                        onBeginDrag(bundleID, slotIdx)
                    }
                } else {
                    // 更新目标槽位
                    if let nearest = nearestSlot(to: value.location) {
                        onUpdateDragTarget(nearest)
                    }
                }
            }
            .onEnded { _ in onEndDrag() }
    }

    /// 根据全局坐标找出对应槽位和 bundleID
    private func slotAt(location: CGPoint) -> (Int, String)? {
        for (idx, frame) in slotFrames {
            if frame.contains(location), idx < items.count {
                if case .app(let id) = items[idx] { return (idx, id) }
            }
        }
        return nil
    }

    /// 找到距离给定点最近的槽位索引
    private func nearestSlot(to point: CGPoint) -> Int? {
        slotFrames.min { a, b in
            let da = hypot(a.value.midX - point.x, a.value.midY - point.y)
            let db = hypot(b.value.midX - point.x, b.value.midY - point.y)
            return da < db
        }?.key
    }
}

// MARK: - PreferenceKey

/// 收集各图标槽位的全局 frame，用于拖拽命中检测
private struct SlotFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Array Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
