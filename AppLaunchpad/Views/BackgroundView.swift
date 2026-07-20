import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// 虚化壁纸背景；壁纸读取失败时降级为系统 NSVisualEffectView
struct BackgroundView: View {
    @State private var blurredWallpaper: NSImage? = nil

    var body: some View {
        ZStack {
            if let img = blurredWallpaper {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                VisualEffectView()
                    .ignoresSafeArea()
            }
            Color.black.opacity(0.35)
                .ignoresSafeArea()
        }
        .task {
            blurredWallpaper = await makeBlurredWallpaper()
        }
    }

    private func makeBlurredWallpaper() async -> NSImage? {
        guard
            let screen = NSScreen.main,
            let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen),
            let ciImage = CIImage(contentsOf: wallpaperURL)
        else { return nil }

        return await Task.detached(priority: .utility) {
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ciImage
            filter.radius = 20
            guard let output = filter.outputImage else { return nil }
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(output, from: ciImage.extent) else { return nil }
            return NSImage(cgImage: cg, size: screen.frame.size)
        }.value
    }
}

/// NSVisualEffectView 包装，作为背景降级方案
private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
