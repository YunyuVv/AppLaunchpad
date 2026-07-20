import AppKit

/// 管理 App 生命周期、Dock 图标点击响应，以及全屏窗口的显示/隐藏切换
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: LaunchpadWindowController?
    private var viewModel: LaunchpadViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 后台应用模式：不出现在 Cmd+Tab 列表，仅保留 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        let vm = LaunchpadViewModel()
        viewModel = vm
        windowController = LaunchpadWindowController(viewModel: vm)

        // 后台异步扫描已安装应用
        Task {
            await vm.loadApps()
        }

        // 临时全局快捷键：Cmd+L 呼出/关闭（Phase 3 替换为 F4）
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // keyCode 37 = L
            guard event.modifierFlags.contains(.command), event.keyCode == 37 else { return }
            Task { @MainActor [weak self] in self?.toggle() }
        }
    }

    /// Dock 图标点击或 App 再次激活时，切换启动台显示/隐藏
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        toggle()
        return false
    }

    /// 切换启动台可见状态（供快捷键、Dock 点击共同使用）
    func toggle() {
        guard let wc = windowController else { return }
        if wc.isVisible {
            wc.hide()
        } else {
            wc.show()
        }
    }
}
