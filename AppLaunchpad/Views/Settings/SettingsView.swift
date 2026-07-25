import SwiftUI
import AppKit
import ApplicationServices

// MARK: - 设置分类

enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general     = "通用"
    case appearance  = "外观"
    case interaction = "交互"
    case about       = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:     return "gearshape"
        case .appearance:  return "paintbrush"
        case .interaction: return "keyboard"
        case .about:       return "info.circle"
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
            Label("通用", systemImage: SettingsSection.general.icon)
                .tag(SettingsSection.general)
            Label("外观", systemImage: SettingsSection.appearance.icon)
                .tag(SettingsSection.appearance)
            Label("交互", systemImage: SettingsSection.interaction.icon)
                .tag(SettingsSection.interaction)
            Label("关于", systemImage: SettingsSection.about.icon)
                .tag(SettingsSection.about)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selected {
        case .general, .none:
            GeneralPane(prefs: prefs)
        case .appearance:
            AppearancePane(prefs: prefs)
        case .interaction:
            InteractionPane(prefs: prefs)
        case .about:
            AboutPane()
        }
    }
}
