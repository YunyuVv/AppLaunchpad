import SwiftUI
import AppKit

/// 单个应用图标：图标图片 + 应用名称，支持 hover/编辑模式/拖拽
struct AppIconView: View {
    let app: AppInfo
    let iconSize: CGFloat        // 由父级传入，不在此处观察 UserPreferences（避免36个视图同时触发重渲染）
    let isEditMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    /// 删除回调（可选）。启动台网格不传（不显示 X）；文件夹展开视图传入以移除文件夹内 app。
    let onDelete: (() -> Void)?

    @State private var icon: NSImage?
    @State private var isHovering: Bool = false
    @State private var isPressed: Bool = false

    // 自定义 init：构造时同步从缓存取图标（翻页重建时命中缓存，避免灰色占位闪烁）。
    // 注意：@State 初值不能在属性初始值里引用 app，必须在 init 中用 _icon = State(initialValue:) 设置。
    init(app: AppInfo, iconSize: CGFloat, isEditMode: Bool,
         onTap: @escaping () -> Void, onLongPress: @escaping () -> Void,
         onDelete: (() -> Void)? = nil) {
        self.app = app
        self.iconSize = iconSize
        self.isEditMode = isEditMode
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onDelete = onDelete
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
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
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

            // 删除按钮（仅当传入 onDelete 时显示，例如文件夹展开视图移除 app）
            if isEditMode, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.7))
                        .font(.system(size: max(16, iconSize * 0.22)))
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: isEditMode)
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
