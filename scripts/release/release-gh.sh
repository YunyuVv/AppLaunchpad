#!/bin/sh
#
# release-gh.sh — 一键发布 GitHub Release（自动升版本 + 触发 CI 云端打包未签名 DMG）
#
# 用法：
#   ./scripts/release/release-gh.sh            # 不传版本 → 按 BUMP 自动加一（默认 patch：0.3.0 → 0.3.1）
#   ./scripts/release/release-gh.sh 0.2.0      # 显式指定版本（带不带 v 都行）
#   ./scripts/release/release-gh.sh v0.2.0
#
# 说明：
#   - 自动把版本写入 AppLaunchpad/Info.plist：
#       · CFBundleShortVersionString = 本次发布的版本号
#       · CFBundleVersion            = 原值 +1（内部构建号）
#     然后提交并推送到远程，再建标签 vX.Y.Z → 触发 .github/workflows/build-dmg.yml
#     → GitHub 后台构建未签名 DMG（AppLaunchpad.dmg）并上传到本 Release。
#   - 因此本机无需本地编译，也不需再跑 scripts/release/release-local.sh。
#   - 版本发布说明取自 NOTES_FILE（默认脚本同目录 CHANGELOG.md）。
#   - 对外固定下载地址（永远指向最新版）：
#       https://github.com/YunyuVv/AppLaunchpad/releases/latest/download/AppLaunchpad.dmg
#
set -e

# 脚本所在目录与仓库根（脚本位于 scripts/release/，仓库根回退两级）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# ── 可配置项（脚本前几行修改）──────────────────────────────
NOTES_FILE="$SCRIPT_DIR/CHANGELOG.md"   # 版本说明文件（默认脚本同目录 CHANGELOG.md，可改绝对/相对路径）
TITLE_PREFIX=""                         # Release 标题前缀；留空则标题 = 标签名（如 v0.2.0）
BUMP="patch"                            # 不传版本参数时的自动加一位：major / minor / patch
                                        #   默认 patch（第三位+1）：修复、性能优化、小调整——本项目绝大多数发版属此类
                                        #   加向下兼容的新功能 → 显式传版本（如 release-gh.sh 0.4.0 即 minor：第二位+1）
                                        #   不兼容的重大改动/重构 → 显式传版本（如 release-gh.sh 1.0.0 即 major：第一位+1）
                                        #   即：不传=patch，要 minor/major 请显式给版本号（脚本会自动识别 X.Y.Z）
AUTO_COMMIT=1                           # 是否自动 git 提交并推送 Info.plist 的版本改动（1=是，0=否）
# ──────────────────────────────────────────────────────────

# 检查 gh 是否安装
if ! command -v gh >/dev/null 2>&1; then
  echo "✗ 未找到 gh（GitHub CLI）。请先安装并登录：" >&2
  echo "    brew install gh && gh auth login" >&2
  exit 1
fi

# 检查 git 是否可用
if ! command -v git >/dev/null 2>&1; then
  echo "✗ 未找到 git。" >&2
  exit 1
fi

# ── 读取 Info.plist 当前版本 ───────────────────────────────
INFO_PLIST="$REPO_ROOT/AppLaunchpad/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
  echo "✗ 找不到 Info.plist：$INFO_PLIST" >&2
  exit 1
fi
PLIST_BUDDY=/usr/libexec/PlistBuddy
if [ ! -x "$PLIST_BUDDY" ]; then
  echo "✗ 找不到 PlistBuddy：$PLIST_BUDDY" >&2
  exit 1
fi
CUR_VER=$("$PLIST_BUDDY" -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)
CUR_BUILD=$("$PLIST_BUDDY" -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || true)

# ── 确定本次版本号 ─────────────────────────────────────────
bump_version() {
  # $1 = 当前版本(如 0.1.0)； $2 = major/minor/patch
  _cur="$1"; _kind="$2"
  _maj=$(echo "$_cur" | cut -d. -f1)
  _min=$(echo "$_cur" | cut -d. -f2)
  _pat=$(echo "$_cur" | cut -d. -f3)
  _maj=${_maj:-0}; _min=${_min:-0}; _pat=${_pat:-0}
  case "$_kind" in
    major) _maj=$((_maj + 1)); _min=0; _pat=0 ;;
    minor) _min=$((_min + 1)); _pat=0 ;;
    patch) _pat=$((_pat + 1)) ;;
    *) echo "✗ 未知 BUMP='$_kind'（应为 major/minor/patch）" >&2; exit 1 ;;
  esac
  echo "${_maj}.${_min}.${_pat}"
}

if [ $# -ge 1 ]; then
  VER="${1#v}"                         # 去掉可能已有的 v 前缀，统一再加
  echo "▶ 使用显式版本：$VER"
else
  if [ -z "$CUR_VER" ]; then
    echo "✗ 无法读取 Info.plist 当前版本，请用参数显式指定版本号。" >&2
    exit 1
  fi
  VER=$(bump_version "$CUR_VER" "$BUMP")
  echo "▶ 未指定版本，按默认 BUMP=$BUMP 自动加一（patch=第三位+1，修复/性能优化）：$CUR_VER → $VER"
fi

# 校验版本号格式 X.Y.Z
case "$VER" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "✗ 版本号格式应为 X.Y.Z，当前：$VER" >&2; exit 1 ;;
esac
TAG="v${VER}"

# ── 写入 Info.plist ────────────────────────────────────────
NEW_BUILD=$(( ${CUR_BUILD:-0} + 1 ))
echo "▶ 写入 Info.plist："
echo "    CFBundleShortVersionString = $VER"
echo "    CFBundleVersion            = ${CUR_BUILD:-0} → $NEW_BUILD"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VER" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

# ── 自动提交并推送版本改动 ─────────────────────────────────
if [ "$AUTO_COMMIT" = "1" ]; then
  if git diff --quiet "$INFO_PLIST" 2>/dev/null; then
    echo "  Info.plist 无变化，跳过提交。"
  else
    git add "$INFO_PLIST"
    git commit -m "chore: bump version to $VER (build $NEW_BUILD)"
    echo "▶ 已提交 Info.plist 版本改动，推送中…"
    git push
  fi
else
  echo "  (AUTO_COMMIT=0，未提交 Info.plist，记得自行 git commit/push 后再发版)"
fi

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

echo "▶ 发布 Release：$TAG（标题：$TITLE，说明取自 $NOTES_FILE）"
gh release create "$TAG" \
  --title "$TITLE" \
  --notes-file "$NOTES_FILE"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "YunyuVv/AppLaunchpad")
echo ""
echo "✅ 已创建 Release $TAG"
echo "   GitHub 正在后台构建未签名 DMG，几分钟后到 Release 页面查看 AppLaunchpad.dmg"
echo "   本次下载：$REPO/releases/download/$TAG/AppLaunchpad.dmg"
echo "   永久下载（永远指向最新版）：https://github.com/$REPO/releases/latest/download/AppLaunchpad.dmg"
