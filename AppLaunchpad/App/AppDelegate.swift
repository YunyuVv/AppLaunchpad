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
        // TODO: Phase 7 设置页面中开放全局快捷键配置（默认 F4，可自定义）
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
