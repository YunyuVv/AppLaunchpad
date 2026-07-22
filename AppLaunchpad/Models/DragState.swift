import Foundation

/// 拖拽发生的上下文：网格内拖拽 vs 文件夹内拖拽。
/// 让同一套 DragState 状态机同时驱动两种场景，避免两套平行逻辑。
enum DragContext {
    case grid(pageIndex: Int)
    case folder(folderID: UUID)
}

/// 图标拖拽过程中的实时状态
struct DragState {
    var isDragging: Bool = false
    var draggedBundleID: String = ""
    /// 拖拽上下文：决定 reorder / 建文件夹 / 拖出 等语义
    var context: DragContext = .grid(pageIndex: 0)
    var sourcePageIndex: Int = 0
    var sourceSlotIndex: Int = 0
    var targetSlotIndex: Int = 0
    var dragLocation: CGPoint = .zero
    /// 悬停足够长时间后，准备与之合并的目标 app bundleID（触发文件夹创建，仅网格场景）
    var folderTargetID: String? = nil
    /// 当前正悬停在其上方、准备尝试创建文件夹的目标 app bundleID。
    /// 与 folderTargetID 不同：candidate 在悬停瞬间即确定，用于在进度走满前
    /// 就把进度环画在「真正的目标 app」上；folderTargetID 只在 0.7s 后真正提交。
    var folderCandidateID: String? = nil
    /// 文件夹创建悬停进度（0~1），用于驱动目标图标的环形进度提示
    var folderProgress: Double = 0
    /// 拖拽中悬停在其上方、准备松手归入的已有文件夹 ID（用于拖到文件夹上的高亮反馈）
    var folderHoverID: UUID? = nil

    var isEmpty: Bool { !isDragging }
    var isFolderMode: Bool { folderTargetID != nil }
    /// 是否文件夹内拖拽（用于视图层判断是否走文件夹重排逻辑）
    var isFolderContext: Bool {
        if case .folder = context { return true }
        return false
    }
}
