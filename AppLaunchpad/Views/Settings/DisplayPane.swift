import SwiftUI

// MARK: - 显示器面板

struct DisplayPane: View {
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
