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
        panel.makeKey()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }

        // 本地键盘监听：Escape 关闭，比 onExitCommand 更可靠
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // keyCode 53 = Escape
                if event.keyCode == 53 {
                    if !self.viewModel.searchText.isEmpty {
                        self.viewModel.searchText = ""
                    } else {
                        self.hide()
                    }
                    return nil  // 消费该事件，不再传递
                }
                return event
            }
        }

        viewModel.show()
    }

    func hide() {
        // 移除本地监听器
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
            styleMask: [.borderless, .nonactivatingPanel],
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

        let rootView = LaunchpadView(viewModel: viewModel)
        p.contentView = NSHostingView(rootView: rootView)
        return p
    }
}
