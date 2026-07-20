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
    private var accumulatedScrollY: CGFloat = 0  // 同时记录 Y，用于判断方向是否以水平为主
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
        NSApp.presentationOptions = []
    }

    private let highLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)

    /// 打开设置前降低面板层级，让设置窗口浮在上方
    func lowerPanelForSettings() {
        panel?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)))
    }

    /// 设置窗口关闭后恢复面板层级
    func restorePanelLevel() {
        panel?.level = highLevel
    }

    // 供 LaunchpadView 右键菜单调用（转发到 AppDelegate）
    func openSettings() {
        // 直接通过 AppDelegate 打开，确保走统一入口
        (NSApp.delegate as? AppDelegate)?.showSettings()
    }

    // MARK: - 主屏幕

    private var primaryScreen: NSScreen {
        switch UserPreferences.shared.multiMonitorMode {
        case .primaryScreen:
            return NSScreen.screens.first ?? NSScreen.screens[0]
        case .mouseScreen:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouse) }
                ?? NSScreen.screens.first
                ?? NSScreen.screens[0]
        }
    }

    // MARK: - 键盘监听

    private func setupKeyMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Escape：编辑模式 → 退出编辑；搜索中 → 清空；否则 → 关闭面板
                if viewModel.isEditMode {
                    viewModel.exitEditMode()
                } else if !viewModel.searchText.isEmpty {
                    viewModel.searchText = ""
                } else {
                    hide()
                }
                return nil
            case 123: // ← 方向键：搜索时透传给 TextField
                if !viewModel.isSearching {
                    withAnimation(.spring(duration: 0.38, bounce: 0.18)) { viewModel.goToPreviousPage() }
                    return nil
                }
                return event
            case 124: // → 方向键：同上
                if !viewModel.isSearching {
                    withAnimation(.spring(duration: 0.38, bounce: 0.18)) { viewModel.goToNextPage() }
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    // MARK: - 触控板 + 鼠标滚轮翻页

    private var scrollDebounceTimer: Timer?

    private func setupScrollMonitor() {
        guard scrollMonitor == nil else { return }
        accumulatedScrollX = 0
        accumulatedScrollY = 0

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, !viewModel.isSearching else { return event }
            guard event.momentumPhase == .none else { return event }  // 忽略惯性阶段

            if event.hasPreciseScrollingDeltas {
                // ── 触控板：用 phase 全程累积 x 和 y，只在 .ended 时整体判断方向
                switch event.phase {
                case .began:
                    accumulatedScrollX = 0
                    accumulatedScrollY = 0
                case .changed:
                    accumulatedScrollX += event.scrollingDeltaX
                    accumulatedScrollY += event.scrollingDeltaY
                case .ended, .cancelled:
                    let ax = abs(accumulatedScrollX)
                    let ay = abs(accumulatedScrollY)
                    // 水平方向主导且幅度足够时翻页
                    if ax > ay && ax > 20 {
                        flipPage(deltaX: accumulatedScrollX > 0 ? 100 : -100)
                    }
                    accumulatedScrollX = 0
                    accumulatedScrollY = 0
                default:
                    break
                }
            } else {
                // ── 物理鼠标滚轮：每步事件直接响应
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
            withAnimation(.spring(duration: 0.38, bounce: 0.18)) {
                viewModel.goToNextPage()
            }
            lastPageFlipTime = now
        } else if deltaX > 80 {
            withAnimation(.spring(duration: 0.38, bounce: 0.18)) {
                viewModel.goToPreviousPage()
            }
            lastPageFlipTime = now
        }
    }

    // MARK: - 清理

    private func removeMonitors() {
        scrollDebounceTimer?.invalidate()
        scrollDebounceTimer = nil
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

        let rootView = LaunchpadView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        p.contentView = NSHostingView(rootView: rootView)
        return p
    }
}
