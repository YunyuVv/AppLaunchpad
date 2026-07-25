import Foundation
import AppKit
import ServiceManagement

/// 用户偏好设置，持久化到 UserDefaults
///
/// 关键约定：所有偏好都是**存储属性**并由 @Observable 追踪，
/// 改动会即时触发 SwiftUI 视图重绘（设置面板与启动台界面同步刷新）。
/// 持久化放在 didSet / init 中写回 UserDefaults。
@Observable
final class UserPreferences: @unchecked Sendable {
    static let shared = UserPreferences()

    private let defaults = UserDefaults.standard

    // MARK: - 外观

    /// 背景遮罩透明度（0.0 ~ 0.8）
    var backgroundOverlayOpacity: Double = 0.10 {
        didSet {
            let v = backgroundOverlayOpacity.clamped(to: 0...0.8).nonZero(default: 0.10)
            if v != backgroundOverlayOpacity { backgroundOverlayOpacity = v }
            defaults.set(backgroundOverlayOpacity, forKey: Keys.backgroundOverlayOpacity)
        }
    }

    /// 背景样式：0 = 磨砂玻璃，1 = macOS 26 液态玻璃（Liquid Glass，当前默认）
    var backgroundStyle: Int = 1 {
        didSet {
            let v = (backgroundStyle == 1) ? 1 : 0
            if v != backgroundStyle { backgroundStyle = v }
            defaults.set(backgroundStyle, forKey: Keys.backgroundStyle)
        }
    }

    /// 每行图标列数（0 = 根据屏幕宽度自动，3~12 = 手动指定）
    var columnCountOverride: Int = 0 {
        didSet { defaults.set(max(0, columnCountOverride), forKey: Keys.columnCountOverride) }
    }

    /// 每页行数（0 = 根据屏幕高度自动，3~8 = 手动指定）
    var rowCountOverride: Int = 0 {
        didSet { defaults.set(max(0, rowCountOverride), forKey: Keys.rowCountOverride) }
    }

    /// 图标最大尺寸 pt（0 = 自动撑满网格，56~200 = 手动限制）
    var iconSizeOverride: Double = 0 {
        didSet { defaults.set(iconSizeOverride, forKey: Keys.iconSizeOverride) }
    }

    // MARK: - 网格布局

    /// 水平间距（0 = 自动，按屏幕宽度比例推算；2~60 = 手动指定）
    var horizontalSpacing: Double = 0 {
        didSet {
            let v = horizontalSpacing.clamped(to: 0...60)
            if v != horizontalSpacing { horizontalSpacing = v }
            defaults.set(horizontalSpacing, forKey: Keys.horizontalSpacing)
        }
    }

    /// 垂直间距（0 = 自动；2~80 = 手动指定）
    var verticalSpacing: Double = 0 {
        didSet {
            let v = verticalSpacing.clamped(to: 0...80)
            if v != verticalSpacing { verticalSpacing = v }
            defaults.set(verticalSpacing, forKey: Keys.verticalSpacing)
        }
    }

    /// 左右边距（0 = 自动；2~200 = 手动指定）
    var sidePadding: Double = 0 {
        didSet {
            let v = sidePadding.clamped(to: 0...200)
            if v != sidePadding { sidePadding = v }
            defaults.set(sidePadding, forKey: Keys.sidePadding)
        }
    }

    /// 顶部边距（搜索栏上方，0 = 自动；2~200 = 手动指定）
    var topPadding: Double = 0 {
        didSet {
            let v = topPadding.clamped(to: 0...200)
            if v != topPadding { topPadding = v }
            defaults.set(topPadding, forKey: Keys.topPadding)
        }
    }

    /// 底部边距（分页指示器下方，0 = 自动；2~200 = 手动指定）
    var bottomPadding: Double = 0 {
        didSet {
            let v = bottomPadding.clamped(to: 0...200)
            if v != bottomPadding { bottomPadding = v }
            defaults.set(bottomPadding, forKey: Keys.bottomPadding)
        }
    }

    // MARK: - 显示器

    /// 启动台展示于哪块显示器。
    /// - primary: 主显示器（默认）
    /// - mouse:   鼠标所在显示器
    /// - specific: 指定某块显示器（按 CGDirectDisplayID 稳定标识，拔插/重排也不丢）
    enum DisplayTarget: Hashable {
        case primary
        case mouse
        case specific(CGDirectDisplayID)

        /// 持久化键：primary / mouse / specific:<displayID>
        var persistenceKey: String {
            switch self {
            case .primary:          return "primary"
            case .mouse:            return "mouse"
            case .specific(let id): return "specific:\(id)"
            }
        }

        init(persistenceKey: String?) {
            guard let key = persistenceKey, !key.isEmpty else { self = .primary; return }
            if key == "primary" { self = .primary; return }
            if key == "mouse"   { self = .mouse;   return }
            let parts = key.split(separator: ":")
            if parts.count == 2, parts[0] == "specific", let id = UInt32(parts[1]) {
                self = .specific(id); return
            }
            self = .primary
        }
    }

