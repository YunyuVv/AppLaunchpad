# Phase 1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭建 AppLaunchpad macOS 应用基础骨架：工程配置 + 应用扫描 + 全屏图标网格展示 + 点击启动应用。

**Architecture:** 采用 MVVM + AppKit/SwiftUI 混合架构。AppDelegate 管理生命周期和 NSPanel 全屏窗口，LaunchpadViewModel（@Observable）作为单一数据源，SwiftUI 视图层响应状态变化。AppScanner 异步扫描应用目录，IconCache 懒加载图标。

**Tech Stack:** Swift 6.2 · SwiftUI · AppKit · XcodeGen 2.46 · macOS 26+ · Xcode 26.2

## Global Constraints

- 最低部署目标：macOS 26.0
- Swift Concurrency：全面使用 async/await，UI 更新必须在 @MainActor
- 不启用沙盒（App Sandbox = false）
- Bundle ID：com.applaunchpad.app
- 项目根目录：/Users/wangpenglong/projects/swift/macos/AppLaunchpad
- 源码目录：AppLaunchpad/（位于项目根目录下）
- 不使用第三方依赖

---

## Task 1：XcodeGen 工程配置

**Files:**
- Create: `project.yml`
- Create: `AppLaunchpad/AppLaunchpad.entitlements`
- Create: `AppLaunchpad/Info.plist`

**Interfaces:**
- Produces: 可执行的 .xcodeproj，后续所有 Swift 文件均在此工程内编译

- [ ] **Step 1: 创建 project.yml**

```yaml
# project.yml
name: AppLaunchpad
options:
  bundleIdPrefix: com.applaunchpad
  deploymentTarget:
    macOS: "26.0"
  xcodeVersion: "16.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: 6.0
    MACOSX_DEPLOYMENT_TARGET: "26.0"
    ENABLE_HARDENED_RUNTIME: YES
    CODE_SIGN_STYLE: Automatic
    PRODUCT_BUNDLE_IDENTIFIER: com.applaunchpad.app

targets:
  AppLaunchpad:
    type: application
    platform: macOS
    deploymentTarget: "26.0"
    sources:
      - AppLaunchpad
    settings:
      base:
        INFOPLIST_FILE: AppLaunchpad/Info.plist
        CODE_SIGN_ENTITLEMENTS: AppLaunchpad/AppLaunchpad.entitlements
        PRODUCT_NAME: AppLaunchpad
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    entitlements:
      path: AppLaunchpad/AppLaunchpad.entitlements
```

- [ ] **Step 2: 创建 entitlements 文件**

```xml
<!-- AppLaunchpad/AppLaunchpad.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: 创建 Info.plist**

```xml
<!-- AppLaunchpad/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>AppLaunchpad</string>
    <key>CFBundleIdentifier</key>
    <string>com.applaunchpad.app</string>
    <key>CFBundleName</key>
    <string>AppLaunchpad</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMainNibFile</key>
    <string></string>
    <key>LSUIElement</key>
    <false/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 AppLaunchpad. All rights reserved.</string>
</dict>
</plist>
```

- [ ] **Step 4: 生成 .xcodeproj**

```bash
cd /Users/wangpenglong/projects/swift/macos/AppLaunchpad
xcodegen generate
```

预期输出：`✨  Generated: AppLaunchpad.xcodeproj`

- [ ] **Step 5: 验证工程可编译（暂无源文件，会报错，正常）**

```bash
xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD|warning:" | head -20
```

预期：报 "no files" 类型错误，不报配置错误即为通过。

- [ ] **Step 6: 提交**

```bash
git add project.yml AppLaunchpad/AppLaunchpad.entitlements AppLaunchpad/Info.plist AppLaunchpad.xcodeproj
git commit -m "chore: 初始化 XcodeGen 工程配置"
```

---

## Task 2：App 入口与 AppDelegate

**Files:**
- Create: `AppLaunchpad/App/AppLaunchpadApp.swift`
- Create: `AppLaunchpad/App/AppDelegate.swift`

**Interfaces:**
- Produces:
  - `AppDelegate` 类，实现 `NSApplicationDelegate`
  - `applicationDidFinishLaunching(_:)` 方法
  - `toggle()` 方法（供后续快捷键/Dock 调用）

- [ ] **Step 1: 创建 App 入口**

```swift
// AppLaunchpad/App/AppLaunchpadApp.swift
import SwiftUI
import AppKit

