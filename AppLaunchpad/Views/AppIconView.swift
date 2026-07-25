import SwiftUI
import AppKit

/// 单个应用图标：图标图片 + 应用名称，支持 hover/编辑模式/拖拽
struct AppIconView: View {
    let app: AppInfo
    let iconSize: CGFloat        // 由父级传入，不在此处观察 UserPreferences（避免36个视图同时触发重渲染）
    let isEditMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    /// 右键菜单「删除」回调：触发后把 .app 移入废纸篓（与原生「卸载」一致）。
    /// 主网格传入（viewModel.deleteApp）；文件夹内部 app 等场景传 nil，则不显示「删除」。
    let onDeleteApp: (() -> Void)?

    @State private var icon: NSImage?
    @State private var isHovering: Bool = false
    @State private var isPressed: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    // 自定义 init：构造时同步从缓存取图标（翻页重建时命中缓存，避免灰色占位闪烁）。
    // 注意：@State 初值不能在属性初始值里引用 app，必须在 init 中用 _icon = State(initialValue:) 设置。
    init(app: AppInfo, iconSize: CGFloat, isEditMode: Bool,
         onTap: @escaping () -> Void, onLongPress: @escaping () -> Void,
         onDeleteApp: (() -> Void)? = nil) {
        self.app = app
        self.iconSize = iconSize
        self.isEditMode = isEditMode
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onDeleteApp = onDeleteApp
        _icon = State(initialValue: IconCache.cachedIcon(for: app))
    }

    private var cellWidth: CGFloat { iconSize + 20 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: { if !isEditMode { onTap() } }) {
                VStack(spacing: 6) {
                    iconImage
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(isPressed ? 0.92 : (isHovering && !isEditMode ? 1.08 : 1.0))
                        .animation(.easeOut(duration: 0.1), value: isPressed)
                        .animation(.easeOut(duration: 0.12), value: isHovering)

                    Text(app.displayName)
                        .font(.system(size: min(max(10, iconSize * 0.14), 16)))  // 字体随图标比例缩放，最高 16pt
                        // 浅色外观用黑字+白阴影；深色外观用白字+黑阴影 —— 跟随系统颜色方案自适应
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .shadow(color: colorScheme == .dark ? .black.opacity(0.6) : .white.opacity(0.6),
                                radius: 2, x: 0, y: 1)
                }
                .frame(width: cellWidth)
                .opacity(isPressed && !isEditMode ? 0.8 : 1.0)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { isHovering = $0 }
            // 用长按手势的按压态驱动按压缩放，避免额外的 DragGesture(minimumDistance:0)
            // 与 onLongPressGesture 抢识别（那是之前长按进编辑模式不稳定的根因）。
            // 用 pressing && !isEditMode 防止长按触发 enterEditMode 后图标卡在缩小态。
            .onLongPressGesture(
                minimumDuration: 0.5,
                maximumDistance: 100,
                perform: { onLongPress() },
                onPressingChanged: { pressing in
                    isPressed = pressing && !isEditMode
                }
            )
            .task(id: app.id) {
                icon = await IconCache.shared.icon(for: app)
            }
            .animation(.easeIn(duration: 0.15), value: icon != nil)
            .animation(.spring(duration: 0.2), value: isEditMode)
        }
        .animation(.spring(duration: 0.2), value: isEditMode)
        // 右键菜单：打开 / 在访达中显示 / 删除（删除动作与原生一致，把 .app 移入废纸篓）。
        // secondary click 由 .contextMenu 识别，与 primary 长按进编辑模式互不冲突。
        .contextMenu {
            Button {
                NSWorkspace.shared.open(app.url)
            } label: {
                Label("打开", systemImage: "arrow.up.right.square")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Label("在访达中显示", systemImage: "folder")
            }
            // 系统受保护 app（/System 下）无法卸载，不显示「删除」，与原生一致。
            if !app.url.path.hasPrefix("/System/") {
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        // 二次确认：点「删除」后弹窗，确认才真正把 .app 移入废纸篓（动作仍与原生一致）。
        .confirmationDialog(
            "确定把“\(app.displayName)”移到废纸篓？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) {
                onDeleteApp?()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会将应用移入废纸篓，可在废纸篓中恢复。")
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .transition(.opacity)
        } else {
            RoundedRectangle(cornerRadius: iconSize * 0.2)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: iconSize * 0.2)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .transition(.opacity)
        }
    }
}