    /// 当前偏好：启动台展示的显示器目标（默认主显示器）
    var displayTarget: DisplayTarget = .primary {
        didSet { defaults.set(displayTarget.persistenceKey, forKey: Keys.displayTarget) }
    }

    /// 解析出实际要展示的 NSScreen。
    /// 指定显示器已断开时回退到主显示器，避免落到空屏。
    var targetScreen: NSScreen {
        let screens = NSScreen.screens
        switch displayTarget {
        case .primary:
            return screens.first ?? screens[0]
        case .mouse:
            let mouse = NSEvent.mouseLocation
            return screens.first { $0.frame.contains(mouse) }
                ?? screens.first ?? screens[0]
        case .specific(let id):
            return screens.first { Self.displayID(for: $0) == id }
                ?? screens.first ?? screens[0]
        }
    }

    /// 取屏幕的稳定显示 ID（CGDirectDisplayID）
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// 显示器展示名：名称 + 是否主显 + 分辨率，便于列表里辨认
    static func screenLabel(_ screen: NSScreen) -> String {
        let size = screen.frame.size
        let isMain = (screen == NSScreen.main)
        let tag = isMain ? "（主显示器）" : ""
        return "\(screen.localizedName)\(tag)  \(Int(size.width))×\(Int(size.height))"
    }

    // MARK: - 全局快捷键

    /// 录制期间临时标记，全局监听看到它会跳过触发（避免录制时误呼出）
    var isCapturingHotkey: Bool = false

