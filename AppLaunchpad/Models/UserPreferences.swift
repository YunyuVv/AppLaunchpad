import Foundation

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

    // MARK: - Keys

    private enum Keys {
        static let backgroundOverlayOpacity = "backgroundOverlayOpacity"
        static let multiMonitorMode         = "multiMonitorMode"
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
