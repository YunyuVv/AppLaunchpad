import SwiftUI
import AppKit

/// App 入口，使用 AppDelegate 接管全部生命周期，SwiftUI 仅做桥接
@main
struct AppLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Cmd+, 打开设置页面
        Settings {
            SettingsView()
        }
    }
}