/// App 入口，使用 AppDelegate 接管生命周期
@main
struct AppLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 不使用 WindowGroup，窗口完全由 AppDelegate 管理
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 2: 创建 AppDelegate**

```swift
// AppLaunchpad/App/AppDelegate.swift
import AppKit
import SwiftUI

/// 管理 App 生命周期、Dock 图标点击响应和窗口显示/隐藏
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    var windowController: LaunchpadWindowController?
    var viewModel: LaunchpadViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 后台应用模式：不出现在 Cmd+Tab，仅显示 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        let vm = LaunchpadViewModel()
        self.viewModel = vm
        self.windowController = LaunchpadWindowController(viewModel: vm)

        // 异步扫描应用
        Task {
            await vm.loadApps()
        }
    }

    /// Dock 图标点击 / 再次激活时切换显示
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        toggle()
        return false
    }

    func toggle() {
        guard let wc = windowController else { return }
        if wc.isVisible {
            wc.hide()
        } else {
            wc.show()
        }
    }
}
```

- [ ] **Step 3: 编译验证（此时 LaunchpadWindowController、LaunchpadViewModel 尚未创建，预期报错）**

```bash
xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad -destination 'platform=macOS' build 2>&1 | grep "error:" | head -10
```

预期：报 `cannot find type 'LaunchpadWindowController'` 和 `'LaunchpadViewModel'`，这是正常的，说明结构正确。

- [ ] **Step 4: 提交**

```bash
git add AppLaunchpad/App/
git commit -m "feat: App 入口与 AppDelegate 骨架"
```

---

## Task 3：数据模型

**Files:**
- Create: `AppLaunchpad/Models/AppInfo.swift`
- Create: `AppLaunchpad/Models/LayoutData.swift`

**Interfaces:**
- Produces:
  - `struct AppInfo: Identifiable, Hashable, Sendable` — 字段：id(String), bundleID, displayName, url(URL), isMASApp(Bool)
  - `enum LayoutItem: Hashable, Codable` — `.app(bundleID: String)` | `.folder(id: UUID)`
  - `struct LayoutData: Codable` — `pages: [[LayoutItem]]`, `version: Int`

- [ ] **Step 1: 创建 AppInfo**

```swift
// AppLaunchpad/Models/AppInfo.swift
import Foundation

/// 单个已安装应用的信息，扫描后不可变
struct AppInfo: Identifiable, Hashable, Sendable {
    /// 使用 bundleID 作为唯一标识，路径可能变化但 bundleID 稳定
    let id: String
    let bundleID: String
    let displayName: String
    let url: URL
    let isMASApp: Bool

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
```

- [ ] **Step 2: 创建 LayoutData**

```swift
// AppLaunchpad/Models/LayoutData.swift
import Foundation

/// 网格槽位的内容：应用或文件夹
enum LayoutItem: Hashable, Codable {
    case app(bundleID: String)
    case folder(id: UUID)
}

/// 所有页面的图标排列，支持持久化
struct LayoutData: Codable {
    /// pages[pageIndex][slotIndex] = LayoutItem，从左到右、从上到下排列
    var pages: [[LayoutItem]]
    var version: Int = 1

    init(pages: [[LayoutItem]] = []) {
        self.pages = pages
    }

    /// 将应用列表按每页容量分页，生成初始布局
    static func initial(from apps: [AppInfo], itemsPerPage: Int) -> LayoutData {
        let items = apps.map { LayoutItem.app(bundleID: $0.bundleID) }
        let pages = stride(from: 0, to: items.count, by: itemsPerPage).map {
            Array(items[$0..<min($0 + itemsPerPage, items.count)])
        }
        return LayoutData(pages: pages)
    }
}
```

