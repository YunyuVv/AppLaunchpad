import SwiftUI
import AppKit

/// 文件夹收起态：圆角矩形背景 + 最多 9 个小图标（3×3）+ 文件夹名称
struct FolderThumbnailView: View {
    let folder: FolderInfo
    let apps: [AppInfo]
    let iconSize: CGFloat        // 由父级传入
    let isEditMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var icons: [String: NSImage] = [:]

    private var gridApps: [AppInfo] {
        Array(folder.appIDs.prefix(9).compactMap { id in
            apps.first { $0.bundleID == id }
        })
    }

    var body: some View {
        let smallIconSize = iconSize * 0.26   // 文件夹内小图标约为主图标的 26%
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.22)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: iconSize, height: iconSize)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(smallIconSize), spacing: 3), count: 3),
                    spacing: 3
                ) {
                    ForEach(gridApps, id: \.id) { app in
                        if let icon = icons[app.bundleID] {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: smallIconSize, height: smallIconSize)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.15))
                                .frame(width: smallIconSize, height: smallIconSize)
                        }
                    }
                }
                .padding(iconSize * 0.11)
                .frame(width: iconSize, height: iconSize)
            }
            .wobble(isEditMode)

            Text(folder.name)
                .font(.system(size: max(10, iconSize * 0.14)))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
        }
        .frame(width: iconSize + 20)
        .onTapGesture { if !isEditMode { onTap() } }
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 100) { onLongPress() }
        .task(id: folder.id) {
            for app in gridApps {
                let icon = await IconCache.shared.icon(for: app)
                icons[app.bundleID] = icon
            }
        }
    }
}
