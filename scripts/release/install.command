#!/bin/bash
# install.command — AppLaunchpad 一键安装（在 DMG 内双击运行，需输入管理员密码）
# 双击后由 Terminal 运行：sudo 会提示输入登录密码（输入时不显示，回车确认）。
set -e

APP_NAME="AppLaunchpad"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$SCRIPT_DIR/$APP_NAME.app"
APP_DST="/Applications/$APP_NAME.app"

if [ ! -d "$APP_SRC" ]; then
  echo "✗ 未找到 $APP_SRC，请确认本脚本与 AppLaunchpad.app 在同一文件夹（DMG 根目录）。" >&2
  exit 1
fi
if pgrep -f "$APP_DST" >/dev/null 2>&1; then
  echo "⚠ $APP_NAME 正在运行，请先 ⌘Q 退出后再安装。" >&2
  exit 1
fi

echo "🔐 输入管理员密码以安装到 /Applications："
sudo bash -c "
  rm -rf \"$APP_DST\"
  cp -R \"$APP_SRC\" \"$APP_DST\"
  xattr -r -d com.apple.quarantine \"$APP_DST\" 2>/dev/null || true
  spctl --add \"$APP_DST\" 2>/dev/null || true
"

echo "✅ 已安装到 $APP_DST"
echo "   首次启动：在访达中右键 AppLaunchpad.app → 打开 → 点「仍要打开」。"
read -p "按回车退出…"