- [ ] **Step 3: 提交**

```bash
git add AppLaunchpad/Models/
git commit -m "feat: AppInfo 和 LayoutData 数据模型"
```

---

## Task 4：图标缓存服务

**Files:**
- Create: `AppLaunchpad/Services/IconCache.swift`

**Interfaces:**
- Consumes: `AppInfo.url: URL`
- Produces:
  - `actor IconCache` 单例
  - `func icon(for app: AppInfo) async -> NSImage`：返回应用图标，未命中时异步加载并缓存

- [ ] **Step 1: 创建 IconCache**

```swift
// AppLaunchpad/Services/IconCache.swift
import AppKit

/// 应用图标内存缓存，actor 保证并发安全
actor IconCache {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        // 限制缓存总大小 50MB
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    /// 获取图标，缓存命中直接返回，未命中后台加载后写入缓存
    func icon(for app: AppInfo) async -> NSImage {
        let key = app.bundleID as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        // 在后台线程加载图标
        let image = await Task.detached(priority: .utility) {
            NSWorkspace.shared.icon(forFile: app.url.path)
        }.value
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 清空全部缓存（用于内存警告时）
    func clearAll() {
        cache.removeAllObjects()
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add AppLaunchpad/Services/IconCache.swift
git commit -m "feat: IconCache 图标懒加载缓存服务"
```

---

## Task 5：应用扫描服务

**Files:**
- Create: `AppLaunchpad/Services/AppScanner.swift`

**Interfaces:**
- Produces:
  - `actor AppScanner`
  - `func scan() async -> [AppInfo]`：扫描全部应用目录，返回去重后的应用列表

- [ ] **Step 1: 创建 AppScanner**

```swift
// AppLaunchpad/Services/AppScanner.swift
import AppKit
import Foundation

/// 异步扫描 macOS 应用目录，过滤后台/系统内部应用
actor AppScanner {
    static let shared = AppScanner()

    /// 扫描路径优先级顺序
    private let scanPaths: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
    ]

    /// 扫描所有路径，返回去重排序的应用列表
    func scan() async -> [AppInfo] {
        var seen = Set<String>()
        var result: [AppInfo] = []

        for baseURL in scanPaths {
            let apps = await scanDirectory(baseURL)
            for app in apps {
                if seen.insert(app.bundleID).inserted {
                    result.append(app)
                }
            }
        }

        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Private

    private func scanDirectory(_ url: URL) async -> [AppInfo] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var apps: [AppInfo] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "app" else { continue }
            if let app = makeAppInfo(from: fileURL) {
                apps.append(app)
            }
            // 跳过 .app 包内部，不继续递归
            enumerator.skipDescendants()
        }
        return apps
    }

    private func makeAppInfo(from url: URL) -> AppInfo? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL),
              let bundleID = plist["CFBundleIdentifier"] as? String,
              !bundleID.isEmpty else { return nil }

        // 过滤纯后台应用
        if let backgroundOnly = plist["LSBackgroundOnly"] as? Bool, backgroundOnly { return nil }
        if let uiElement = plist["LSUIElement"] as? Bool, uiElement { return nil }
        // 兼容字符串 "1" 的写法
        if let uiElementStr = plist["LSUIElement"] as? String, uiElementStr == "1" { return nil }

        let displayName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let isMASApp = FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Contents/_MASReceipt").path
        )

        return AppInfo(
            id: bundleID,
            bundleID: bundleID,
            displayName: displayName,
            url: url,
            isMASApp: isMASApp
        )
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add AppLaunchpad/Services/AppScanner.swift
git commit -m "feat: AppScanner 异步应用扫描服务"
```

---

## Task 6：LaunchpadViewModel

**Files:**
- Create: `AppLaunchpad/ViewModel/LaunchpadViewModel.swift`

