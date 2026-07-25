import SwiftUI
import AppKit

/// 全屏背景：使用 NSVisualEffectView 实时模糊窗口后方的当前屏幕内容
/// 相比读取壁纸文件的优势：
///   1. 显示的是真实的当前屏幕画面（含其他窗口），而不仅是壁纸
///   2. 无需屏幕录制权限
///   3. 硬件加速，性能优于 CIFilter
struct BackgroundView: View {
    // 用 @State 持有引用，建立对 @Observable UserPreferences 的追踪依赖
    @State private var prefs = UserPreferences.shared

    var body: some View {
        ZStack {
            if prefs.backgroundStyle == 1 {
                // 液态玻璃：全屏 NSGlassEffectView，自身折射窗口后方桌面，无需叠黑遮罩
                // （黑遮罩叠在玻璃上会发灰、吃掉折射感，故玻璃模式不叠）。
                GlassBlurView().ignoresSafeArea()
            } else {
                // 磨砂玻璃（当前默认）：实时模糊窗口后方内容 + 半透明黑遮罩压暗以提升可读性
                ScreenBlurView().ignoresSafeArea()
                Color.black.opacity(prefs.backgroundOverlayOpacity).ignoresSafeArea()
            }
        }
    }
}

/// 封装 NSVisualEffectView，behindWindow 模式显示窗口背后的实时模糊内容
private struct ScreenBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI   // 专为全屏界面设计的材质
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 封装 NSGlassEffectView（macOS 26 液态玻璃），全屏无圆角、跟随系统环境折射桌面。
/// 用于「背景样式 = 液态玻璃」模式。面板本身是 borderless + backgroundColor = .clear，
/// 玻璃能采样窗口后方桌面内容。
private struct GlassBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = 0           // 全屏无圆角
        glass.tintColor = nil            // 跟随系统环境
        glass.style = .regular           // 常规折射玻璃
        return glass
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
}
