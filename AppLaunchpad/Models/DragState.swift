import Foundation

/// 图标拖拽过程中的实时状态
struct DragState {
    var isDragging: Bool = false
    var draggedBundleID: String = ""
    var sourcePageIndex: Int = 0
    var sourceSlotIndex: Int = 0
    var targetSlotIndex: Int = 0
    var dragLocation: CGPoint = .zero
    /// 悬停足够长时间后，准备与之合并的目标 app bundleID（触发文件夹创建）
    var folderTargetID: String? = nil

    var isEmpty: Bool { !isDragging }
    var isFolderMode: Bool { folderTargetID != nil }
}
