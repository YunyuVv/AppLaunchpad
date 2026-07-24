import SwiftUI

/// 文件夹在网格中的缩略图：3×3 嵌套小图标 + 文件夹名称。
/// 替代原先 GridPageView 中 .folder 的 Color.clear 占位。
struct FolderThumbnailView: View {
    let folder: FolderInfo
    let apps: [AppInfo]
    let iconSize: CGFloat
    let isEditMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDelete: (() -> Void)?
    /// 是否显示文件夹名称（拖拽浮动图标时隐藏，仅显示 3×3 图标网格）
    var showName: Bool = true
    /// 是否显示删除按钮（拖拽浮动图标时隐藏；用显式参数锁死，不依赖 isEditMode 运行时状态）
    var showDeleteButton: Bool = true

    @State private var folderIconImages: [String: NSImage] = [:]

    var body: some View {
        VStack(spacing: 2) {
            // 3×3 图标网格
            folderIconGrid
                .frame(width: iconSize, height: iconSize)

            // 文件夹名称（拖拽浮动图标时隐藏，仅显示 3×3 网格）
            if showName {
                Text(folder.name)
                    .font(.system(size: max(10, iconSize * 0.14)))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: iconSize + 16)
            }
        }
        .onTapGesture { onTap() }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() })
        .overlay(alignment: .topTrailing) {
            if showDeleteButton, isEditMode, let onDelete {
                deleteButton
            }
        }
        .task(id: folder.appIDs) { await loadIcons() }
    }

    // MARK: - Icon Grid

    private var folderIconGrid: some View {
        let gridSize = 3  // 固定 3×3，始终占满 9 格
        let outerPad: CGFloat = 6
        let cellSpacing: CGFloat = 2
        let thumbnailSize = (iconSize - 2 * outerPad - CGFloat(gridSize - 1) * cellSpacing) / CGFloat(gridSize)

        return ZStack {
            RoundedRectangle(cornerRadius: iconSize * 0.22)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: iconSize * 0.22)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )

            VStack(spacing: cellSpacing) {
                ForEach(0..<gridSize, id: \.self) { row in
                    HStack(spacing: cellSpacing) {
                        ForEach(0..<gridSize, id: \.self) { col in
                            let idx = row * gridSize + col
                            if idx < folder.appIDs.count {
                                iconView(for: folder.appIDs[idx],
                                         size: max(16, thumbnailSize))
                            } else {
                                Color.clear.frame(width: max(16, thumbnailSize),
                                                  height: max(16, thumbnailSize))
                            }
                        }
                    }
                }
            }
            .padding(outerPad)
        }
    }

    private func iconView(for bundleID: String, size: CGFloat) -> some View {
        Group {
            if let image = folderIconImages[bundleID] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                ProgressView()
                    .scaleEffect(0.3)
                    .frame(width: size, height: size)
            }
        }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button { onDelete?() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: iconSize * 0.25))
                .foregroundStyle(.white, .red)
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
    }

    // MARK: - Icon Loading

    private func loadIcons() async {
        let maxIcons = min(9, folder.appIDs.count)
        let ids = Array(folder.appIDs.prefix(maxIcons))
        for id in ids {
            guard folderIconImages[id] == nil,
                  let app = apps.first(where: { $0.bundleID == id }) else { continue }
            let icon = await IconCache.shared.icon(for: app)
            folderIconImages[id] = icon
        }
    }
}
