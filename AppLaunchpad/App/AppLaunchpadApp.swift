import SwiftUI
import AppKit

/// App 入口，使用 AppDelegate 接管启动台生命周期，SwiftUI 原生 Window 场景承载设置窗口。
@main
struct AppLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 原生设置窗口：SwiftUI Window 场景会自动生成标准 macOS 窗口，
        // NavigationSplitView 会获得完整的系统工具栏和 sidebar toggle 按钮。
        Window("设置", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 900, height: 650)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    // Window 场景响应 showWindow: 选择器，与 Dock / 状态栏菜单统一
                    NSApp.sendAction(Selector(("showWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