**Interfaces:**
- Consumes: `AppScanner.shared.scan() async -> [AppInfo]`、`IconCache.shared`
- Produces:
  - `@Observable @MainActor final class LaunchpadViewModel`
  - `var allApps: [AppInfo]`
  - `var layout: LayoutData`
  - `var isVisible: Bool`
  - `var currentPageIndex: Int`
  - `var searchText: String`
  - `func loadApps() async`
  - `func launch(_ app: AppInfo)`
  - `func show()` / `func hide()`
  - `var searchResults: [AppInfo]`（计算属性）
  - `var totalPages: Int`（计算属性）
  - `func columnCount(for screen: NSScreen) -> Int`
  - `var itemsPerPage: Int`

- [ ] **Step 1: 创建 LaunchpadViewModel**

```swift
// AppLaunchpad/ViewModel/LaunchpadViewModel.swift
import AppKit
import Observation

/// 启动台全局状态管理，所有 UI 状态的单一数据源
@Observable
@MainActor
final class LaunchpadViewModel {

    // MARK: - 核心数据

    /// 全部已扫描应用
    var allApps: [AppInfo] = []
    /// 当前图标布局
    var layout: LayoutData = LayoutData()

    // MARK: - UI 状态

    /// 启动台窗口是否可见
    var isVisible: Bool = false
    /// 当前显示页（0-based）
    var currentPageIndex: Int = 0
    /// 搜索关键词
    var searchText: String = ""
    /// 是否处于图标编辑模式
    var isEditMode: Bool = false

    // MARK: - 计算属性

    /// 根据屏幕宽度计算每行列数
    func columnCount(for screen: NSScreen) -> Int {
        switch screen.frame.width {
        case 1440...: return 7
        case 1280..<1440: return 6
        default: return 5
        }
    }

    /// 每页图标容量（5行）
    var itemsPerPage: Int {
        columnCount(for: NSScreen.main ?? NSScreen.screens[0]) * 5
    }

    /// 总页数
    var totalPages: Int { layout.pages.count }

    /// 搜索结果（前缀匹配优先）
    var searchResults: [AppInfo] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return allApps
            .filter {
                $0.displayName.lowercased().contains(query) ||
                $0.bundleID.lowercased().contains(query)
            }
            .sorted {
                let ap = $0.displayName.lowercased().hasPrefix(query)
                let bp = $1.displayName.lowercased().hasPrefix(query)
                if ap != bp { return ap }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    var isSearching: Bool { !searchText.isEmpty }

    // MARK: - Actions

    /// 扫描应用并初始化布局
    func loadApps() async {
        let scanned = await AppScanner.shared.scan()
        allApps = scanned
        layout = LayoutData.initial(from: scanned, itemsPerPage: itemsPerPage)
    }

    /// 启动应用并关闭启动台
    func launch(_ app: AppInfo) {
        hide()
        NSWorkspace.shared.open(app.url)
    }

    func show() { isVisible = true }
    func hide() {
        isVisible = false
        isEditMode = false
        searchText = ""
        currentPageIndex = 0
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add AppLaunchpad/ViewModel/LaunchpadViewModel.swift
git commit -m "feat: LaunchpadViewModel 状态管理核心"
```

---

## Task 7：NSPanel 全屏窗口控制器

**Files:**
- Create: `AppLaunchpad/Window/LaunchpadWindowController.swift`

**Interfaces:**
- Consumes: `LaunchpadViewModel.isVisible`、`LaunchpadViewModel.show()`/`hide()`
- Produces:
  - `final class LaunchpadWindowController`
  - `init(viewModel: LaunchpadViewModel)`
  - `var isVisible: Bool`
  - `func show()` / `func hide()`

- [ ] **Step 1: 创建窗口控制器**

