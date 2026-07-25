AppLaunchpad 安装说明
====================

1. 把 AppLaunchpad.app 拖到「应用程序」(/Applications) 文件夹

2. 打开「终端」（Spotlight 搜"终端"），执行以下命令并输入登录密码：
   sudo xattr -r -d com.apple.quarantine /Applications/AppLaunchpad.app

3. 在「应用程序」文件夹里找到 AppLaunchpad.app，第一次打开时
   在弹窗中点"打开"即可（只需这一次，之后双击正常启动）

首次启动后请到：系统设置 → 隐私与安全性 → 辅助功能 → 打开 AppLaunchpad
（全局快捷键 ⌥+Space 必需，需手动授权一次）
