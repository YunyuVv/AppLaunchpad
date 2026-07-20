import SwiftUI
import AppKit

/// 单个应用图标：图标图片 + 应用名称，支持 hover 放大和点击启动
struct AppIconView: View {
    let app: AppInfo
    let onTap: () -> Void

    @State private var icon: NSImage? = nil
    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                iconImage
                    .frame(width: 80, height: 80)
                    .scaleEffect(isHovering ? 1.08 : 1.0)
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
        .task(id: app.id) {
            // task(id:) 确保切页时为新 app 重新加载图标
            icon = await IconCache.shared.icon(for: app)
        }
        .animation(.easeIn(duration: 0.15), value: icon != nil)
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
