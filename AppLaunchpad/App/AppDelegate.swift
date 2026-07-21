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

        let vm = LaunchpadViewModel()
        viewModel = vm
        windowController = LaunchpadWindowController(viewModel: vm)

        setupStatusItem()
        setupGlobalHotkey()
        setupWindowObservers()

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
        // 打开 SwiftUI Window 场景（"设置"）
        NSApp.sendAction(Selector(("showWindow:")), to: nil, from: nil)
    }

    // MARK: - 窗口层级观察（让 SwiftUI Settings 场景的设置窗口能浮在全屏面板之上）

    private func setupWindowObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    /// 当面板可见时，任何非面板窗口成为 key（例如原生 Settings 窗口），都要把面板降到普通层级，
    /// 否则高层级面板会把设置窗口挡在背后看不见。
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let wc = windowController,
              window != wc.hostWindow,
              wc.isVisible,
              !wc.isPanelLowered else { return }
        wc.lowerPanelForSettings()
        window.makeKeyAndOrderFront(nil)
    }

    /// 非面板窗口关闭后，把面板恢复回 screenSaver-1 层级，继续当启动台用。
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let wc = windowController,
              window != wc.hostWindow,
              wc.isPanelLowered,
              wc.isVisible else { return }
        wc.restorePanelLevel()
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
}
