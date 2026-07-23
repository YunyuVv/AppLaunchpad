import Foundation

/// 网格几何（全局坐标系）。拖拽期间稳定，因为网格容器在拖拽过程中不移动。
///
/// 这是「几何落点」方案的核心：均匀网格下每个 cell 的几何完全确定，
/// 落点直接由光标坐标 `row*cols+col` 推导，无需测量每个 cell 的实时坐标框、
/// 也无需拖拽起手拍快照。从而彻底消除「实时让位 ↔ 快照命中」的反馈振荡
/// 与「最近中心点」在二维网格下的歧义。
struct GridGeometry {
    let origin: CGPoint      // 网格内容区 global 原点（左上角）
    let size: CGSize         // 网格内容区大小
    let columns: Int
    let rows: Int
    let cellW: CGFloat       // 单格宽 = (size.width - hSpacing*(cols-1)) / cols
    let cellH: CGFloat       // 单格高 = (size.height - vSpacing*(rows-1)) / rows
    let hSpacing: CGFloat
    let vSpacing: CGFloat
    let iconSize: CGFloat    // 图标实际方形尺寸，用于 footprint 命中（不含 cell 间隙）

    /// 光标所在槽位索引（0 ..< columns*rows），超出范围按边界 clamp。
    /// 居中边界：cell 间隙的中点归到更近的列 / 行，符合直觉。
    func slotUnderCursor(_ p: CGPoint) -> Int {
        let lx = p.x - origin.x
        let ly = p.y - origin.y
        let strideX = cellW + hSpacing
        let strideY = cellH + vSpacing
        guard strideX > 0, strideY > 0, columns > 0, rows > 0 else { return 0 }
        let rawCol = Int((lx + hSpacing / 2) / strideX)
        let rawRow = Int((ly + vSpacing / 2) / strideY)
        let col = min(max(rawCol, 0), columns - 1)
        let row = min(max(rawRow, 0), rows - 1)
        return row * columns + col
    }

    /// 某槽位对应的「图标 footprint」矩形：cell 中心对齐的 iconSize 方形。
    /// 用于区分「光标压在图标上」与「光标落在 cell 间隙 / 空白处」。
    func iconRect(forSlot slot: Int) -> CGRect {
        guard columns > 0, rows > 0 else { return .zero }
        let col = slot % columns
        let row = slot / columns
        let cx = origin.x + CGFloat(col) * (cellW + hSpacing) + cellW / 2
        let cy = origin.y + CGFloat(row) * (cellH + vSpacing) + cellH / 2
        return CGRect(x: cx - iconSize / 2,
                      y: cy - iconSize / 2,
                      width: iconSize,
                      height: iconSize)
    }
}
