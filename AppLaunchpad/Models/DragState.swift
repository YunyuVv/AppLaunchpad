import Foundation

/// 图标拖拽过程中的实时状态
struct DragState {
    var isDragging: Bool = false
    var draggedBundleID: String = ""
    var sourcePageIndex: Int = 0
    var sourceSlotIndex: Int = 0
    var targetSlotIndex: Int = 0
    /// 鼠标当前位置（SwiftUI global 坐标），用于渲染浮动图标
    var dragLocation: CGPoint = .zero

    var isEmpty: Bool { !isDragging }
}
