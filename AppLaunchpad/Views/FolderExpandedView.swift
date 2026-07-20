import SwiftUI

/// 文件夹展开态：居中弹出，内部图标 4 列，超出时可滚动，顶部可内联编辑名称
struct FolderExpandedView: View {
    let folder: FolderInfo
    let apps: [AppInfo]
    let isEditMode: Bool
    let onTapApp: (AppInfo) -> Void
    let onRemoveApp: (String) -> Void
    let onRename: (String) -> Void

    @State private var isEditingName = false
    @State private var editingName = ""
    @FocusState private var nameFocused: Bool

    private var folderApps: [AppInfo] {
        folder.appIDs.compactMap { id in apps.first { $0.bundleID == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 文件夹名称（可点击内联编辑）
            nameView
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider().opacity(0.3)

            // 内部图标网格（4列，超出时可垂直滚动）
            let cols = Array(repeating: GridItem(.fixed(80), spacing: 20), count: 4)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: cols, spacing: 20) {
                    ForEach(folderApps, id: \.id) { app in
                        AppIconView(
                            app: app,
                            isEditMode: isEditMode,
                            onTap: { onTapApp(app) },
                            onLongPress: {},
                            onDelete: isEditMode ? { onRemoveApp(app.bundleID) } : nil
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(maxHeight: 320)  // 约 3 行，超出滚动
        }
        .frame(width: 500)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    @ViewBuilder
    private var nameView: some View {
        if isEditingName {
            TextField("文件夹名称", text: $editingName)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 220)
                .focused($nameFocused)
                .onSubmit { commitRename() }
                .onExitCommand { commitRename() }
        } else {
            Text(folder.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .onTapGesture {
                    editingName = folder.name
                    isEditingName = true
                    nameFocused = true
                }
        }
    }

    private func commitRename() {
        isEditingName = false
        nameFocused = false
        onRename(editingName)
    }
}
