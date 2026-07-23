import Foundation

/// 图标拖拽过程中的实时状态。
/// 当前仅支持「网格内 app 重排」一种场景（文件夹功能已移除），
/// 故不再有 DragContext / folderHoverID 等文件夹相关字段。
struct DragState {
    var isDragging: Bool = false
    var draggedBundleID: String = ""
    /// 被拖 app 所在的源页（跨页拖拽时落点页 != 源页）
    var sourcePageIndex: Int = 0
    /// 被拖 app 在源页的起始槽位
    var sourceSlotIndex: Int = 0
    /// 光标当前所在的几何槽位（由 GridGeometry 推导，非 measured frame）。
    /// 同时作为 make-way 弹簧动画的驱动值，因它来自固定几何、不随让位动画漂移，避免振荡。
    var cursorSlot: Int = 0
    var dragLocation: CGPoint = .zero

    var isEmpty: Bool { !isDragging }
}
