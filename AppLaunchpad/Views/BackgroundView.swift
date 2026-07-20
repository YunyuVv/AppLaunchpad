import SwiftUI
import AppKit

/// 全屏背景：使用 NSVisualEffectView 实时模糊窗口后方的当前屏幕内容
/// 相比读取壁纸文件的优势：
///   1. 显示的是真实的当前屏幕画面（含其他窗口），而不仅是壁纸
///   2. 无需屏幕录制权限
///   3. 硬件加速，性能优于 CIFilter
struct BackgroundView: View {
    var body: some View {
        ZStack {
            // 系统级实时模糊：自动合成窗口后方的当前画面
            ScreenBlurView()
                .ignoresSafeArea()

            // 深色半透明遮罩，提升图标和文字的可读性
            Color.black.opacity(0.45)
                .ignoresSafeArea()
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
