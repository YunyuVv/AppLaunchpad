import SwiftUI
import AppKit

/// 单个应用图标：图标图片 + 应用名称，支持 hover/编辑模式/拖拽
struct AppIconView: View {
    let app: AppInfo
    let isEditMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDelete: (() -> Void)?         // 仅 MAS 应用传入

    @State private var icon: NSImage? = nil
    @State private var isHovering: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: { if !isEditMode { onTap() } }) {
                VStack(spacing: 6) {
                    iconImage
                        .frame(width: 80, height: 80)
                        .scaleEffect(isHovering && !isEditMode ? 1.08 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: isHovering)

                    Text(app.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                }
                .frame(width: 100)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .onLongPressGesture(minimumDuration: 0.5) { onLongPress() }
            .wobble(isEditMode)
            .task(id: app.id) {
                icon = await IconCache.shared.icon(for: app)
            }
            .animation(.easeIn(duration: 0.15), value: icon != nil)

            // MAS 应用删除按钮（仅编辑模式显示）
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
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.12))
                .transition(.opacity)
        }
    }
}
