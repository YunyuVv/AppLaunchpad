#!/bin/sh
#
# release-gh.sh — 用 gh 发布一个「带版本说明」的 GitHub Release（触发 CI 自动打包未签名 DMG）
#
# 用法：
#   ./scripts/release/release-gh.sh 0.2.0        # 发 v0.2.0，说明取自下方 NOTES_FILE
#   ./scripts/release/release-gh.sh v0.2.0       # 带 v 前缀也行
#
# 说明：
#   - 该命令会自动建标签 vX.Y.Z 并推送到远程 → 触发 .github/workflows/build-dmg.yml
#     → GitHub 后台构建未签名 DMG 并上传到本 Release。
#   - 建议发版前先升版本号（scripts/release/release-local.sh 或手动改 Info.plist 的
#     CFBundleShortVersionString），保持 app 内部版本与 Release 名一致。
#
set -eu

# 脚本所在目录与仓库根（脚本位于 scripts/release/，仓库根回退两级）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── 可配置项（脚本前几行修改）──────────────────────────────
NOTES_FILE="$SCRIPT_DIR/CHANGELOG.md"   # 版本说明文件（默认脚本同目录 CHANGELOG.md，可改绝对/相对路径）
TITLE_PREFIX=""                         # Release 标题前缀；留空则标题 = 标签名（如 v0.2.0）
# ──────────────────────────────────────────────────────────

# 检查 gh 是否安装
if ! command -v gh >/dev/null 2>&1; then
  echo "✗ 未找到 gh（GitHub CLI）。请先安装并登录：" >&2
  echo "    brew install gh && gh auth login" >&2
  exit 1
fi

# 解析版本号参数
if [ $# -lt 1 ]; then
  echo "用法：./scripts/release/release-gh.sh <版本号，如 0.2.0 或 v0.2.0>" >&2
  exit 1
fi
VER="$1"
VER="${VER#v}"              # 去掉可能已有的 v 前缀，统一再加
TAG="v${VER}"

# 检查版本说明文件是否存在
if [ ! -f "$NOTES_FILE" ]; then
  echo "✗ 版本说明文件不存在：$NOTES_FILE" >&2
  echo "   请创建该文件，或修改脚本顶部的 NOTES_FILE 配置。" >&2
  exit 1
fi

# 标题
if [ -n "$TITLE_PREFIX" ]; then
  TITLE="${TITLE_PREFIX} ${TAG}"
else
  TITLE="$TAG"
fi

# 软提醒：app 内部版本（Info.plist）是否与即将发布的 tag 一致
INFO_PLIST="$REPO_ROOT/AppLaunchpad/Info.plist"
if [ -f "$INFO_PLIST" ] && command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  BUNDLE_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)
  if [ -n "$BUNDLE_VER" ] && [ "$BUNDLE_VER" != "$VER" ]; then
    echo "⚠ 提醒：Info.plist 的 CFBundleShortVersionString = $BUNDLE_VER，与即将发布的 $TAG 不一致。"
    echo "  若需对齐，请先升版本（scripts/release/release-local.sh 或手动改 Info.plist），再发版。"
    echo "  3 秒后继续发布（Ctrl+C 取消）…"
    sleep 3
  fi
fi

echo "▶ 发布 Release：$TAG（标题：$TITLE，说明取自 $NOTES_FILE）"
gh release create "$TAG" \
  --title "$TITLE" \
  --notes-file "$NOTES_FILE"

echo ""
echo "✅ 已创建 Release $TAG"
echo "   GitHub 正在后台构建未签名 DMG，几分钟后到 Release 页面查看 AppLaunchpad.dmg"
echo "   $TAG 下载：https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/download/$TAG/AppLaunchpad.dmg"
