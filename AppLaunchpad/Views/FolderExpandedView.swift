import SwiftUI

/// 文件夹展开态：居中弹出，内部图标 4 列、从左上角起排列，超出时可滚动。
/// 支持：点击 app 打开、编辑模式下移除 app、把 app 拖出文件夹（落到网格重排）、
/// 文件夹内拖拽重排（与启动台网格同款手感，复用 DragState）。
struct FolderExpandedView: View {
    let folder: FolderInfo
    let apps: [AppInfo]
    let isEditMode: Bool
    let viewModel: LaunchpadViewModel
    let onTapApp: (AppInfo) -> Void
    let onRemoveApp: (String) -> Void
    let onRename: (String) -> Void
    /// 拖拽结束回调：droppedOutside 表示落在文件夹浮层之外（应移出到网格）。
    /// 同时负责在 LaunchpadView 层刷新/关闭展开视图并重置 dragState。
    let onAppDragEnded: (AppInfo, Bool, CGPoint) -> Void

    @State private var isEditingName = false
    @State private var editingName = ""
    @FocusState private var nameFocused: Bool
    @State private var folderGlobalFrame: CGRect = .zero
    /// 文件夹内每个 app cell 的全局坐标框，用于拖拽时命中最近槽位（与 GridPageView 同思路）
    @State private var slotFrames: [Int: CGRect] = [:]

    /// 实时排序后的 app 列表：优先读 viewModel（拖拽提交后立即反映新顺序），
    /// 否则退回传入的 folder 快照。
    private var orderedApps: [AppInfo] {
        let ids = viewModel.layout.folders[folder.id]?.appIDs ?? folder.appIDs
        return ids.compactMap { id in apps.first { $0.bundleID == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 文件夹名称（点击或点笔形按钮可内联编辑）
            nameView
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider().opacity(0.3)

            // 内部图标网格（4列，从左上角起排列，超出时可垂直滚动）
            let cols = Array(repeating: GridItem(.fixed(80), spacing: 20), count: 4)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 20) {
                    ForEach(Array(orderedApps.enumerated()), id: \.element.id) { idx, app in
                        appCell(app, index: idx)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(maxHeight: 320)  // 约 3 行，超出滚动
        }
        .frame(width: 500)
        .background(
            // 捕获文件夹浮层自身的全局坐标框，用于判断拖拽落点是否在浮层外
            GeometryReader { geo in
                Color.clear.preference(key: FolderFrameKey.self, value: geo.frame(in: .global))
            }
        )
        .onPreferenceChange(FolderFrameKey.self) { folderGlobalFrame = $0 }
        // 收集文件夹内各 cell 的全局坐标，供拖拽命中最近槽位
        .onPreferenceChange(FolderSlotFrameKey.self) { newFrames in
            if newFrames != slotFrames { slotFrames = newFrames }
        }
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
        HStack(spacing: 8) {
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
                        beginRename()
                    }
                // 笔形按钮：让「重命名」更可发现
                Button(action: { beginRename() }) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("重命名文件夹")
            }
        }
    }

    @ViewBuilder
    private func appCell(_ app: AppInfo, index: Int) -> some View {
        let isDragged = viewModel.dragState.isDragging
            && viewModel.dragState.draggedBundleID == app.bundleID
        let isTarget = viewModel.dragState.isDragging
            && viewModel.dragState.isFolderContext
            && viewModel.dragState.targetSlotIndex == index

        AppIconView(
            app: app,
            iconSize: 72,   // 文件夹内图标固定稍小，保持4列整洁
            isEditMode: isEditMode,
            onTap: { onTapApp(app) },
            onLongPress: {},
            onDelete: isEditMode ? { onRemoveApp(app.bundleID) } : nil
        )
        .opacity(isDragged ? 0.2 : 1.0)
        .scaleEffect(isTarget ? 1.12 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 72 * 0.22)
                .strokeBorder(Color.white.opacity(isTarget ? 0.85 : 0), lineWidth: 2)
                .frame(width: 72 + 8, height: 72 + 8)
                .allowsHitTesting(false)
        )
        // 与启动台网格同款：常驻高优先级拖拽手势，minDistance 5 起手即拖
        .highPriorityGesture(folderDragGesture(app: app, index: index))
        .background(slotFrameTracker(index: index))
    }

    // MARK: - 文件夹内拖拽手势（与 GridPageView.cellDragGesture 同思路）

    private func folderDragGesture(app: AppInfo, index: Int) -> some Gesture {
        var hasBegunDrag = false
        return DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                if !hasBegunDrag {
                    hasBegunDrag = true
                    viewModel.beginFolderDrag(
                        bundleID: app.bundleID,
                        folderID: folder.id,
                        slotIndex: index,
                        location: value.startLocation
                    )
                }
                if let nearest = nearestSlot(to: value.location) {
                    viewModel.updateFolderDragTarget(
                        folderID: folder.id,
                        targetIndex: nearest,
                        location: value.location
                    )
                }
            }
            .onEnded { value in
                let outside = !folderGlobalFrame.contains(value.location)
                if outside {
                    onAppDragEnded(app, true, value.location)
                } else {
                    viewModel.commitFolderReorder(folderID: folder.id)
                    onAppDragEnded(app, false, value.location)
                }
            }
    }

    private func slotFrameTracker(index: Int) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: FolderSlotFrameKey.self,
                value: [index: geo.frame(in: .global)]
            )
        }
    }

    private func nearestSlot(to point: CGPoint) -> Int? {
        slotFrames.min { a, b in
            hypot(a.value.midX - point.x, a.value.midY - point.y) <
            hypot(b.value.midX - point.x, b.value.midY - point.y)
        }?.key
    }

    private func beginRename() {
        editingName = folder.name
        isEditingName = true
        nameFocused = true
    }

    private func commitRename() {
        isEditingName = false
        nameFocused = false
        onRename(editingName)
    }
}

private struct FolderFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// 文件夹内各 app cell 的全局坐标框（key = 在 orderedApps 中的索引）
private struct FolderSlotFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
