import SwiftUI

// MARK: - 通用面板（开机启动 / 显示器）

struct GeneralPane: View {
    @Bindable var prefs: UserPreferences

    /// 当前连接的显示器（实时）
    private var screens: [NSScreen] { NSScreen.screens }

    var body: some View {
        Form {
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
}
