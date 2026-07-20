import AppKit
import SwiftUI

/// 管理覆盖全屏的 NSPanel，承载 SwiftUI 启动台界面
@MainActor
final class LaunchpadWindowController {

    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var scrollMonitor: Any?
    private let viewModel: LaunchpadViewModel

    // 触控板：累积 scrollWheel 偏移
    private var accumulatedScrollX: CGFloat = 0
    // 防止连续翻页（上次翻页时间）
    private var lastPageFlipTime: Date = .distantPast

    var isVisible: Bool { panel?.isVisible ?? false }

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        // display: true 强制重绘，确保 SwiftUI 拿到正确的 frame 尺寸
        panel.setFrame(primaryScreen.frame, display: true)

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
            case 123: // ←：只在非搜索状态翻页，搜索时透传给 TextField 处理光标
                if !viewModel.isSearching {
                    viewModel.goToPreviousPage()
                    return nil
                }
                return event
            case 124: // →：同上
                if !viewModel.isSearching {
                    viewModel.goToNextPage()
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    // MARK: - 触控板 + 鼠标滚轮翻页

    private func setupScrollMonitor() {
        guard scrollMonitor == nil else { return }
        accumulatedScrollX = 0

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, !viewModel.isSearching else { return event }

            // 只处理以横向为主的滚动
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }

            if event.phase == .none && event.momentumPhase == .none {
                // ── 物理鼠标滚轮：phase 恒为 .none，每个事件独立判断
                flipPage(deltaX: event.scrollingDeltaX * 3)
            } else if event.momentumPhase == .none {
                // ── 触控板手势：累积 delta，松手后判断
                if event.phase == .began { accumulatedScrollX = 0 }
                accumulatedScrollX += event.scrollingDeltaX
                if event.phase == .ended || event.phase == .cancelled {
                    flipPage(deltaX: accumulatedScrollX)
                    accumulatedScrollX = 0
                }
            }
            // momentum 阶段（惯性）忽略，避免翻多页

            return event
        }
    }

    /// 根据累积偏移量决定翻页方向，带防抖（300ms 内不重复翻页）
    private func flipPage(deltaX: CGFloat) {
        let now = Date()
        guard now.timeIntervalSince(lastPageFlipTime) > 0.3 else { return }
        if deltaX < -80 {
            viewModel.goToNextPage()
            lastPageFlipTime = now
        } else if deltaX > 80 {
            viewModel.goToPreviousPage()
            lastPageFlipTime = now
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
