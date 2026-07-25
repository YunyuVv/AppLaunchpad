# AppLaunchpad 发版流程（AI Runbook）

> 本文档供 AI（后续维护者/智能体）照做：升级版本号 + 触发 GitHub 云端打包未签名 DMG。
> 路径以本仓库根目录 `/Users/wangpenglong/projects/swift/macos/AppLaunchpad` 为基准。
> 文档所在目录：`scripts/release/`。

---

## 0. 一句话结论

**版本真源只有一个文件**：`AppLaunchpad/AppLaunchpad/Info.plist`（注意是两层同名 `AppLaunchpad/`）。
发版只跑一条命令：

```bash
# 在仓库根目录执行
./scripts/release/release-gh.sh            # 自动按 minor 加一（0.1.0 → 0.2.0）
./scripts/release/release-gh.sh 0.2.0      # 或显式指定版本（带不带 v 都行）
```

脚本会自动：改 Info.plist → 提交推送 → 建 git tag → 触发 CI 在 GitHub 云端构建并上传 `AppLaunchpad.dmg`。
**本机不编译、不占资源。**

---

## 1. 发版全流程（AI 照做）

### 步骤 1 — 更新 CHANGELOG（唯一需人工/AI 手写的内容）
编辑 `scripts/release/CHANGELOG.md`，为本次版本新增一段说明。
- 该文件会被 `release-gh.sh` 当作 Release 的完整说明（`--notes-file`）。
- 段落标题建议与版本号一致，例如 `## v0.2.0`。
- 这是流程里**唯一非自动**的环节，AI 必须补全对应版本的条目，否则 Release 说明会缺失/陈旧。

### 步骤 2 — 执行发版脚本
在**仓库根目录**运行：

```bash
# 方式 A：自动加一（默认 BUMP=minor）
./scripts/release/release-gh.sh

# 方式 B：显式指定版本
./scripts/release/release-gh.sh 0.2.0
```

脚本内部依次做（无需人工干预）：
1. 读取 `AppLaunchpad/AppLaunchpad/Info.plist` 当前 `CFBundleShortVersionString` / `CFBundleVersion`。
2. 确定本次版本：
   - 传了参数 → 直接用该版本（去掉可能的 `v` 前缀）。
   - 没传参数 → 按脚本顶部 `BUMP`（默认 `minor`）在当前版本上自动加一。
3. 用 `PlistBuddy` 写回：
   - `CFBundleShortVersionString` = 本次版本
   - `CFBundleVersion` = 原值 +1（内部构建号）
4. 若 `AUTO_COMMIT=1`（默认）：`git add` 该 Info.plist → `git commit -m "chore: bump version to X.Y.Z (build N)"` → `git push`。
5. `gh release create vX.Y.Z --title vX.Y.Z --notes-file CHANGELOG.md`：
   - 本地建 tag 并推送到远程 → **触发** `.github/workflows/build-dmg.yml`。
6. 打印本次下载链接与**永久下载链接**。

### 步骤 3 — 确认 CI 打包成功
- 打开 GitHub Actions：`https://github.com/YunyuVv/AppLaunchpad/actions`
- 等待 `build-dmg.yml` 在 `macos-26` runner 上跑完（约几分钟）。
- 进入 Release 页 `https://github.com/YunyuVv/AppLaunchpad/releases/tag/vX.Y.Z`，确认资产里有 `AppLaunchpad.dmg`。

---

## 2. 涉及改动的文件清单（改哪里）

| 文件 | 角色 | 谁改 | 说明 |
|------|------|------|------|
| `AppLaunchpad/AppLaunchpad/Info.plist` | **版本真源** | 脚本自动（`release-gh.sh`） | `CFBundleShortVersionString`（对外版本）+ `CFBundleVersion`（内部构建号，每次 +1） |
| `scripts/release/CHANGELOG.md` | Release 说明 | **AI/人工** | 必须补对应版本段落；脚本只读不写 |
| `.github/workflows/build-dmg.yml` | CI 打包流水线 | 一般不动 | 产物名固定 `AppLaunchpad.dmg`，**不要改成带版本号** |
| git tag `vX.Y.Z` | 发布标记 | 脚本自动建并推送 | 触发 CI 的唯一条件（仅 `v*` tag 出 DMG） |
| `AppLaunchpad/AppLaunchpad/Info.plist` 的提交 | 版本提交的载体 | 脚本自动 commit+push | 让 tag 指向含新版本的 commit，CI 打出来的包才是新版本 |

