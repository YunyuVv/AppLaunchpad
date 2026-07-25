import SwiftUI

// MARK: - 外观面板

struct AppearancePane: View {
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

            Section("背景样式") {
                Picker("样式", selection: $prefs.backgroundStyle) {
                    Text("磨砂玻璃").tag(0)
                    Text("液态玻璃").tag(1)
                }
                .pickerStyle(.segmented)
                Text("液态玻璃（macOS 26+）会折射桌面背景；切换即时生效，无需重启启动台")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("网格密度") {
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
                            in: 0...12,
                            step: 1
                        )
                        Text("12 列").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("设为 0 时根据屏幕宽度自动决定")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // 每页行数
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("每页行数")
                        Spacer()
                        Text(prefs.rowCountOverride == 0 ? "自动" : "\(prefs.rowCountOverride) 行")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Text("自动").font(.caption).foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(prefs.rowCountOverride == 0 ? 0 : prefs.rowCountOverride) },
                                set: { prefs.rowCountOverride = $0 < 3 ? 0 : Int($0) }
                            ),
                            in: 0...8,
                            step: 1
                        )
                        Text("8 行").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("设为 0 时根据屏幕高度自动决定")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("图标尺寸") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("图标最大尺寸")
                        Spacer()
                        Text(prefs.iconSizeOverride == 0 ? "自动撑满" : "\(Int(prefs.iconSizeOverride)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Text("自动").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $prefs.iconSizeOverride, in: 0...200, step: 4)
                        Text("200 pt").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("设为 0 时自动撑满网格；调大可在保持撑满的同时限制上限")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("间距与边距") {
                spacingRow(label: "水平间距", value: $prefs.horizontalSpacing, range: 0...60, unit: "pt")
                spacingRow(label: "垂直间距", value: $prefs.verticalSpacing, range: 0...80, unit: "pt")
                spacingRow(label: "左右边距", value: $prefs.sidePadding, range: 0...200, unit: "pt")
                spacingRow(label: "顶部边距", value: $prefs.topPadding, range: 0...200, unit: "pt")
                spacingRow(label: "底部边距", value: $prefs.bottomPadding, range: 0...200, unit: "pt")
            }

            Section {
                Button("恢复默认外观") {
                    prefs.resetAppearanceToDefault()
                }
                .controlSize(.small)
            }

            Section {
                Text("所有调整会实时反映到启动台界面，可边拖动边看效果。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func spacingRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue == 0 ? "自动" : String(format: "%.0f %@", value.wrappedValue, unit))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 2)
        }
    }
}
