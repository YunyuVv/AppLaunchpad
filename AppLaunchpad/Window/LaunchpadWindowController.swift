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

        // 先更新激活策略，再显示窗口
        NSApp.setActivationPolicy(.regular)

        // orderFrontRegardless 比 makeKeyAndOrderFront 更可靠，不依赖 App 是否已激活
        panel.orderFrontRegardless()
        panel.makeKey()

        // 短暂延迟激活，确保 setActivationPolicy 已生效
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }

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
            .onExitCommand { [weak self] in
                guard let self else { return }
                if !viewModel.searchText.isEmpty {
                    viewModel.searchText = ""
                } else {
                    hide()
                }
            }
        p.contentView = NSHostingView(rootView: rootView)
        return p
    }
}
