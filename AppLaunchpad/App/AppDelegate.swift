import AppKit
import SwiftUI

/// 管理 App 生命周期、菜单栏图标、FSEvents 目录监听
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: LaunchpadWindowController?
    private var viewModel: LaunchpadViewModel?
    private var statusItem: NSStatusItem?
    private var fsWatcher: FSEventsWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // 启动时把持久化的外观模式（自动/浅色/深色）应用到全局，
        // 保证 SwiftUI 各 View 的 @Environment(\.colorScheme) 立即正确。
        UserPreferences.shared.applyAppearance()

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

    // MARK: - Dock 菜单

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开启动台", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "").target = self
        return menu
    }

    @objc private func openSettings() {
        // 通过 SwiftUI 环境桥接的 openWindow(id:) 打开设置场景，
        // 而不是 showWindow:（依赖响应者链，对 Window(id:) 场景不可靠）。
        if let opener = settingsOpener {
            opener()
        } else {
            NSApp.sendAction(#selector(NSWindowController.showWindow(_:)), to: nil, from: nil)
        }
    }

    /// 由 AppLaunchpadApp 在 body 中注入：捕获 SwiftUI 环境的 openWindow 动作，
    /// 让 AppKit 侧的 Dock / 状态栏菜单能可靠打开设置场景。
    var settingsOpener: (@MainActor () -> Void)?

    func setSettingsOpener(_ opener: @escaping @MainActor () -> Void) {
        settingsOpener = opener
    }

    // MARK: - Dock 点击

    /// 左键点击 Dock 图标时切换启动台显示/收起，与原生 Launchpad 行为一致。
    /// 返回 false 表示已自行处理，不触发系统默认的窗口恢复行为。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggle()
        return false
    }

    // MARK: - 常驻：关窗不退出

    /// 设置窗口是 App 唯一的标准窗口，关闭它不应退出程序（启动台面板是 NSPanel，不在场景系统内）。
    /// 显式返回 false，确保"保持常驻"——退出仅通过 ⌘Q / 状态栏菜单。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
        // 菜单栏图标使用本项目 App 图标（彩色），适配菜单栏高度约 18pt；取不到时回退系统符号
        if let appIcon = NSImage(named: "AppIcon") {
            appIcon.size = NSSize(width: 18, height: 18)
            appIcon.isTemplate = false
            item.button?.image = appIcon
        } else {
            item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "AppLaunchpad")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "打开启动台", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "").target = self
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

    /// 明确呼出启动台（仅当未显示时才 show），供「测试触发」按钮使用，
    /// 避免 toggle 在启动台已显示时反而收起、造成「按钮没反应」的错觉。
    func showLaunchpad() {
        guard let wc = windowController else { return }
        if !wc.isVisible { wc.show() }
    }
}
