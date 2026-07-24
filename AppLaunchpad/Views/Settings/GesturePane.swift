import SwiftUI

// MARK: - 手势面板

struct GesturePane: View {
    @Bindable var prefs: UserPreferences

    var body: some View {
        Form {
            Section("触控板翻页") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("跟手灵敏度")
                        Spacer()
                        Text(String(format: "%.1fx", prefs.trackpadPagingGain))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $prefs.trackpadPagingGain, in: 1...8, step: 0.5)
                    Text("数值越大，手指少滑一点就能跟满整页，越省力；1x 为 1:1 跟手（最自然但最费手指）。觉得翻页累可往大调。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("更改即时生效，无需重启。翻页方向（左滑看下一页）与灵敏度相互独立。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
