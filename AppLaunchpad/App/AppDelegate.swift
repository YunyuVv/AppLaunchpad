import AppKit

/// 管理 App 生命周期、菜单栏图标、FSEvents 目录监听
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: LaunchpadWindowController?
    private var viewModel: LaunchpadViewModel?
    private var statusItem: NSStatusItem?
    private var fsWatcher: FSEventsWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let vm = LaunchpadViewModel()
        viewModel = vm
        windowController = LaunchpadWindowController(viewModel: vm)

        setupStatusItem()

        Task {
            await vm.loadApps()
            // 首次扫描完成后启动目录监听
            await startFSWatcher(vm: vm)
        }
        // TODO: Phase 7 设置页面中开放全局快捷键配置（默认 F4，可自定义）
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await fsWatcher?.stop() }
    }

    // MARK: - Dock 图标点击

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        toggle()
        return false
    }

    // MARK: - FSEvents 目录监听

    private func startFSWatcher(vm: LaunchpadViewModel) async {
        let watcher = FSEventsWatcher {
            // 目录变化 → 重新扫描并合并布局（在主线程执行）
            Task { @MainActor in
                await vm.refreshApps()
            }
        }
        await watcher.start()
        self.fsWatcher = watcher
    }

    // MARK: - 菜单栏图标

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "AppLaunchpad")

        // 左键点击打开菜单，不再直接 toggle
        let menu = NSMenu()
        menu.addItem(withTitle: "打开启动台", action: #selector(toggle), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置...", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 AppLaunchpad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        windowController?.openSettings()
    }

    // MARK: - 切换显示

    @objc func toggle() {
        guard let wc = windowController else { return }
        if wc.isVisible { wc.hide() } else { wc.show() }
    }
}
