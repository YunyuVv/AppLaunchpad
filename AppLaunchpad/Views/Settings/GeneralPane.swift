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
                    appearanceCard(mode: .auto,  label: "自动", imageName: "AppearanceAuto")
                    appearanceCard(mode: .light, label: "浅色", imageName: "AppearanceLight")
                    appearanceCard(mode: .dark,  label: "深色", imageName: "AppearanceDark")
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

    // MARK: - 外观三卡片选择器（图片资源版，与 LaunchNext HEIC 卡片视觉风格一致）

    @ViewBuilder
    private func appearanceCard(mode: UserPreferences.AppearanceMode,
                                label: String,
                                imageName: String) -> some View {
        let isSelected = prefs.appearanceMode == mode
        Button {
            prefs.appearanceMode = mode
        } label: {
            VStack(spacing: 6) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 73)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                lineWidth: isSelected ? 3 : 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
