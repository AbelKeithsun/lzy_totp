# 应用图标

图标由 `generate_totp_icon.py` **用代码绘制**（纯几何路径，不依赖任何字体），
设计要点：把关键词 **`totp`** 作为主体，其中字母 **`o` 就是倒计时圆环**——
弧长表示当前 TOTP 周期已过去的比例，弧末端的高亮圆点表示「现在」，
正好对应 TOTP（基于时间的一次性密码）的语义。

## 文件

| 文件 | 用途 |
|---|---|
| `generate_totp_icon.py` | 生成器（参数化：倒计时进度、留白） |
| `totp_icon.svg` | 主图标，满幅圆角方形（Android / iOS / Web favicon） |
| `totp_icon_macos.svg` | macOS 变体，四周 112px 透明留白（符合 macOS 图标网格规范） |
| `totp_icon_1024.png` | 主图标 1024×1024 位图（供图标工具链使用） |
| `totp_icon_macos_1024.png` | macOS 变体 1024×1024 位图 |

## 设计参数

```bash
# 默认：满幅圆角方形，倒计时进度 68%
python3 generate_totp_icon.py

# macOS 规范（透明留白 + 内缩底板）
python3 generate_totp_icon.py --inset 112 -o totp_icon_macos.svg

# 自定义倒计时进度（0~1），例如画在周期刚过半的位置
python3 generate_totp_icon.py --progress 0.5
```

配色取自 App 的深色主题（teal 系）：底板渐变 `#07302F → #0B4A47`，
字母 `#EAFFFC`，圆环进度弧 `#2DD4BF`。

## 导出 PNG

SVG 转 PNG 需要一个真正的 SVG 渲染器（ImageMagick 内置的 MSVG 渲染器不支持
渐变与组合变换，会画出空白图）。任选其一：

```bash
# 方式一：resvg（推荐，渲染质量最好）
npm i -g @resvg/resvg-js
node -e "const{Resvg}=require('@resvg/resvg-js');const fs=require('fs');\
const r=new Resvg(fs.readFileSync('totp_icon.svg','utf8'),{fitTo:{mode:'width',value:1024}});\
fs.writeFileSync('totp_icon_1024.png',r.render().asPng())"

# 方式二：librsvg（brew install librsvg）
rsvg-convert -w 1024 totp_icon.svg -o totp_icon_1024.png
```

## 接入 Flutter

用 [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) 一次性生成
Android / iOS / macOS 各尺寸图标：

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.0

flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon/totp_icon_1024.png"          # iOS 会自动去掉圆角
  macos:
    generate: true
    image_path: "assets/icon/totp_icon_macos_1024.png"  # macOS 用带留白的变体
  adaptive_icon_background: "#0B4A47"                    # Android 自适应图标底色
  adaptive_icon_foreground: "assets/icon/totp_icon_1024.png"
```

```bash
dart run flutter_launcher_icons
```
