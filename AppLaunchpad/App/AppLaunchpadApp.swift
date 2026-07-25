import SwiftUI
import AppKit

/// App 入口，使用 AppDelegate 接管启动台生命周期，SwiftUI 原生 Window 场景承载设置窗口。
@main
struct AppLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 把 SwiftUI 环境的 openWindow(id:) 注入给 AppDelegate，
        // 让 Dock / 状态栏菜单（AppKit 侧）也能可靠打开设置场景。
        let _ = appDelegate.setSettingsOpener { self.openWindow(id: "settings") }

        // 原生设置窗口：SwiftUI Window 场景会自动生成标准 macOS 窗口，
        // NavigationSplitView 会获得完整的系统工具栏和 sidebar toggle 按钮。
        Window("设置", id: "settings") {
            SettingsView()
        }
        .defaultLaunchBehavior(.suppressed)   // 启动/重启不自动打开设置窗，仅 ⌘, / 菜单按需打开
        .defaultSize(width: 900, height: 650)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    // 统一走 AppDelegate.openSettings()：必要时拉起 App 到前台，
                    // 并妥善处理「窗口已开但未前置」的情况
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
