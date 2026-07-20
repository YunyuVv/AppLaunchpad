# Phase 1 开发日志 — 基础骨架

**完成日期**: 2026-07-20  
**对应计划**: `docs/superpowers/plans/2026-07-20-phase1-foundation.md`  
**状态**: ✅ 完成

---

## 一、交付内容

### 新增文件

| 文件 | 说明 |
|-----|------|
| `project.yml` | XcodeGen 工程配置，macOS 26、非沙盒、Swift 6、Hardened Runtime |
| `AppLaunchpad/AppLaunchpad.entitlements` | 关闭沙盒，允许 Apple Events |
| `AppLaunchpad/Info.plist` | Bundle ID: `com.applaunchpad.app` |
| `App/AppLaunchpadApp.swift` | SwiftUI `@main` 入口，桥接 AppDelegate |
| `App/AppDelegate.swift` | 生命周期管理、菜单栏图标、全局快捷键入口 |
| `Models/AppInfo.swift` | 应用数据模型（id/bundleID/displayName/url/isMASApp） |
| `Models/LayoutData.swift` | 分页布局模型（LayoutItem 枚举、LayoutData 结构体） |
| `Services/AppScanner.swift` | 异步扫描 `/Applications`、`~/Applications`、`/System/Applications` |
| `Services/IconCache.swift` | actor 图标内存缓存，NSCache 限制 50MB |
| `ViewModel/LaunchpadViewModel.swift` | `@Observable @MainActor` 全局状态机 |
| `Views/BackgroundView.swift` | 壁纸读取 + CIGaussianBlur 模糊，降级到 NSVisualEffectView |
| `Views/AppIconView.swift` | 图标 + 应用名，hover 放大 scale(1.08) |
| `Views/GridPageView.swift` | LazyVGrid 单页网格，列数自适应屏幕宽度 |
| `Views/LaunchpadView.swift` | 全屏根视图，空白区域关闭 |
| `Window/LaunchpadWindowController.swift` | NSPanel 全屏窗口管理 |

---

## 二、关键技术决策

### 2.1 工程生成：XcodeGen
- 不手动维护 `.xcodeproj`，所有配置在 `project.yml` 中声明
- 每次新增源文件后执行 `xcodegen generate` 重新生成工程
- 命令：`xcodegen generate`

### 2.2 非沙盒 + Hardened Runtime
- 需要访问 `/Applications`、注册全局快捷键，沙盒均不支持
- `com.apple.security.app-sandbox = false`
- `ENABLE_HARDENED_RUNTIME = YES`

### 2.3 Swift 6 并发处理
- `AppScanner` 使用 `actor` + `Task.detached`，将 `NSDirectoryEnumerator` 的同步遍历移出 async 上下文（Swift 6 中 NSDirectoryEnumerator 不可在 async 上下文直接迭代）
- 所有 UI 更新通过 `@MainActor` 保证线程安全

### 2.4 应用入口：activationPolicy
- 默认 `.accessory`：不出现在 Cmd+Tab，Dock 无额外图标
- 呼出时切换为 `.regular` 使 NSPanel 能接收键盘事件
- 关闭后恢复 `.accessory`

---

## 三、修复记录

### Bug 1：全局快捷键 Cmd+L 无响应
**原因**：`NSEvent.addGlobalMonitorForEvents` 需要辅助功能权限，未授权静默失效。  
**修复**：改用菜单栏图标（`NSStatusItem`）作为触发入口，不需要任何权限。

### Bug 2：点击菜单栏图标窗口不弹出
**原因**：`NSApp.setActivationPolicy(.regular)` + `makeKeyAndOrderFront` 同步调用时序问题。  
**修复**：改用 `orderFrontRegardless()` + `makeKeyAndOrderFront(nil)` + 同步 `NSApp.activate(ignoringOtherApps: true)`。

### Bug 3：Escape 和点击空白无法关闭
**原因 A**：`.nonactivatingPanel` 导致点击后 panel 失去 key 状态，`NSEvent.addLocalMonitorForEvents` 收不到键盘事件。  
**修复 A**：移除 `.nonactivatingPanel`，panel 正常成为 key window。  
**原因 B**：`LaunchpadView.onTapGesture` 直接调用 `viewModel.hide()` 只改 ViewModel 状态，`panel.orderOut(nil)` 从未执行，面板实际不消失。  
**修复 B**：引入 `onDismiss: () -> Void` 闭包，由 `LaunchpadWindowController` 注入，确保点击空白时调用 `hide()` 完整流程（`panel.orderOut` + `viewModel.hide` + 恢复 `.accessory`）。

---

## 四、验收结果

- [x] 菜单栏图标点击呼出全屏界面
- [x] 壁纸虚化背景正常显示
- [x] 图标网格展示本机所有 App（/Applications + ~/Applications + /System/Applications）
- [x] 点击图标成功启动对应应用，面板关闭
- [x] Escape 键关闭面板
- [x] 点击空白区域关闭面板
- [x] 菜单栏图标再次点击关闭面板

---

## 五、已知问题 / 遗留事项

- 菜单栏图标为临时方案，Phase 3 替换为 F4 全局快捷键 + Dock 图标
- 当前无呼出/关闭动画（Phase 2 添加）
- 无搜索、无翻页（Phase 2 添加）
- 控制台有 `com.apple.linkd.autoShortcut` 报错，属系统级非致命日志，可忽略
