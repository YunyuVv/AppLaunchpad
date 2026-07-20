import SwiftUI
import AppKit

/// 文件夹收起态：圆角矩形背景 + 最多 9 个小图标（3×3）+ 文件夹名称
struct FolderThumbnailView: View {
    let folder: FolderInfo
    let apps: [AppInfo]
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
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 80, height: 80)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(22), spacing: 3), count: 3),
                    spacing: 3
                ) {
                    ForEach(gridApps, id: \.id) { app in
                        if let icon = icons[app.bundleID] {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 22, height: 22)
                        }
                    }
                }
                .padding(9)
                .frame(width: 80, height: 80)
            }
            .wobble(isEditMode)

            Text(folder.name)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
        }
        .frame(width: 100)
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
