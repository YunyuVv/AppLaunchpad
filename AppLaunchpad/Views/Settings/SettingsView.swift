import SwiftUI
import AppKit
import ApplicationServices

// MARK: - 设置分类

enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case appearance = "外观"
    case display    = "显示器"
    case hotkey     = "快捷键"
    case about      = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .display:    return "display"
        case .hotkey:     return "command"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - 原生设置窗口（⌘, / App 菜单 Settings... 打开）
// 使用 NavigationSplitView，由 SwiftUI Settings 场景托管窗口，
// 系统会自动生成标题栏、工具栏和 sidebar toggle 按钮。

struct SettingsView: View {
    var body: some View {
        SettingsNavigationContent()
            .frame(minWidth: 820, idealWidth: 900, minHeight: 600, idealHeight: 650)
    }
}

struct SettingsNavigationContent: View {
    @Bindable private var prefs = UserPreferences.shared
    @State private var selected: SettingsSection? = .appearance
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationTitle("设置")
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detailPane
                .navigationTitle(navigationTitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var navigationTitle: String {
        selected?.rawValue ?? "设置"
    }

    private var sidebar: some View {
        List(selection: $selected) {
            Section("常规") {
                Label("外观", systemImage: SettingsSection.appearance.icon)
                    .tag(SettingsSection.appearance)
                Label("显示器", systemImage: SettingsSection.display.icon)
                    .tag(SettingsSection.display)
            }

            Section("高级") {
                Label("快捷键", systemImage: SettingsSection.hotkey.icon)
                    .tag(SettingsSection.hotkey)
                Label("关于", systemImage: SettingsSection.about.icon)
                    .tag(SettingsSection.about)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selected {
        case .appearance, .none:
            AppearancePane(prefs: prefs)
        case .display:
            DisplayPane(prefs: prefs)
        case .hotkey:
            HotkeyPane(prefs: prefs)
        case .about:
            AboutPane()
        }
    }
}
