import SwiftUI

/// 设置页面：外观 + 显示器 + 关于
struct SettingsView: View {
    @Bindable private var prefs = UserPreferences.shared

    var body: some View {
        TabView {
            AppearanceTab(prefs: prefs)
                .tabItem { Label("外观", systemImage: "paintbrush") }

            DisplayTab(prefs: prefs)
                .tabItem { Label("显示器", systemImage: "display") }

            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 300)
    }
}

// MARK: - 外观 Tab

private struct AppearanceTab: View {
    @Bindable var prefs: UserPreferences

    var body: some View {
        Form {
            Section("背景") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("遮罩透明度")
                        Spacer()
                        Text(String(format: "%.0f%%", prefs.backgroundOverlayOpacity * 100))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $prefs.backgroundOverlayOpacity, in: 0...0.8, step: 0.05)
                    Text("较低数值让背景更清晰，较高数值让图标更易辨认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 显示器 Tab

private struct DisplayTab: View {
    @Bindable var prefs: UserPreferences

    var body: some View {
        Form {
            Section("多显示器") {
                Picker("启动台显示位置", selection: $prefs.multiMonitorMode) {
                    ForEach(UserPreferences.MultiMonitorMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 关于 Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            VStack(spacing: 4) {
                Text("AppLaunchpad")
                    .font(.title2.bold())
                Text("版本 0.1.0")
                    .foregroundStyle(.secondary)
            }

            Text("macOS 26 启动台替代应用")
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 6) {
                Text("触控板翻页：待修复（TODO-1）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}
