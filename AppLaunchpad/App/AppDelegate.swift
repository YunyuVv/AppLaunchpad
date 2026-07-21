import AppKit
import SwiftUI

/// 管理 App 生命周期、菜单栏图标、FSEvents 目录监听
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: LaunchpadWindowController?
    private var viewModel: LaunchpadViewModel?
    private var statusItem: NSStatusItem?
    private var fsWatcher: FSEventsWatcher?

    // 直接持有设置窗口，不依赖 sendAction 响应链
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let vm = LaunchpadViewModel()
        viewModel = vm
        windowController = LaunchpadWindowController(viewModel: vm)

        setupStatusItem()
        setupGlobalHotkey()

        Task {
            await vm.loadApps()
            await startFSWatcher(vm: vm)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalHotkeyMonitor { NSEvent.removeMonitor(monitor) }
        Task { await fsWatcher?.stop() }
    }

    // MARK: - Dock 图标点击

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        toggle()
        return false
    }

    // MARK: - 设置窗口（直接创建，不走 sendAction）

    func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 先清除全屏展示选项（hideDock/autoHideMenuBar 会阻止普通窗口浮现）
        NSApp.presentationOptions = []

        // 把面板层级降到 normal，让设置窗口可以浮在它上面
        windowController?.lowerPanelForSettings()

        let controller = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: controller)
        window.title = "AppLaunchpad 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 420, height: 300))
        window.center()
        window.isReleasedWhenClosed = false
        // 显式设置 .floating 层级（3），高于降低后的面板（0），确保浮在上方
        window.level = .floating
        settingsWindow = window

        // 窗口关闭时恢复面板层级和展示选项
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.windowController?.restorePanelLevel()
                // 如果面板还在显示，重新隐藏 Dock/菜单栏
                if self?.windowController?.isVisible == true {
                    NSApp.presentationOptions = [.hideDock, .autoHideMenuBar]
                }
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - FSEvents

    private func startFSWatcher(vm: LaunchpadViewModel) async {
        let watcher = FSEventsWatcher {
            Task { @MainActor in await vm.refreshApps() }
        }
        await watcher.start()
        self.fsWatcher = watcher
    }

    // MARK: - 全局快捷键

    private var globalHotkeyMonitor: Any?

    /// 诊断用计数：监听收到的总按键数、以及匹配成功后实际触发的次数
    var hotkeyMonitorFiredCount: Int = 0
    var hotkeyMatchedCount: Int = 0

    /// 注册全局快捷键，呼出/收起启动台。需要辅助功能权限才生效
    private func setupGlobalHotkey() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.hotkeyMonitorFiredCount += 1
                let prefs = UserPreferences.shared
                guard !prefs.isCapturingHotkey,
                      prefs.hotkeyEnabled,
                      event.keyCode == UInt16(prefs.hotkeyKeyCode),
                      event.modifierFlags.intersection([.control, .option, .shift, .command]) ==
                        NSEvent.ModifierFlags(rawValue: prefs.hotkeyModifiers) else { return }
                self?.hotkeyMatchedCount += 1
                self?.toggle()
            }
        }
    }

    /// （重新）建立全局监听。先移除旧监听再新建，确保授权后即时生效，无需整机重启。
    /// 在打开设置、切换开关、点击「测试触发」时调用。
    func ensureGlobalHotkey() {
        if let m = globalHotkeyMonitor { NSEvent.removeMonitor(m); globalHotkeyMonitor = nil }
        setupGlobalHotkey()
    }

    // MARK: - 菜单栏图标

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "AppLaunchpad")

        let menu = NSMenu()
        menu.addItem(withTitle: "打开启动台", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 AppLaunchpad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    // MARK: - 切换显示

    @objc func toggle() {
        guard let wc = windowController else { return }
        if wc.isVisible { wc.hide() } else { wc.show() }
    }
}
