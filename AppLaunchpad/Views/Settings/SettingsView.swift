import SwiftUI
import AppKit
import ApplicationServices

// MARK: - 设置分类

enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case appearance = "外观"
    case display    = "显示器"
    case hotkey     = "快捷键"
    case about      = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .display:    return "display"
        case .hotkey:     return "command"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - 原生设置窗口（⌘, / App 菜单 Settings... 打开）
// 使用 NavigationSplitView，由 SwiftUI Settings 场景托管窗口，
// 系统会自动生成标题栏、工具栏和 sidebar toggle 按钮。

struct SettingsView: View {
    var body: some View {
        SettingsNavigationContent()
            .frame(minWidth: 820, idealWidth: 900, minHeight: 600, idealHeight: 650)
    }
}

struct SettingsNavigationContent: View {
    @Bindable private var prefs = UserPreferences.shared
    @State private var selected: SettingsSection? = .appearance
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationTitle("设置")
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detailPane
                .navigationTitle(navigationTitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var navigationTitle: String {
        selected?.rawValue ?? "设置"
    }

    private var sidebar: some View {
        List(selection: $selected) {
            Section("常规") {
                Label("外观", systemImage: SettingsSection.appearance.icon)
                    .tag(SettingsSection.appearance)
                Label("显示器", systemImage: SettingsSection.display.icon)
                    .tag(SettingsSection.display)
            }

            Section("高级") {
                Label("快捷键", systemImage: SettingsSection.hotkey.icon)
                    .tag(SettingsSection.hotkey)
                Label("关于", systemImage: SettingsSection.about.icon)
                    .tag(SettingsSection.about)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selected {
        case .appearance, .none:
            AppearancePane(prefs: prefs)
        case .display:
            DisplayPane(prefs: prefs)
        case .hotkey:
            HotkeyPane(prefs: prefs)
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
                Text(String(format: "%.0f %@", value.wrappedValue, unit))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 2)
        }
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

// MARK: - 快捷键

// MARK: - 快捷键录制器

/// 在「录制模式」下捕获下一次按键事件作为新快捷键
@MainActor
private final class HotkeyRecorder: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?
    var onCapture: ((NSEvent) -> Void)?

    /// 纯修饰键的键码，仅按这些键时不应作为主键
    private let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62]

    nonisolated init() {}

    func start() {
        guard !isRecording else { return }
        isRecording = true
        UserPreferences.shared.isCapturingHotkey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        // Esc 取消录制
        if event.keyCode == 53 { stop(); return }
        // 仅按下修饰键时忽略，等待主键
        if modifierKeyCodes.contains(event.keyCode) { return }
        onCapture?(event)
        stop()
    }

    func stop() {
        isRecording = false
        UserPreferences.shared.isCapturingHotkey = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - 快捷键

private struct HotkeyPane: View {
    @Bindable var prefs: UserPreferences
    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        Form {
            Section("全局快捷键") {
                Toggle("启用快捷键呼出启动台", isOn: $prefs.hotkeyEnabled)

                if !prefs.hotkeyEnabled {
                    Text("⚠️ 快捷键已关闭，即使已授权辅助功能也不会呼出启动台。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text("当前快捷键")
                    Spacer()
                    if recorder.isRecording {
                        Text("请按下新的组合键…")
                            .foregroundStyle(.orange)
                    } else {
                        Text(prefs.hotkeyDescription)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if recorder.isRecording {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Button("取消 (Esc)") { recorder.stop() }
                            .controlSize(.small)
                    }
                } else {
                    Button("设置快捷键…") { recorder.start() }
                        .controlSize(.small)
                }

                Button("恢复默认 (⌥空格)") { prefs.resetHotkeyToDefault() }
                    .controlSize(.small)

                Button("测试触发") {
                    // 先重建监听（如有授权后未生效的情况），再直接呼出面板确认链路通畅
                    (NSApp.delegate as? AppDelegate)?.ensureGlobalHotkey()
                    (NSApp.delegate as? AppDelegate)?.toggle()
                }
                .controlSize(.small)

                // 实时诊断：打开设置后盯着这里，按 ⌥C 看计数变化
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    let delegate = NSApp.delegate as? AppDelegate
                    VStack(alignment: .leading, spacing: 4) {
                        Text("诊断：监听收到按键 \(delegate?.hotkeyMonitorFiredCount ?? 0) 次")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("诊断：匹配并触发 \(delegate?.hotkeyMatchedCount ?? 0) 次")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("提示：按 ⌥C 后「收到」不涨→监听未收到事件（多因监听建于授权前，关闭本窗口再打开一次即可重建；或别的 App 抢了 ⌥C）。「收到」涨但「触发」不涨→修饰键/键码不匹配。")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }

            Section("辅助功能权限") {
                // 实时轮询：TCC 在进程启动时判定，开启后需重启 App 才会生效，
                // 用 TimelineView 每秒刷新一次，重启回来后状态灯自动变绿。
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    let granted = AXIsProcessTrusted()
                    HStack {
                        Text("当前状态")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(granted ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(granted ? "已授权" : "未授权")
                                .foregroundStyle(granted ? Color.secondary : Color.red)
                        }
                    }
                }

                Text("全局快捷键依赖「辅助功能」权限。受 macOS 安全限制，无法由代码自动勾选；点击下方按钮可让系统把本 App 登记进列表并弹出授权提示，再跳到设置页手动开启即可。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("⚠️ 在系统设置中开启后，必须**完全退出本程序（⌘Q）并重新启动**才会生效；仅关闭设置窗口无效。")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Button(AXIsProcessTrusted() ? "重新打开辅助功能设置" : "一键添加辅助功能权限…") {
                    requestAccessibility()
                }
                .controlSize(.small)

                Button("在访达中显示 App（可拖入列表）") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear {
            recorder.onCapture = { [weak prefs] event in
                prefs?.setHotkey(from: event)
            }
            // 打开设置即重建全局监听，确保授权后无需整机重启即可生效
            (NSApp.delegate as? AppDelegate)?.ensureGlobalHotkey()
        }
        .onDisappear { recorder.stop() }
        .onChange(of: prefs.hotkeyEnabled) { _, _ in
            // 开启快捷键时若全局监听未建立（例如授权前启动、授权后才打开开关），立即重建，无需整机重启
            (NSApp.delegate as? AppDelegate)?.ensureGlobalHotkey()
        }
    }

    // 让系统把本 App 登记进辅助功能列表并弹出授权提示，再跳到设置页
    private func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