    /// 是否启用全局快捷键呼出启动台（默认开启；仅当用户显式关闭时才为 false）
    var hotkeyEnabled: Bool = true {
        didSet { defaults.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled) }
    }

    /// 修饰键（NSEvent.ModifierFlags 的 rawValue），默认 ⌥
    var hotkeyModifiers: UInt = UInt(NSEvent.ModifierFlags.option.rawValue) {
        didSet { defaults.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers) }
    }

    /// 键码（默认 49 = 空格）
    var hotkeyKeyCode: UInt = 49 {
        didSet { defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode) }
    }

    /// 捕获时记录的可读按键名（如 "F"、"R"），用于更友好的展示
    var hotkeyKeyLabel: String? = nil {
        didSet { defaults.set(hotkeyKeyLabel, forKey: Keys.hotkeyKeyLabel) }
    }

    // MARK: - 翻页手势

    /// 触控板双指横扫翻页的跟手增益。
    /// 1.0 = 1:1 跟手（手指滑多少页就移多少，最自然但最费手指）；
    /// 越大 = 手指少滑一点就能跟满整页，越省力。默认 4.0。范围 1.0 ~ 8.0。
    var trackpadPagingGain: Double = 4.0 {
        didSet {
            let v = trackpadPagingGain.clamped(to: 1...8)
            if v != trackpadPagingGain { trackpadPagingGain = v }
            defaults.set(trackpadPagingGain, forKey: Keys.trackpadPagingGain)
        }
    }

    // MARK: - 开机启动

    /// 是否开机后静默自动启动（默认关闭）。开启后系统登录时自动运行 App，
    /// App 仅后台常驻，不弹出启动台也不打开设置窗口。改动会同步到系统登录项。
    var launchAtLogin: Bool = false {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            syncLaunchAtLogin()
        }
    }

    /// 把「开机自启」偏好同步到系统登录项（ServiceManagement.SMAppService.mainApp）。
    /// 失败仅记录日志，不影响 App 正常运行。
    private func syncLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin, service.status != .enabled {
                try service.register()
            } else if !launchAtLogin, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("设置开机自启失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 初始化（从 UserDefaults 载入，带默认值与范围约束）

    private init() {
        let d = UserDefaults.standard
        backgroundOverlayOpacity = d.double(forKey: Keys.backgroundOverlayOpacity).clamped(to: 0...0.8).nonZero(default: 0.10)
        backgroundStyle         = d.object(forKey: Keys.backgroundStyle) != nil
            ? ((d.integer(forKey: Keys.backgroundStyle) == 1) ? 1 : 0)
            : 1
        columnCountOverride      = max(0, d.integer(forKey: Keys.columnCountOverride))
        rowCountOverride         = max(0, d.integer(forKey: Keys.rowCountOverride))
        iconSizeOverride         = d.double(forKey: Keys.iconSizeOverride)
        horizontalSpacing        = d.double(forKey: Keys.horizontalSpacing).clamped(to: 0...60)
        verticalSpacing          = d.double(forKey: Keys.verticalSpacing).clamped(to: 0...80)
        sidePadding              = d.double(forKey: Keys.sidePadding).clamped(to: 0...200)
        topPadding               = d.double(forKey: Keys.topPadding).clamped(to: 0...200)
        bottomPadding            = d.double(forKey: Keys.bottomPadding).clamped(to: 0...200)
        // 显示目标：优先读新键；兼容旧 multiMonitorMode 的 mouse 选择
        let legacy = d.string(forKey: Keys.multiMonitorMode)
        displayTarget            = DisplayTarget(persistenceKey: d.string(forKey: Keys.displayTarget) ?? legacy)
        hotkeyEnabled            = d.object(forKey: Keys.hotkeyEnabled) != nil ? d.bool(forKey: Keys.hotkeyEnabled) : true
        hotkeyModifiers          = d.object(forKey: Keys.hotkeyModifiers) != nil
            ? UInt(d.integer(forKey: Keys.hotkeyModifiers))
            : UInt(NSEvent.ModifierFlags.option.rawValue)
        hotkeyKeyCode            = d.object(forKey: Keys.hotkeyKeyCode) != nil ? UInt(d.integer(forKey: Keys.hotkeyKeyCode)) : 49
        hotkeyKeyLabel           = d.string(forKey: Keys.hotkeyKeyLabel)
        trackpadPagingGain       = d.object(forKey: Keys.trackpadPagingGain) != nil
            ? d.double(forKey: Keys.trackpadPagingGain).clamped(to: 1...8)
            : 4.0
        launchAtLogin            = d.bool(forKey: Keys.launchAtLogin)
        isCapturingHotkey        = false
    }

    /// 由一次按键事件设置快捷键（剔除 Caps Lock 等无关修饰键）
    func setHotkey(from event: NSEvent) {
        let allowed: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let cleaned = event.modifierFlags.intersection(allowed)
        hotkeyModifiers = UInt(cleaned.rawValue)
        hotkeyKeyCode = UInt(event.keyCode)
        // 用物理键名（A-Z、空格、F1…）而非实际打出的字符（⌥C 会打出 ©，易误导以为要大写）
        hotkeyKeyLabel = Self.keyCodeToLabel(UInt(event.keyCode))
    }

    /// 恢复默认快捷键 ⌥ + 空格
    func resetHotkeyToDefault() {
        hotkeyModifiers = UInt(NSEvent.ModifierFlags.option.rawValue)
        hotkeyKeyCode = 49
        hotkeyKeyLabel = "空格"
    }

    /// 恢复默认外观：布局类参数归 0（即"自动"，由启动台按屏幕比例推算），透明度归 0.10
    func resetAppearanceToDefault() {
        columnCountOverride = 0
        rowCountOverride = 0
        iconSizeOverride = 0
        backgroundOverlayOpacity = 0.10
        backgroundStyle = 1
        horizontalSpacing = 0
        verticalSpacing = 0
        sidePadding = 0
        topPadding = 0
        bottomPadding = 0
    }

    /// 当前快捷键的可读描述，用于设置 UI 展示
    var hotkeyDescription: String {
        let mods = NSEvent.ModifierFlags(rawValue: hotkeyModifiers)
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)   { s += "⌥" }
        if mods.contains(.shift)    { s += "⇧" }
        if mods.contains(.command)  { s += "⌘" }
        if let label = hotkeyKeyLabel, !label.isEmpty { return s + label }
        return s + Self.keyName(for: hotkeyKeyCode)
    }

    /// 常见键码 → 名称（用于无 label 时的兜底展示）
    private static func keyName(for keyCode: UInt) -> String {
        switch keyCode {
        case 49:  return "空格"
        case 36:  return "回车"
        case 53:  return "Esc"
        case 48:  return "Tab"
        case 51:  return "Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:  return "键 \(keyCode)"
        }
    }

    /// macOS 虚拟键码 → 物理键名（标准 ANSI 布局表）。
    /// 注意：虚拟键码并非 0=A、1=B… 的线性序列（例如 C=8、J=38、V=9），
    /// 必须用查表方式才能得到正确的物理键名。
    private static let keyCodeToChar: [UInt: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
        45: "N", 46: "M"
    ]

    /// 由键码生成干净的物理键名，用于更友好的展示
    private static func keyCodeToLabel(_ keyCode: UInt) -> String {
        if let char = keyCodeToChar[keyCode] { return char }
        return keyName(for: keyCode)
    }

    // MARK: - Keys

    private enum Keys {
        static let backgroundOverlayOpacity = "backgroundOverlayOpacity"
        static let backgroundStyle         = "backgroundStyle"
        static let multiMonitorMode         = "multiMonitorMode"   // 旧键，仅用于兼容读取
        static let displayTarget            = "displayTarget"
        static let columnCountOverride      = "columnCountOverride"
        static let rowCountOverride         = "rowCountOverride"
        static let iconSizeOverride         = "iconSizeOverride"
        static let horizontalSpacing       = "horizontalSpacing"
        static let verticalSpacing         = "verticalSpacing"
        static let sidePadding             = "sidePadding"
        static let topPadding              = "topPadding"
        static let bottomPadding           = "bottomPadding"
        static let hotkeyEnabled            = "hotkeyEnabled"
        static let hotkeyModifiers          = "hotkeyModifiers"
        static let hotkeyKeyCode            = "hotkeyKeyCode"
        static let hotkeyKeyLabel           = "hotkeyKeyLabel"
        static let trackpadPagingGain       = "trackpadPagingGain"
        static let launchAtLogin            = "launchAtLogin"
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
    func nonZero(default value: Double) -> Double {
        self == 0 ? value : self
    }
}
