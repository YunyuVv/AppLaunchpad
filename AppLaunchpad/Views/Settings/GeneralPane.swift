import SwiftUI

// MARK: - 通用面板（外观模式 / 开机启动 / 显示器）

struct GeneralPane: View {
    @Bindable var prefs: UserPreferences

    /// 当前连接的显示器（实时）
    private var screens: [NSScreen] { NSScreen.screens }

    var body: some View {
        Form {
            Section("外观") {
                HStack(alignment: .top, spacing: 12) {
                    appearanceCard(mode: .auto,  label: "自动", style: .auto)
                    appearanceCard(mode: .light, label: "浅色", style: .light)
                    appearanceCard(mode: .dark,  label: "深色", style: .dark)
                }
                .frame(maxWidth: .infinity)
                Text("「自动」跟随系统外观；选择「浅色」或「深色」会立即切换全 App 的外观，文字配色随之变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("开机启动") {
                Toggle(isOn: $prefs.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开机静默启动")
                            .font(.callout)
                        Text("启动电脑后 App 自动在后台运行，不弹出启动台或设置窗口")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.regular)
            }

            Section("显示器") {
                if screens.count <= 1 {
                    // 仅一块显示器：无需选择，固定主显示器
                    LabeledContent("启动台显示于", value: "主显示器")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("启动台显示于", selection: $prefs.displayTarget) {
                        Text("主显示器").tag(UserPreferences.DisplayTarget.primary)
                        Text("鼠标所在显示器").tag(UserPreferences.DisplayTarget.mouse)
                        ForEach(screens, id: \.self) { screen in
                            if let id = UserPreferences.displayID(for: screen) {
                                Text(UserPreferences.screenLabel(screen))
                                    .tag(UserPreferences.DisplayTarget.specific(id))
                            }
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Text("可指定启动台固定在某块显示器上展示；仅有一块显示器时无需选择，默认主显示器。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    // MARK: - 外观三卡片选择器

    @ViewBuilder
    private func appearanceCard(mode: UserPreferences.AppearanceMode,
                                label: String,
                                style: AppearanceThumbnail.Style) -> some View {
        let isSelected = prefs.appearanceMode == mode
        Button {
            prefs.appearanceMode = mode
        } label: {
            VStack(spacing: 6) {
                AppearanceThumbnail(style: style)
                    .frame(width: 100, height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 外观缩略图（macOS 设置风格：左半浅 + 右半深 = 自动）

private struct AppearanceThumbnail: View {
    enum Style { case auto, light, dark }

    let style: Style

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.36)).frame(width: 4, height: 4)
                    Circle().fill(Color(red: 1.0, green: 0.78, blue: 0.20)).frame(width: 4, height: 4)
                    Circle().fill(Color(red: 0.28, green: 0.83, blue: 0.36)).frame(width: 4, height: 4)
                }
                Spacer().frame(height: 2)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(contentBar)
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(contentBar.opacity(0.6))
                    .frame(height: 4)
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .auto:
            // 左浅 + 右深，对应"自动（跟随系统）"在浅/深系统下的两种状态并置
            HStack(spacing: 0) {
                Rectangle()
                    .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.78)],
                                         startPoint: .top, endPoint: .bottom))
                Rectangle()
                    .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.10)],
                                         startPoint: .top, endPoint: .bottom))
            }
        case .light:
            Rectangle()
                .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.78)],
                                     startPoint: .top, endPoint: .bottom))
        case .dark:
            Rectangle()
                .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
        }
    }

    /// 内容条颜色：深色背景上偏白、浅色背景上偏深，保证始终可读
    private var contentBar: Color {
        switch style {
        case .auto:  return .white   // 整体偏深（以右半主导），用白色
        case .light: return .black.opacity(0.55)
        case .dark:  return .white
        }
    }
}
