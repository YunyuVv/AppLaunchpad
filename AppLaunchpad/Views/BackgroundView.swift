import SwiftUI
import AppKit

/// 全屏背景：使用 NSVisualEffectView 实时模糊窗口后方的当前屏幕内容
/// 相比读取壁纸文件的优势：
///   1. 显示的是真实的当前屏幕画面（含其他窗口），而不仅是壁纸
///   2. 无需屏幕录制权限
///   3. 硬件加速，性能优于 CIFilter
struct BackgroundView: View {
    // 从 UserPreferences 读取透明度，设置页面修改后实时生效
    private var overlayOpacity: Double { UserPreferences.shared.backgroundOverlayOpacity }

    var body: some View {
        ZStack {
            ScreenBlurView().ignoresSafeArea()
            Color.black.opacity(overlayOpacity).ignoresSafeArea()
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
