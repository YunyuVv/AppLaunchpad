import SwiftUI
import AppKit

// MARK: - 关于面板

struct AboutPane: View {
    /// 作者邮箱（用户反馈联系用）
    private static let contactEmail = "biliww997@gmail.com"

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            // 项目自带的 App 图标（取自 Assets.xcassets/AppIcon）
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)
            } else {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 4) {
                Text("AppLaunchpad")
                    .font(.title3.bold())
                // 仅显示版本号，不显示内部 build 号（避免 "(1)"）
                Text("版本 \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("原生打造的 macOS 启动台：支持拼音搜索、文件夹分组、多显示器同步，以及可精调的液态玻璃外观。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            // 联系方式：mailto: 链接，点击调起默认邮件 App
            Link(destination: URL(string: "mailto:\(Self.contactEmail)")!) {
                HStack(spacing: 6) {
                    Image(systemName: "envelope")
                    Text(Self.contactEmail)
                }
                .font(.callout)
            }
            .help("点击发送邮件反馈")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
