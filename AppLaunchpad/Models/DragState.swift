import Foundation

/// 图标拖拽过程中的实时状态。
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

    // ── 文件夹悬停（2026-07-24）──
    /// 光标悬停在哪个 app 的 icon 上（nil = 未悬停）
    var hoverTargetBundleID: String? = nil
    /// 光标悬停在哪个文件夹的 icon 上
    var hoverTargetFolderID: UUID? = nil
    /// 悬停目标在原布局中的槽位索引（用于创建文件夹时定位，与 cursorSlot 解耦）
    var hoverTargetSlot: Int? = nil
    /// 被拖拽的是 app 还是文件夹
    var draggedItemType: DragItemType = .app
    /// 被拖拽的文件夹 ID（仅 draggedItemType == .folder 时有效）
    var draggedFolderID: UUID? = nil

    var isEmpty: Bool { !isDragging }
}

/// 拖拽源的项类型
enum DragItemType: Equatable {
    case app
    case folder
}
