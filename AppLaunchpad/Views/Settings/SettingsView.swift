import SwiftUI

// MARK: - 菜单项枚举

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance = "外观"
    case display    = "显示器"
    case about      = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .display:    return "display"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - 设置主视图（左右结构）

/// 左侧菜单 + 右侧内容的双栏设置页面
struct SettingsView: View {
    @State private var selected: SettingsSection = .appearance
    @Bindable private var prefs = UserPreferences.shared

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧菜单栏
            sidebar

            Divider()

            // ── 右侧内容区
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 左侧菜单

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                sidebarItem(section)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 140)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: section.icon)
                .font(.system(size: 14))
                .frame(width: 20)
                .foregroundStyle(selected == section ? .white : .secondary)
            Text(section.rawValue)
                .font(.system(size: 13))
                .foregroundStyle(selected == section ? .white : .primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected == section ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selected = section } }
    }

    // MARK: - 右侧内容

    @ViewBuilder
    private var contentArea: some View {
        switch selected {
        case .appearance:
            AppearancePane(prefs: prefs)
        case .display:
            DisplayPane(prefs: prefs)
        case .about:
            AboutPane()
        }
    }
}

// MARK: - 外观

private struct AppearancePane: View {
    @Bindable var prefs: UserPreferences

    var body: some View {
        Form {
            Section("背景遮罩") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("透明度")
                        Spacer()
                        Text(String(format: "%.0f%%", prefs.backgroundOverlayOpacity * 100))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Slider(value: $prefs.backgroundOverlayOpacity, in: 0...0.8, step: 0.05)
                    Text("数值越低背景越清晰，越高图标越易辨认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("图标网格") {
                // 每行列数
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("每行列数")
                        Spacer()
                        Text(prefs.columnCountOverride == 0 ? "自动" : "\(prefs.columnCountOverride) 列")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Text("自动").font(.caption).foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(prefs.columnCountOverride == 0 ? 0 : prefs.columnCountOverride) },
                                set: { prefs.columnCountOverride = $0 < 3 ? 0 : Int($0) }
                            ),
                            in: 0...9,
                            step: 1
                        )
                        Text("9 列").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("设为 0 时根据屏幕宽度自动决定（推荐）")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // 图标尺寸
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("图标大小")
                        Spacer()
                        Text(prefs.iconSizeOverride == 0 ? "默认 (80pt)" : "\(Int(prefs.iconSizeOverride)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { prefs.iconSizeOverride == 0 ? 80 : prefs.iconSizeOverride },
                            set: { prefs.iconSizeOverride = abs($0 - 80) < 3 ? 0 : $0 }
                        ),
                        in: 56...120,
                        step: 4
                    )
                    Text("拖到 80pt 附近自动吸附到默认值")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - 显示器

private struct DisplayPane: View {
    @Bindable var prefs: UserPreferences

    var body: some View {
        Form {
            Section("多显示器") {
                Picker("启动台位置", selection: $prefs.multiMonitorMode) {
                    ForEach(UserPreferences.MultiMonitorMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - 关于

private struct AboutPane: View {
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
