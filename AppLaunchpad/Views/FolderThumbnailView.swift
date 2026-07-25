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

    // 自定义 init：同步预填缓存命中的文件夹图标，避免每次进屏（含翻页时相邻页挂载）
    // 先闪 ProgressView 再异步加载的闪烁。与 AppIconView 的 IconCache.cachedIcon 同步兜底同思路。
    init(folder: FolderInfo, apps: [AppInfo], iconSize: CGFloat, isEditMode: Bool, isSelected: Bool,
         onTap: @escaping () -> Void, onLongPress: @escaping () -> Void, onDelete: (() -> Void)?,
         showName: Bool = true, showDeleteButton: Bool = true) {
        self.folder = folder
        self.apps = apps
        self.iconSize = iconSize
        self.isEditMode = isEditMode
        self.isSelected = isSelected
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self.showName = showName
        self.showDeleteButton = showDeleteButton
        var initial: [String: NSImage] = [:]
        for id in folder.appIDs.prefix(9) {
            if let app = apps.first(where: { $0.bundleID == id }),
               let img = IconCache.cachedIcon(for: app) {
                initial[id] = img
            }
        }
        _folderIconImages = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 2) {
            // 3×3 图标网格
            folderIconGrid
                .frame(width: iconSize, height: iconSize)

            // 文件夹名称（拖拽浮动图标时隐藏，仅显示 3×3 网格）
            if showName {
                Text(folder.name)
                    .font(.system(size: min(max(10, iconSize * 0.14), 16)))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    // 与普通 app 对齐：白字 + 黑色阴影确保浅色玻璃背景下仍清晰可读
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .frame(width: iconSize + 20)
            }
        }
        .onTapGesture { onTap() }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() })
        .overlay(alignment: .topTrailing) {
            if showDeleteButton, isEditMode, onDelete != nil {
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
            // 同步兜底：优先取缓存（未命中会同步取系统图标并回填），避免异步加载期间闪 ProgressView；
            // 极罕见缓存仍为空时再异步取一次。
            let icon: NSImage
            if let cached = IconCache.cachedIcon(for: app) {
                icon = cached
            } else {
                icon = await IconCache.shared.icon(for: app)
            }
            folderIconImages[id] = icon
        }
    }
}