> ⚠️ **易错点**：`Info.plist` 在项目根下的 `AppLaunchpad/` 子目录里（两层同名），不是 `项目根/Info.plist`。

---

## 3. 执行了什么命令（汇总）

```
# 仓库根目录
./scripts/release/release-gh.sh [<版本号>]

# 脚本等价展开（理解用，不要手敲；让脚本跑）：
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString <ver>" AppLaunchpad/AppLaunchpad/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion <build+1>"   AppLaunchpad/AppLaunchpad/Info.plist
git add AppLaunchpad/AppLaunchpad/Info.plist
git commit -m "chore: bump version to <ver> (build <n>)"
git push
gh release create v<ver> --title v<ver> --notes-file scripts/release/CHANGELOG.md
```

---

## 4. 前置条件（执行前检查）

1. **已安装并登录 `gh`**：`command -v gh` 非空；`gh auth status` 正常。未装则 `brew install gh && gh auth login`。
2. **仓库为公开仓库**（当前开源 GPL v3，默认公开）。私有仓时 `releases/latest/download/...` 需登录鉴权。
3. **未提交的无关改动尽量少**：脚本只会 `git add` Info.plist 一个文件，但会 `git push` 当前分支，请注意不要把脏改动带上去。
4. **CI 运行器可用**：`.github/workflows/build-dmg.yml` 指定 `macos-26` runner + GitHub Actions 权限（默认有 `GITHUB_TOKEN` 写 Release/构件）。

---

## 5. 发布后对外下载地址（固定，永不变）

```
永久链接（永远指向最新非预发布 Release 的 DMG）：
https://github.com/YunyuVv/AppLaunchpad/releases/latest/download/AppLaunchpad.dmg

本次链接（带具体版本）：
https://github.com/YunyuVv/AppLaunchpad/releases/download/vX.Y.Z/AppLaunchpad.dmg
```

只需对外给"永久链接"即可，版本升级后链接不变。

---

## 6. 红线 / 坑（务必遵守）

1. **DMG 名保持 `AppLaunchpad.dmg` 不变**（CI 内写死，无版本号）。改名会破坏"永久下载链接"。
2. **Release 不要标成 pre-release**：`releases/latest` 会跳过预发布，永久链接会停在上一个正式版。
3. **版本号只增不减**，且 `CFBundleShortVersionString` 必须与 tag `vX.Y.Z` 同号（脚本已自动对齐，手动改时尤其注意）。
4. **不要把 `layout.json` 的 `version` 字段（`LayoutData.swift` 里 `version: Int = 1`）当成 app 版本**——那是布局数据格式版本，互不影响。
5. **bundle id 固定** `com.biliww.applaunchpad`（见 `project.yml`），改 id 会让已授权的辅助功能失效、历史设置重置，勿动。
6. 当前 `project.yml` **未写死**版本（只有 `SWIFT_VERSION: 6.0`），版本完全来自 Info.plist；不要去 `project.yml` 另设版本。
7. 安装未签名包的用户需：`sudo xattr -r -d com.apple.quarantine /Applications/AppLaunchpad.app` + 右键打开 + 系统设置授权辅助功能（全局快捷键 ⌥+Space 依赖）。

---

## 7. 备选：本地打包（不推荐，占本机资源）

若确需在本机构建（例如 CI 不可用），用：

```bash
./scripts/release/release-local.sh <major|minor|patch|<x.y.z>> [--tag]
```

它会本地 `xcodegen` → 未签名 `xcodebuild` → `hdiutil` 出 DMG，并用 PlistBuddy 升版本。
**日常发版请用 `release-gh.sh`（云端打包），避免占用本机。**

---

## 8. 异常情况处理

- **CI 跑挂**：去 Actions 看日志；常见为 `macos-26` runner 拉取/代码签名步骤。未签名路线已设 `CODE_SIGN_IDENTITY=""` 等覆盖，正常情况下不需改。修复后重新跑 `release-gh.sh` 即可（已存在同名 tag 时 `gh release create` 会冲突——此时先 `gh release delete vX.Y.Z` 并删本地/远程 tag 再发，或改用更高版本号）。
- **想换版本号但 Info.plist 已改**：直接再跑 `release-gh.sh <正确版本>`，脚本会把 Info.plist 覆盖写入该版本并重新发版。
- **`gh` 不在本机**：按第 4 节安装登录；或纯手工走第 3 节的等价命令（需手动 `git` + `gh`）。
