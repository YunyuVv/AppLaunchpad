import SwiftUI

// MARK: - 外观面板

struct AppearancePane: View {
    @Bindable var prefs: UserPreferences

    @State private var dbAvailable = false
    @State private var importMessage = ""
    @State private var showingImportConfirm = false
    @State private var showingRestoreConfirm = false

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

            Section("布局") {
                // 两个互斥胶囊开关：开哪个就用哪个布局来源。
                // 互斥逻辑在 set 闭包里手动维持：开 A 必弹"导入"确认；开 B 必弹"恢复默认"确认；取消/失败时还原。

                Toggle("使用原生 macOS 启动台布局", isOn: Binding(
                    get: { prefs.useNativeLayout },
                    set: { on in
                        // 用户想开 A → 走导入确认；想关 A → 互斥自动开 B → 走恢复默认确认
                        if on { showingImportConfirm = true }
                        else  { showingRestoreConfirm = true }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.large)
                .disabled(!dbAvailable)
                .help(dbAvailable
                      ? "开启后用系统启动台数据库的顺序与文件夹覆盖当前布局（自动备份）"
                      : "当前系统未找到可用的启动台数据库，无法启用")

                Toggle("使用本项目默认布局", isOn: Binding(
                    get: { !prefs.useNativeLayout },
                    set: { on in
                        // 用户想开 B → 走恢复默认确认；想关 B → 互斥自动开 A → 走导入确认
                        if on { showingRestoreConfirm = true }
                        else  { showingImportConfirm = true }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.large)
                .help("开启后按本机已安装 App 顺序重新铺满布局（自动备份当前布局）")

                if !importMessage.isEmpty {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .task { dbAvailable = NativeLaunchpadImporter.hasImportableDatabase() }
        .alert("导入系统启动台布局", isPresented: $showingImportConfirm) {
            Button("取消", role: .cancel) {}
            Button("导入并覆盖") { Task { await runImport() } }
        } message: {
            Text("导入将用系统启动台的顺序与文件夹覆盖当前布局。导入前会自动备份当前布局，可随时还原。")
        }
        .alert("恢复默认布局", isPresented: $showingRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复") { Task { await runRestore() } }
        } message: {
            Text("将按本机已安装 App 重新生成默认布局并覆盖当前布局。操作前会自动备份当前布局。")
        }
    }

    // MARK: - 导入 / 恢复（经 AppContext.viewModel → LayoutService）

    private func runImport() async {
        guard let vm = AppContext.viewModel else {
            importMessage = "内部错误：启动台尚未就绪"
            return
        }
        let result = await vm.importNativeLayout()
        switch result {
        case .success(let apps, let folders, let skipped, let appended):
            prefs.useNativeLayout = true
            var msg = "已导入 \(apps) 个 App、\(folders) 个文件夹"
            if skipped > 0 { msg += "，跳过 \(skipped) 个未安装" }
            if appended > 0 { msg += "，追加 \(appended) 个本机已装但启动台未收录的 App" }
            importMessage = msg + "。"
        case .noDatabase:
            importMessage = "未找到系统启动台数据库，无法导入。"
        case .parseError(let msg):
            importMessage = "导入失败：\(msg)"
        }
    }

    private func runRestore() async {
        guard let vm = AppContext.viewModel else {
            importMessage = "内部错误：启动台尚未就绪"
            return
        }
        let result = await vm.restoreDefaultLayout()
        switch result {
        case .success(let apps, _, _, _):
            prefs.useNativeLayout = false
            importMessage = "已恢复默认布局（\(apps) 个 App）。"
        case .noDatabase:
            importMessage = "无法恢复：尚未扫描到任何 App。"
        case .parseError(let msg):
            importMessage = "恢复失败：\(msg)"
        }
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
