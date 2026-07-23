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

// MARK: - 快捷键面板

struct HotkeyPane: View {
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

                Button("恢复默认 (⌥空格)") {
                    prefs.resetHotkeyToDefault()
                    // 复位后主动重建全局监听，确保新的默认快捷键立即生效（无需整机重启）
                    (NSApp.delegate as? AppDelegate)?.ensureGlobalHotkey()
                }
                .controlSize(.small)

                Button("测试触发") {
                    // 先重建监听（如有授权后未生效的情况），再明确呼出面板确认链路通畅
                    (NSApp.delegate as? AppDelegate)?.ensureGlobalHotkey()
                    (NSApp.delegate as? AppDelegate)?.showLaunchpad()
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
