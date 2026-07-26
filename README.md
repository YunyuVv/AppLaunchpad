# AppLaunchpad

macOS 启动台（Launchpad）的替代应用——全屏网格展示本机应用，支持搜索、拖拽重排、文件夹分组、外观主题切换，并通过**菜单栏图标 + 全局快捷键**后台常驻唤起。

> 中文名 / 显示名：AppLaunchpad
> 最低系统：macOS 26.0
> 开发语言：Swift 6（严格并发）

---

## ✨ 主要功能

- **全局唤起**：默认快捷键 `⌥ + Space` 一键显示 / 隐藏；也可点菜单栏图标或 Dock 图标切换。
- **全屏覆盖**：以高于 Dock / 菜单栏的层级全屏覆盖，沉浸浏览本机所有应用。
- **应用网格**：自动扫描 `/Applications`、用户 `Applications`、`/System/Applications`，中文应用名正确显示。
- **搜索**：模糊搜索（支持拼音 / 子序列匹配），搜索框焦点管理避免输入法分裂。
- **拖拽重排**：拖拽整理图标、make-way 让位动画、跨页拖动、边缘自动翻页。
- **文件夹**：拖 App 到 App 上即可建组，文件夹内可重命名、增删。
- **多显示器**：可选在主显示器 / 鼠标所在显示器 / 指定显示器展示。
- **外观主题**：磨砂背景与液态玻璃背景二选一。
- **右键菜单**：打开 / 在访达中显示 / 删除（删除进废纸篓并保留「放回」）。
- **后台常驻**：关窗不退出，仅 `⌘Q` / 菜单栏退出。

---

## 🧰 环境要求

- macOS 26.0 及以上
- Xcode 26（含 macOS 26 SDK）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（用 `project.yml` 生成 Xcode 工程）

---

## 🔨 构建与运行

```bash
# 1. 由 project.yml 生成 Xcode 工程
xcodegen generate

# 2. 打开并运行（或在 Xcode 中 ⌘R）
open AppLaunchpad.xcodeproj
```

> 工程使用 **Manual 签名**（Apple Development 证书 + Team `2VU69Q9CGK`）。
> 若你用自己的开发者账号构建，请在 Xcode 的 Signing 设置中改为你自己的团队 / 证书。

---

## 🔐 首次使用授权

由于全局快捷键依赖系统级事件监听，首次运行后需在 **系统设置 → 隐私与安全性 → 辅助功能** 中，为 AppLaunchpad 开启权限，否则快捷键无法全局生效。

---

## 📄 许可证

本项目采用 **非商业使用许可协议**（见 [`LICENSE`](./LICENSE)）：

- ✅ 可免费用于**非商业**目的：使用、学习、修改、以免费方式分发（含源码与二进制）。
- ❌ **禁止商业使用**：任何营利性 / 收费场景均需著作权人**事先书面授权**。
- 分发时须保留原始著作权声明与本协议。

如需商业授权，请按 `LICENSE` 文末的联系方式联系作者。

---

## 📁 目录结构

| 路径 | 说明 |
|---|---|
| `AppLaunchpad/` | 应用源码（Swift / SwiftUI） |
| `project.yml` | XcodeGen 工程描述 |
| `logo/` | 应用图标与品牌资源 |
| `docs/` | 产品文档 / 开发指南 / 待办事项 |
| `references/` | 第三方参考实现（LaunchNext） |
| `scripts/` | 构建 / 发布脚本 |


# 社区
https://linux.do
