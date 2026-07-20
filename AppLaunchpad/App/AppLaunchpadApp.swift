import SwiftUI
import AppKit

/// App 入口，使用 AppDelegate 接管全部生命周期，SwiftUI 仅做桥接
@main
struct AppLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 不使用 WindowGroup，窗口完全由 AppDelegate/LaunchpadWindowController 管理
        Settings { EmptyView() }
    }
}