```swift
// AppLaunchpad/Window/LaunchpadWindowController.swift
import AppKit
import SwiftUI

/// 管理覆盖全屏的 NSPanel，承载 SwiftUI 启动台界面
@MainActor
final class LaunchpadWindowController {

    private var panel: NSPanel?
    private let viewModel: LaunchpadViewModel

    var isVisible: Bool { panel?.isVisible ?? false }

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        // 切换为普通应用激活策略，使 panel 能接收键盘事件
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        panel.makeKeyAndOrderFront(nil)
        viewModel.show()
    }

    func hide() {
        panel?.orderOut(nil)
        viewModel.hide()
        // 恢复后台模式
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let p = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 覆盖在几乎所有窗口之上（screensaver 级别 - 1）
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false

        let rootView = LaunchpadView(viewModel: viewModel)
            .onExitCommand {           // Escape 键关闭
                Task { @MainActor in self.hide() }
            }
        p.contentView = NSHostingView(rootView: rootView)
        return p
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add AppLaunchpad/Window/LaunchpadWindowController.swift
git commit -m "feat: NSPanel 全屏窗口控制器"
```

---

## Task 8：SwiftUI 视图层

**Files:**
- Create: `AppLaunchpad/Views/BackgroundView.swift`
- Create: `AppLaunchpad/Views/AppIconView.swift`
- Create: `AppLaunchpad/Views/GridPageView.swift`
- Create: `AppLaunchpad/Views/LaunchpadView.swift`

**Interfaces:**
- Consumes:
  - `LaunchpadViewModel.allApps`、`.layout`、`.isVisible`、`.currentPageIndex`
  - `LaunchpadViewModel.launch(_:)`
  - `IconCache.shared.icon(for:) async -> NSImage`
- Produces: 完整可渲染的 SwiftUI 视图树

- [ ] **Step 1: 创建背景视图**

```swift
// AppLaunchpad/Views/BackgroundView.swift
import SwiftUI
import AppKit

/// 虚化壁纸背景，降级时使用 NSVisualEffectView
struct BackgroundView: View {
    @State private var wallpaperImage: NSImage? = nil

    var body: some View {
        ZStack {
            if let img = wallpaperImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                // 降级：系统材质模糊
                VisualEffectBlur()
                    .ignoresSafeArea()
            }
            // 半透明暗色遮罩
            Color.black.opacity(0.35)
                .ignoresSafeArea()
        }
        .task {
            wallpaperImage = await loadBlurredWallpaper()
        }
    }

    private func loadBlurredWallpaper() async -> NSImage? {
        guard let screen = NSScreen.main,
              let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen),
              let ciImage = CIImage(contentsOf: wallpaperURL) else { return nil }

        return await Task.detached(priority: .utility) {
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ciImage
            filter.radius = 20
            guard let output = filter.outputImage else { return nil }
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(output, from: ciImage.extent) else { return nil }
            return NSImage(cgImage: cg, size: screen.frame.size)
        }.value
    }
}

/// AppKit NSVisualEffectView 包装，作为背景降级方案
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
```

- [ ] **Step 2: 创建应用图标视图**

```swift
// AppLaunchpad/Views/AppIconView.swift
import SwiftUI
import AppKit

/// 单个应用图标：显示图标图片 + 应用名称，支持 hover 放大和点击启动
struct AppIconView: View {
    let app: AppInfo
    let onTap: () -> Void

    @State private var icon: NSImage? = nil
    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                    } else {
                        // 加载中占位
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.15))
                    }
                }
                .frame(width: 80, height: 80)
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovering)

                Text(app.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .task {
            icon = await IconCache.shared.icon(for: app)
        }
    }
}
```

- [ ] **Step 3: 创建单页网格视图**

```swift
// AppLaunchpad/Views/GridPageView.swift
import SwiftUI

/// 单页图标网格（LazyVGrid），最多5行×N列
struct GridPageView: View {
    let items: [LayoutItem]
    let apps: [AppInfo]       // 完整应用表，用于 bundleID 查找
    let columns: Int
    let onTapApp: (AppInfo) -> Void

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(100), spacing: 20), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 30) {
            ForEach(items, id: \.self) { item in
                switch item {
                case .app(let bundleID):
                    if let app = apps.first(where: { $0.bundleID == bundleID }) {
                        AppIconView(app: app, onTap: { onTapApp(app) })
                    }
                case .folder:
                    // 文件夹在后续 Phase 5 实现，此处占位
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 60)
    }
}
```

