import AppKit
import SwiftUI

// MARK: - 自定义 Panel，解决 borderless 窗口无法成为 key window 的问题

/// borderless NSPanel 默认 canBecomeKey = false，导致内部 TextField 无法获得焦点
/// 覆盖后才能让 SwiftUI TextField 正常接收键盘输入
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 窗口控制器

/// 管理覆盖全屏的 NSPanel，承载 SwiftUI 启动台界面
@MainActor
final class LaunchpadWindowController {

    private var panel: KeyablePanel?
    private var localEventMonitor: Any?
    private var scrollMonitor: Any?
    private let viewModel: LaunchpadViewModel

    private var accumulatedScrollX: CGFloat = 0
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

        panel.setFrame(primaryScreen.frame, display: true)

        // 呼出时隐藏 Dock + 菜单栏，与原生 Launchpad 一致
        NSApp.presentationOptions = [.hideDock, .autoHideMenuBar]
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
        // 恢复 Dock + 菜单栏
        NSApp.presentationOptions = []
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
            case 123: // ← 方向键：搜索时透传给 TextField
                if !viewModel.isSearching {
                    viewModel.goToPreviousPage()
                    return nil
                }
                return event
            case 124: // → 方向键：同上
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
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }

            if event.hasPreciseScrollingDeltas {
                // ── 触控板：连续精确滚动，phase 累积后判断
                // 忽略惯性阶段，防止翻多页
                guard event.momentumPhase == .none else { return event }
                if event.phase == .began { accumulatedScrollX = 0 }
                accumulatedScrollX += event.scrollingDeltaX
                if event.phase == .ended || event.phase == .cancelled {
                    // 触控板阈值降低到 30pt（原 80pt 太难触发）
                    if accumulatedScrollX < -30 {
                        flipPage(deltaX: -100)
                    } else if accumulatedScrollX > 30 {
                        flipPage(deltaX: 100)
                    }
                    accumulatedScrollX = 0
                }
            } else {
                // ── 物理鼠标滚轮：离散事件，deltaX 为整数步数
                if event.deltaX < 0 {
                    flipPage(deltaX: -100)
                } else if event.deltaX > 0 {
                    flipPage(deltaX: 100)
                }
            }

            return event
        }
    }

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

    private func makePanel() -> KeyablePanel {
        let screen = primaryScreen
        let p = KeyablePanel(
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
