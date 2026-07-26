import SwiftUI
import AppKit
import ApplicationServices

// MARK: - 快捷键录制器

/// 在「录制模式」下捕获下一次按键事件作为新快捷键
@MainActor
final class HotkeyRecorder: ObservableObject {
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

// MARK: - 交互面板（合并「手势」+「快捷键」）

struct InteractionPane: View {
    @Bindable var prefs: UserPreferences
    @StateObject private var recorder = HotkeyRecorder()

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

            Section("全局快捷键") {
                Toggle("启用快捷键呼出启动台", isOn: $prefs.hotkeyEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.regular)

                if prefs.hotkeyEnabled {
                    LabeledContent("当前快捷键") {
                        Text(recorder.isRecording
                             ? "请按下新组合键…"
                             : prefs.hotkeyDescription)
                            .foregroundStyle(recorder.isRecording ? .orange : .secondary)
                            .monospacedDigit()
                    }

                    HStack(spacing: 8) {
                        if recorder.isRecording {
                            ProgressView().controlSize(.small)
                            Button("取消") { recorder.stop() }
                        } else {
                            Button("设置快捷键…") { recorder.start() }
                            Button("恢复默认") {
                                prefs.resetHotkeyToDefault()
                                // 复位后主动重建全局监听，确保默认快捷键立即生效（无需整机重启）
                                (NSApp.delegate as? AppDelegate)?.ensureGlobalHotkey()
                            }
                        }
                    }
                } else {
                    Text("快捷键已关闭，不会呼出启动台")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                Text("⚠️ 在系统设置中开启后，必须**完全退出本程序（⌘Q）并重新启动**才会生效；仅关闭设置窗口无效。\n如在「辅助功能」列表中找不到 AppLaunchpad，请先关闭本程序，再重新启动一次即可出现。")
                    .font(.caption)
                    .foregroundStyle(.orange)

                HStack {
                    Button(AXIsProcessTrusted() ? "重新打开辅助功能设置" : "打开辅助功能设置…") {
                        // App 启动时已通过 NSEvent.addGlobalMonitorForEvents 让系统把本 App
                        // 自动登记到辅助功能列表，无需 AXIsProcessTrustedWithOptions 显式申请
                        // （那会强制弹系统授权框，绕一圈反而打断用户）。
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                    Spacer()
                    Button("在访达中显示 App（可拖入列表）") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    .controlSize(.small)
                }
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
}
