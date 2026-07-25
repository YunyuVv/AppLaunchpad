import SwiftUI
import AppKit

/// 把 SwiftUI 内容包进 NSGlassEffectView（macOS 26 液态玻璃）。
///
/// 官方要求：液态玻璃必须把内容放进 `contentView`，**不要**把玻璃作为内容的兄弟背景层
/// （否则玻璃的折射/镜面视觉不会作用到你的内容边缘）。本视图即按官方做法，
/// 用 `NSHostingView` 承载 SwiftUI 内容并赋给 `glass.contentView`，
/// AppKit 会用 Auto Layout 把 contentView 约束到玻璃几何内。
///
/// 用法：
/// ```swift
/// GlassHostingView(cornerRadius: 16) {
///     MyContentVStack
/// }
/// .frame(width: panelW, height: panelH)
/// .position(x: cx, y: cy)
/// ```
struct GlassHostingView<Content: View>: NSViewRepresentable {
    var cornerRadius: CGFloat = 16
    var tint: NSColor? = nil
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.tintColor = tint
        glass.style = .regular

        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = hosting
        return glass
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        if let hosting = nsView.contentView as? NSHostingView<Content> {
            hosting.rootView = content()
        }
    }
}
