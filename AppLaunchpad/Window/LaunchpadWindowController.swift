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

    /// 当前启动台应展示的屏幕（跟随设置中的显示器选择）
    private var primaryScreen: NSScreen {
        UserPreferences.shared.targetScreen
    }

    // MARK: - 键盘监听

    private func setupKeyMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // ── 搜索框焦点处理 ──
            // 设计目标：拼音 IME 输入不分裂 + 翻页/导航不被吞。
            // - 搜索框已聚焦 且 有内容：所有按键（光标移动/删除/IME 合成）交还输入框。
            // - 搜索框已聚焦 但 为空：可打印字符（含拼音首字母）交还输入框，由其自然接收与
            //   触发 IME；方向键 / ESC / Return 等非可打印键落入下方键盘导航逻辑（翻页、退出），
            //   保证即使焦点残留也能正常翻页（不再被输入框吞掉）。
            // - 搜索框未聚焦：走下方字母搜索 / 键盘导航。
            let focused = self.isTextInputFirstResponder()
            let isPrintable = (event.characters?.isEmpty == false)
                && !event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.control)
                && !event.modifierFlags.contains(.option)
            if focused {
                if viewModel.searchText.isEmpty {
                    if isPrintable { return event }   // 让 IME 从首个字母起在输入框上下文合成
                } else {
                    return event                       // 有内容：全部交还输入框
                }
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
                // ── 触控板：双指横扫跟手平移（与原生 Launchpad 一致）──
                // .changed 阶段把累积量实时映射为跟手偏移，驱动视图层「当前页 + 相邻页」平移；
                // .ended 阶段按累积量阈值决定翻页（连续滑入）或弹簧回弹。
                let pageW = (viewModel.gridGeometry?.size.width) ?? (NSScreen.main?.frame.width ?? 0)
                switch event.phase {
                case .began:
                    accumulatedScrollX = 0
                    accumulatedScrollY = 0
                    viewModel.trackpadPagingOffsetX = 0
                case .changed:
                    accumulatedScrollX += event.scrollingDeltaX
                    accumulatedScrollY += event.scrollingDeltaY
                    // 映射为与 dragOffsetX 同语义的跟手偏移（负 = 看下一页）。
                    // 左滑（自然滚动下 scrollingDeltaX<0 → accumulatedScrollX<0 → off<0）= 看下一页，对齐原生 Launchpad。
                    // 增益：触控板累积量通常远小于整页宽，×gain 让页面明显跟手、更易越过翻页阈值。
                    // 并 clamp 到 ±一页宽，避免一次大幅横扫拖出多页。
                    let gain: CGFloat = UserPreferences.shared.trackpadPagingGain
                    let off = max(-pageW, min(pageW, accumulatedScrollX * gain))
                    viewModel.trackpadPagingOffsetX = off
                case .ended, .cancelled:
                    let ax = abs(accumulatedScrollX)
                    let ay = abs(accumulatedScrollY)
                    if ax > ay {
                        // 水平主导：累计幅度超阈值则翻页，否则当前页弹簧回正中。
                        // 方向与 .changed 一致（gain 后 virtualX<0 = 左滑 = 下一页），阈值用增益后位移判定。
                        let gain: CGFloat = UserPreferences.shared.trackpadPagingGain
                        let virtualX = accumulatedScrollX * gain
                        let threshold = pageW * 0.10
                        let goingNext = virtualX < 0
                        let current = viewModel.currentPageIndex
                        let total = viewModel.totalPages
                        let target = goingNext ? min(current + 1, total - 1) : max(current - 1, 0)
                        if abs(virtualX) > threshold, target != current {
                            // 提交翻页意图（一次性）。视图层 onChange 同步设起点后 goToPage，
                            // 复用鼠标拖拽的连续滑入，避免闪现正中。
                            viewModel.trackpadPagingCommit = TrackpadPageFlip(
                                offset: max(-pageW, min(pageW, virtualX)),
                                target: target
                            )
                            viewModel.trackpadPagingOffsetX = 0
                        } else {
                            // 未越阈值：当前页弹簧回正中（视图层 ZStack 跟手渲染内动画回 0 → 自动切单页）
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                viewModel.trackpadPagingOffsetX = 0
                            }
                        }
                    } else {
                        // 垂直主导：直接归零（不翻页）
                        viewModel.trackpadPagingOffsetX = 0
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
