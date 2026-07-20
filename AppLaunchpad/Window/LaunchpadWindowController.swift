import AppKit
import SwiftUI

/// 管理覆盖全屏的 NSPanel，承载 SwiftUI 启动台界面
@MainActor
final class LaunchpadWindowController {

    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private let viewModel: LaunchpadViewModel

    var isVisible: Bool { panel?.isVisible ?? false }

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        NSApp.setActivationPolicy(.regular)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 本地键盘监听：Escape 关闭
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 53 { // Escape
                    if !viewModel.searchText.isEmpty {
                        viewModel.searchText = ""
                    } else {
                        hide()
                    }
                    return nil
                }
                return event
            }
        }

        viewModel.show()
    }

    func hide() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        panel?.orderOut(nil)
        viewModel.hide()
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let p = NSPanel(
            contentRect: screen.frame,
            // 移除 .nonactivatingPanel：需要 panel 接收键盘事件，不能阻止激活
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false

        // 传入 dismiss 闭包，SwiftUI 层通过它关闭 panel，不直接操作 viewModel
        let rootView = LaunchpadView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.hide()
        })
        p.contentView = NSHostingView(rootView: rootView)
        return p
    }
}
