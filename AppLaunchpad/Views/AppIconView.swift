import SwiftUI
import AppKit

/// 单个应用图标：图标图片 + 应用名称，支持 hover/编辑模式/拖拽
struct AppIconView: View {
    let app: AppInfo
    let isEditMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDelete: (() -> Void)?

    @State private var icon: NSImage? = nil
    @State private var isHovering: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: { if !isEditMode { onTap() } }) {
                VStack(spacing: 6) {
                    iconImage
                        .frame(width: 80, height: 80)
                        // hover 放大，点击按下缩小，双重反馈更自然
                        .scaleEffect(isPressed ? 0.92 : (isHovering && !isEditMode ? 1.08 : 1.0))
                        .animation(.easeOut(duration: 0.1), value: isPressed)
                        .animation(.easeOut(duration: 0.12), value: isHovering)

                    Text(app.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                }
                .frame(width: 100)
                // 点击按下状态
                .opacity(isPressed && !isEditMode ? 0.8 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isEditMode { isPressed = true } }
                    .onEnded { _ in isPressed = false }
            )
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 100) { onLongPress() }
            .wobble(isEditMode)
            .task(id: app.id) {
                icon = await IconCache.shared.icon(for: app)
            }
            .animation(.easeIn(duration: 0.15), value: icon != nil)

            // MAS 应用删除按钮
            if isEditMode, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.7))
                        .font(.system(size: 20))
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
            // 占位：更柔和的灰色，避免纯白闪烁感
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .transition(.opacity)
        }
    }
}
