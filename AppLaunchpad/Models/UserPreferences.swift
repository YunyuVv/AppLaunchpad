import Foundation
import AppKit

/// 用户偏好设置，持久化到 UserDefaults
@Observable
final class UserPreferences: @unchecked Sendable {
    static let shared = UserPreferences()

    private let defaults = UserDefaults.standard

    // MARK: - 外观

    /// 背景遮罩透明度（0.0 ~ 0.8）
    var backgroundOverlayOpacity: Double {
        get { defaults.double(forKey: Keys.backgroundOverlayOpacity).clamped(to: 0...0.8).nonZero(default: 0.45) }
        set { defaults.set(newValue, forKey: Keys.backgroundOverlayOpacity) }
    }

    /// 每行图标列数（0 = 根据屏幕宽度自动，3~12 = 手动指定）
    var columnCountOverride: Int {
        get { defaults.integer(forKey: Keys.columnCountOverride) }  // 0 = auto
        set { defaults.set(max(0, newValue), forKey: Keys.columnCountOverride) }
    }

    /// 每页行数（0 = 根据屏幕高度自动，3~8 = 手动指定）
    var rowCountOverride: Int {
        get { defaults.integer(forKey: Keys.rowCountOverride) }  // 0 = auto
        set { defaults.set(max(0, newValue), forKey: Keys.rowCountOverride) }
    }

    /// 图标最大尺寸 pt（0 = 自动撑满网格，56~200 = 手动限制）
    var iconSizeOverride: Double {
        get { defaults.double(forKey: Keys.iconSizeOverride) }  // 0 = 自动
        set { defaults.set(newValue, forKey: Keys.iconSizeOverride) }
    }

    // MARK: - 网格布局

    /// 水平间距（0 ~ 60）
    var horizontalSpacing: Double {
        get { defaults.double(forKey: Keys.horizontalSpacing).clamped(to: 0...60).nonZero(default: 20) }
        set { defaults.set(newValue.clamped(to: 0...60), forKey: Keys.horizontalSpacing) }
    }

    /// 垂直间距（0 ~ 80）
    var verticalSpacing: Double {
        get { defaults.double(forKey: Keys.verticalSpacing).clamped(to: 0...80).nonZero(default: 28) }
        set { defaults.set(newValue.clamped(to: 0...80), forKey: Keys.verticalSpacing) }
    }

    /// 左右边距（0 ~ 200）
    var sidePadding: Double {
        get { defaults.double(forKey: Keys.sidePadding).clamped(to: 0...200).nonZero(default: 40) }
        set { defaults.set(newValue.clamped(to: 0...200), forKey: Keys.sidePadding) }
    }

    /// 顶部边距（搜索栏上方，0 ~ 200）
    var topPadding: Double {
        get { defaults.double(forKey: Keys.topPadding).clamped(to: 0...200).nonZero(default: 56) }
        set { defaults.set(newValue.clamped(to: 0...200), forKey: Keys.topPadding) }
    }

    /// 底部边距（分页指示器下方，0 ~ 200）
    var bottomPadding: Double {
        get { defaults.double(forKey: Keys.bottomPadding).clamped(to: 0...200).nonZero(default: 46) }
        set { defaults.set(newValue.clamped(to: 0...200), forKey: Keys.bottomPadding) }
    }

    // MARK: - 多显示器

    enum MultiMonitorMode: String, CaseIterable {
        case primaryScreen = "primary"
        case mouseScreen   = "mouse"

        var label: String {
            switch self {
            case .primaryScreen: return "主显示器"
            case .mouseScreen:   return "鼠标所在显示器"
            }
        }
    }

    var multiMonitorMode: MultiMonitorMode {
        get {
            let raw = defaults.string(forKey: Keys.multiMonitorMode) ?? ""
            return MultiMonitorMode(rawValue: raw) ?? .primaryScreen
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.multiMonitorMode) }
    }

    // MARK: - 全局快捷键

    /// 录制期间临时标记，全局监听看到它会跳过触发（避免录制时误呼出）
    var isCapturingHotkey: Bool = false

    /// 是否启用全局快捷键呼出启动台（默认开启；仅当用户显式关闭时才为 false）
    var hotkeyEnabled: Bool {
        get {
            guard defaults.object(forKey: Keys.hotkeyEnabled) != nil else { return true }
            return defaults.bool(forKey: Keys.hotkeyEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.hotkeyEnabled) }
    }

    /// 修饰键（NSEvent.ModifierFlags 的 rawValue），默认 ⌥
    var hotkeyModifiers: UInt {
        get {
            guard defaults.object(forKey: Keys.hotkeyModifiers) != nil else {
                return UInt(NSEvent.ModifierFlags.option.rawValue)
            }
            return UInt(defaults.integer(forKey: Keys.hotkeyModifiers))
        }
        set { defaults.set(Int(newValue), forKey: Keys.hotkeyModifiers) }
    }

    /// 键码（默认 49 = 空格）
    var hotkeyKeyCode: UInt {
        get {
            guard defaults.object(forKey: Keys.hotkeyKeyCode) != nil else { return 49 }
            return UInt(defaults.integer(forKey: Keys.hotkeyKeyCode))
        }
        set { defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode) }
    }

    /// 捕获时记录的可读按键名（如 "F"、"R"），用于更友好的展示
    var hotkeyKeyLabel: String? {
        get { defaults.string(forKey: Keys.hotkeyKeyLabel) }
        set { defaults.set(newValue, forKey: Keys.hotkeyKeyLabel) }
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

    /// 由键码生成干净的物理键名：美式键盘 0-25 对应 A-Z；其余走 keyName 兜底
    private static func keyCodeToLabel(_ keyCode: UInt) -> String {
        if keyCode <= 25 {
            let base = Int(("A" as Character).asciiValue ?? 65)
            if let scalar = UnicodeScalar(base + Int(keyCode)) {
                return String(Character(scalar))
            }
        }
        return keyName(for: keyCode)
    }

    // MARK: - Keys

    private enum Keys {
        static let backgroundOverlayOpacity = "backgroundOverlayOpacity"
        static let multiMonitorMode         = "multiMonitorMode"
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
