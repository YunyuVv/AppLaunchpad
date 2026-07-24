# AppLaunchpad — Logo

主符号：上方一枚上扬 chevron 箭头 + 下方 3×2 圆角方块点阵。
寓意 "从应用网格中一键启动"。

## 配色

| 用途 | 颜色 |
| --- | --- |
| 渐变起点（底部） | `#4F46E5` indigo |
| 渐变终点（顶部） | `#7C3AED` violet |
| 符号 | `#FFFFFF` |

## 文件

| 文件 | 用途 |
| --- | --- |
| `applaunchpad-icon.svg` | **矢量源**：完整应用图标（圆角方块 + 渐变 + 阴影 + 符号） |
| `applaunchpad-logo.svg` | 符号版（仅 chevron + 点阵，透明背景），用于任意彩色底 |
| `applaunchpad-icon-1024.png` | App Store / 启动台主图，1024×1024 |
| `applaunchpad-icon-{512,256,128,64,32}.png` | 各尺寸栅格导出（SVG → PNG） |
| `applaunchpad-icon-source-ai.png` | 原始 AI 生成图（含外圈背景），供溯源参考，**不要直接使用** |
| `applaunchpad-size-preview.png` | 32/64/128/256 px 在浅色与深色背景下的可读性验证图 |

矢量源 `applaunchpad-icon.svg` 是单一权威；所有 PNG 均由它栅格化。
任何尺寸改动（圆角、间距、符号粗细）请编辑 SVG 后用矢量工具重新导出 PNG。

## Xcode 集成（macOS .icns）

将 `applaunchpad-icon-1024.png` 加入 `Assets.xcassets / AppIcon.appiconset` 即可：

| macOS 槽位 | 像素 | 对应文件 |
| --- | --- | --- |
| 16×16, 32×32, 128×128, 256×256, 512×512（@1x/@2x） | 各 | `applaunchpad-icon-{32,64,128,256,512}.png` |
| App Store 1024×1024 | 1024 | `applaunchpad-icon-1024.png` |

或者用 `iconutil` 直接打包：

```sh
mkdir -p AppIcon.iconset
cp applaunchpad-icon-16.png  AppIcon.iconset/icon_16x16.png
cp applaunchpad-icon-32.png  AppIcon.iconset/icon_16x16@2x.png
cp applaunchpad-icon-32.png  AppIcon.iconset/icon_32x32.png
cp applaunchpad-icon-64.png  AppIcon.iconset/icon_32x32@2x.png
cp applaunchpad-icon-128.png AppIcon.iconset/icon_128x128.png
cp applaunchpad-icon-256.png AppIcon.iconset/icon_128x128@2x.png
cp applaunchpad-icon-256.png AppIcon.iconset/icon_256x256.png
cp applaunchpad-icon-512.png AppIcon.iconset/icon_256x256@2x.png
cp applaunchpad-icon-512.png AppIcon.iconset/icon_512x512.png
cp applaunchpad-icon-1024.png AppIcon.iconset/icon_512x512@2x.png
cp applaunchpad-icon-1024.png AppIcon.iconset/icon_1024x1024.png
iconutil -c icns AppIcon.iconset
```

> 当前项目暂无 `Assets.xcassets`；如需正式接入 Xcode，先创建 `Assets.xcassets/AppIcon.appiconset/Contents.json` 并把上面 PNG 填入。

## 可读性验证

32px 仍清晰分辨 chevron + 3×2 网格；通过 favicon 测试。深色背景下表现良好。
详见 `applaunchpad-size-preview.png`。