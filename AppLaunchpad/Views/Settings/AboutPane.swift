import SwiftUI

// MARK: - 关于面板

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            VStack(spacing: 4) {
                Text("AppLaunchpad")
                    .font(.title3.bold())
                Text("版本 \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("macOS 26 启动台替代应用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