- [ ] **Step 4: 创建根视图**

```swift
// AppLaunchpad/Views/LaunchpadView.swift
import SwiftUI

/// 启动台全屏根视图：背景 + 搜索框占位 + 当前页网格 + 页码指示器占位
struct LaunchpadView: View {
    @Bindable var viewModel: LaunchpadViewModel

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    var body: some View {
        ZStack {
            // 背景层
            BackgroundView()

            VStack(spacing: 0) {
                // 搜索框预留位（Phase 2 实现）
                Spacer().frame(height: 80)

                // 当前页内容
                if viewModel.allApps.isEmpty {
                    loadingView
                } else {
                    currentPageView
                }

                Spacer()

                // 页码指示器预留位（Phase 2 实现）
                Spacer().frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(1.5)
            .tint(.white)
    }

    private var currentPageView: some View {
        let cols = viewModel.columnCount(for: screen)
        let pageItems: [LayoutItem]
        if viewModel.currentPageIndex < viewModel.layout.pages.count {
            pageItems = viewModel.layout.pages[viewModel.currentPageIndex]
        } else {
            pageItems = []
        }

        return GridPageView(
            items: pageItems,
            apps: viewModel.allApps,
            columns: cols,
            onTapApp: { viewModel.launch($0) }
        )
    }
}
```

- [ ] **Step 5: 编译验证**

```bash
cd /Users/wangpenglong/projects/swift/macos/AppLaunchpad
xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad \
  -destination 'platform=macOS' build 2>&1 | grep -E "^.*error:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 6: 提交**

```bash
git add AppLaunchpad/Views/
git commit -m "feat: SwiftUI 视图层 - 背景、图标、网格、根视图"
```

---

## Task 9：组装验收

**Files:**
- Modify: `AppLaunchpad/App/AppDelegate.swift`（添加键盘监听）

**Interfaces:**
- 无新接口，整合前8个 Task 的所有模块

- [ ] **Step 1: 添加临时快捷键触发（F4 / Cmd+Space 占位）**

在 `AppDelegate.applicationDidFinishLaunching` 中添加：

```swift
// 临时：监听 Cmd+L 打开启动台（F4 在 Task 3-2 实现）
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
    // keyCode 37 = L，仅用于 Phase 1 测试
    if event.modifierFlags.contains(.command) && event.keyCode == 37 {
        Task { @MainActor in self?.toggle() }
    }
}
```

- [ ] **Step 2: 完整编译并运行**

```bash
xcodebuild -project AppLaunchpad.xcodeproj -scheme AppLaunchpad \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

用 Xcode 运行并按 Cmd+L 验证：
- [ ] 全屏窗口弹出，覆盖在其他窗口上方
- [ ] 背景显示为壁纸模糊效果
- [ ] 图标网格正确展示本机所有 App
- [ ] 点击任意图标成功启动该应用，窗口关闭
- [ ] 再次按 Cmd+L 窗口重新打开
- [ ] 扫描到的应用数量 ≥ 20 个（用 Xcode 控制台打印 `allApps.count` 验证）

- [ ] **Step 3: 最终提交**

```bash
git add -A
git commit -m "feat: Phase 1 完成 - 基础骨架可运行"
```

---

## Self-Review Checklist

- [x] PRD §3.3 应用扫描：Task 5 覆盖，扫描三个目录，过滤后台应用
- [x] PRD §3.2 图标网格展示：Task 8 覆盖，LazyVGrid 自适应列数
- [x] PRD §3.8 点击启动应用：AppIconView.onTap → viewModel.launch()
- [x] PRD §3.2 背景虚化：BackgroundView + CIGaussianBlur，降级到 NSVisualEffectView
- [x] 所有文件路径精确，无占位符
- [x] 完整代码在每个步骤中给出
- [x] Swift 6.0 Concurrency：actor、@MainActor、async/await 一致使用
- [x] 每个 Task 有独立 git commit
