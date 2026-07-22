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
        restorePanelLevel()  // 确保每次呼出都在最高层级

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
    private var loweredForSettings = false

    var isPanelLowered: Bool { loweredForSettings }
    var hostWindow: NSWindow? { panel }

    /// 打开设置前降低面板层级，让原生设置窗口浮在上方
    func lowerPanelForSettings() {
        guard !loweredForSettings else { return }
        panel?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)))
        loweredForSettings = true
    }

    /// 设置窗口关闭后恢复面板层级
    func restorePanelLevel() {
        guard loweredForSettings else { return }
        panel?.level = highLevel
        loweredForSettings = false
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
            // 若启动台内已有 SwiftUI TextField（如文件夹重命名）获得焦点，
            // 所有按键交还给该输入框处理（否则会被下方逻辑吞掉去触发搜索）。
            if self.isTextInputFirstResponder() {
                return event
            }
            let cols = viewModel.columnCount(for: primaryScreen)
            switch event.keyCode {
            case 53: // ESC：逐级退出
                if viewModel.isEditMode {
                    viewModel.exitEditMode()
                } else if viewModel.isSearching {
                    if !viewModel.searchText.isEmpty {
                        viewModel.searchText = ""
                        viewModel.clearSelection()
                    } else {
                        hide()
                    }
                } else if viewModel.selectedSlotIndex != nil || viewModel.selectedSearchIndex != nil {
                    viewModel.clearSelection()
                } else {
                    hide()
                }
                return nil
            case 36: // Return：打开选中项
                viewModel.activateSelected()
                return nil
            case 123: // ←
                if viewModel.isSearching {
                    viewModel.moveSearchSelection(dx: -1, dy: 0, columns: cols)
                } else if viewModel.selectedSlotIndex != nil {
                    viewModel.moveGridSelection(dx: -1, dy: 0, columns: cols)
                } else {
                    withAnimation(.spring(duration: 0.38, bounce: 0.18)) { viewModel.goToPreviousPage() }
                }
                return nil
            case 124: // →
                if viewModel.isSearching {
                    viewModel.moveSearchSelection(dx: 1, dy: 0, columns: cols)
                } else if viewModel.selectedSlotIndex != nil {
                    viewModel.moveGridSelection(dx: 1, dy: 0, columns: cols)
                } else {
                    withAnimation(.spring(duration: 0.38, bounce: 0.18)) { viewModel.goToNextPage() }
                }
                return nil
            case 125: // ↓
                if viewModel.isSearching { viewModel.moveSearchSelection(dx: 0, dy: 1, columns: cols) }
                else { viewModel.moveGridSelection(dx: 0, dy: 1, columns: cols) }
                return nil
            case 126: // ↑
                if viewModel.isSearching { viewModel.moveSearchSelection(dx: 0, dy: -1, columns: cols) }
                else { viewModel.moveGridSelection(dx: 0, dy: -1, columns: cols) }
                return nil
            case 51: // ⌫ Delete：删除搜索字符
                if viewModel.isSearching, !viewModel.searchText.isEmpty {
                    viewModel.searchText.removeLast()
                    viewModel.selectedSearchIndex = viewModel.searchText.isEmpty ? nil : 0
                }
                return nil
            default:
                // 可打印字符：直接进入字母过滤（letter-based search）
                if let chars = event.characters,
                   !chars.isEmpty,
                   !event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.control),
                   !event.modifierFlags.contains(.option) {
                    viewModel.searchText += chars
                    viewModel.selectedSearchIndex = viewModel.searchText.isEmpty ? nil : 0
                    return nil
                }
                return event
            }
        }
    }

    // MARK: - 触控板 + 鼠标滚轮翻页

    private var scrollDebounceTimer: Timer?

    // MARK: - 文本输入焦点判断

    /// 判断当前窗口 firstResponder 是否为 SwiftUI TextField（字段编辑器 NSText，
    /// 或 NSTextField）。文件夹重命名等内联输入框聚焦时命中，此时应放行按键。
    private func isTextInputFirstResponder() -> Bool {
        guard let responder = panel?.firstResponder else { return false }
        return responder is NSText || responder is NSTextField
    }

    private func setupScrollMonitor() {
        guard scrollMonitor == nil else { return }
        accumulatedScrollX = 0
        accumulatedScrollY = 0

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // 拖拽中 / 编辑态下禁用滚轮翻页：避免拖到其他页时滚动额外翻页干扰落点（冲突 C3）
            guard let self,
                  !viewModel.isSearching,
                  !viewModel.dragState.isDragging,
                  !viewModel.isEditMode else { return event }
            guard event.momentumPhase.isEmpty else { return event }  // 忽略惯性阶段

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
            onDismiss: { [weak self] in self?.hide() }
        )
        p.contentView = NSHostingView(rootView: rootView)
        return p
    }
}
