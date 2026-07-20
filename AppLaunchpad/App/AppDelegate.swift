import AppKit

/// 管理 App 生命周期、菜单栏图标、全局快捷键入口
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: LaunchpadWindowController?
    private var viewModel: LaunchpadViewModel?

    // 菜单栏图标，持有引用防止被释放
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // regular 模式：Dock 图标常驻，用户可从 Dock 点击打开启动台
        NSApp.setActivationPolicy(.regular)

        let vm = LaunchpadViewModel()
        viewModel = vm
        windowController = LaunchpadWindowController(viewModel: vm)

        setupStatusItem()

        Task {
            await vm.loadApps()
        }

        setupGlobalHotkey()
    }

    // MARK: - Dock 图标点击

    /// 点击 Dock 图标时触发（hasVisibleWindows 为 false 时也会调用）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        toggle()
        return false
    }

    // MARK: - 菜单栏图标

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "AppLaunchpad")
        item.button?.action = #selector(statusItemClicked)
        item.button?.target = self
        statusItem = item
    }

    @objc private func statusItemClicked() {
        toggle()
    }

    // MARK: - 全局快捷键

    private func setupGlobalHotkey() {
        // 若无辅助功能权限，addGlobalMonitorForEvents 静默失效，不影响菜单栏触发
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // keyCode 37 = L，仅 Phase 1 测试用，Phase 3 改为 F4
            guard event.modifierFlags.contains(.command), event.keyCode == 37 else { return }
            Task { @MainActor [weak self] in self?.toggle() }
        }
    }

    // MARK: - 切换显示

    func toggle() {
        guard let wc = windowController else { return }
        if wc.isVisible {
            wc.hide()
        } else {
            wc.show()
        }
    }
}
