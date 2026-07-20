import AppKit
import SwiftUI

/// 管理覆盖全屏的 NSPanel，承载 SwiftUI 启动台界面
@MainActor
final class LaunchpadWindowController {

    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var scrollMonitor: Any?
    private let viewModel: LaunchpadViewModel

    // 累积 scrollWheel 偏移，用于判断翻页方向
    private var accumulatedScrollX: CGFloat = 0

    var isVisible: Bool { panel?.isVisible ?? false }

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        // 每次显示都更新到主屏幕（screens.first 始终是主屏幕）
        let screen = primaryScreen
        panel.setFrame(screen.frame, display: false)

        NSApp.setActivationPolicy(.regular)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupKeyMonitor()
        setupScrollMonitor()
        viewModel.show()
    }

    func hide() {
        removeMonitors()
        panel?.orderOut(nil)
        viewModel.hide()
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - 主屏幕

    /// 主屏幕 = screens.first（系统设置中被设为主屏幕的那个，带菜单栏）
    private var primaryScreen: NSScreen {
        NSScreen.screens.first ?? NSScreen.screens[0]
    }

    // MARK: - 键盘监听

    private func setupKeyMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Escape
                if !viewModel.searchText.isEmpty {
                    viewModel.searchText = ""
                } else {
                    hide()
                }
                return nil
            case 123: // ←
                if !viewModel.isSearching { viewModel.goToPreviousPage() }
                return nil
            case 124: // →
                if !viewModel.isSearching { viewModel.goToNextPage() }
                return nil
            default:
                return event
            }
        }
    }

    // MARK: - 触控板双指滑动（scrollWheel）

    private func setupScrollMonitor() {
        guard scrollMonitor == nil else { return }
        accumulatedScrollX = 0

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, !viewModel.isSearching else { return event }

            // 只处理明显的横向滑动
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }

            if event.phase == .began {
                accumulatedScrollX = 0
            }

            accumulatedScrollX += event.scrollingDeltaX

            if event.phase == .ended || event.phase == .cancelled {
                // 松手：超过阈值则翻页
                if accumulatedScrollX < -80 {
                    viewModel.goToNextPage()
                } else if accumulatedScrollX > 80 {
                    viewModel.goToPreviousPage()
                }
                accumulatedScrollX = 0
            }

            return event
        }
    }

    // MARK: - 清理

    private func removeMonitors() {
        [localEventMonitor, scrollMonitor].compactMap { $0 }.forEach {
            NSEvent.removeMonitor($0)
        }
        localEventMonitor = nil
        scrollMonitor = nil
    }

    // MARK: - 创建 Panel

    private func makePanel() -> NSPanel {
        let screen = primaryScreen
        let p = NSPanel(
            contentRect: screen.frame,
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

        let rootView = LaunchpadView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.hide()
        })
        p.contentView = NSHostingView(rootView: rootView)
        return p
    }
}
