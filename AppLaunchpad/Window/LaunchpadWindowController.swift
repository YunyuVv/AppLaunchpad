import AppKit
import SwiftUI

/// 管理覆盖全屏的 NSPanel，承载 SwiftUI 启动台界面
@MainActor
final class LaunchpadWindowController {

    private var panel: NSPanel?
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
        // 切换为普通激活策略，使 panel 能接收键盘事件
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        viewModel.show()
    }

    func hide() {
        panel?.orderOut(nil)
        viewModel.hide()
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let p = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 覆盖在几乎所有窗口之上（低于屏保一级，避免遮挡系统弹窗）
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false

        let rootView = LaunchpadView(viewModel: viewModel)
            .onExitCommand {
                // Escape 键：有搜索词则清空，否则关闭
                Task { @MainActor [weak self] in
                    if !self!.viewModel.searchText.isEmpty {
                        self!.viewModel.searchText = ""
                    } else {
                        self?.hide()
                    }
                }
            }
        p.contentView = NSHostingView(rootView: rootView)
        return p
    }
}
