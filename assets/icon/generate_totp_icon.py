#!/usr/bin/env python3
"""lzy_totp 应用图标生成器（纯代码绘制，不依赖任何字体）。

设计：把关键词 "totp" 作为图标主体，其中字母 **o 被画成倒计时圆环**——
弧长表示当前 TOTP 周期已过去的比例，弧的末端有个亮点，正好对应
TOTP「随时间滚动的一次性验证码」这一语义。

用法：
    python3 generate_totp_icon.py                    # 输出 totp_icon.svg
    python3 generate_totp_icon.py --progress 0.35     # 自定义倒计时进度
    python3 generate_totp_icon.py -o out.svg
"""

from __future__ import annotations

import argparse
import math

# ----------------------------------------------------------------- 设计参数

SIZE = 1024          # 画布边长
CORNER = 228         # 圆角半径（近似 macOS/iOS squircle）
PAD = 84             # 内容区留白

STROKE = 48          # 字母笔画宽度（等宽线条）
XH_TOP = 420         # x-height 上沿（o/p 的圆顶）
BASELINE = 620       # 基线
ASCENDER = 316       # t 的竖笔顶端（比 x-height 高出一截，避免像加号）
DESCENDER = 704      # p 的竖笔下沉端
CROSSBAR_Y = 432     # t 横笔位置（贴近 x-height 上沿）

O_RADIUS = 104       # o 圆环外半径
GAP = 52             # 字母间距
TARGET_INK_WIDTH = 632   # 目标字面宽度（居中并等比缩放用）

BG_TOP = "#07302F"       # 背景渐变：深青
BG_BOTTOM = "#0B4A47"
INK = "#EAFFFC"          # 字母颜色
TRACK = "rgba(234,255,252,0.22)"   # 圆环未走完的底轨
ARC = "#2DD4BF"          # 圆环已走完的弧（teal 400）
DOT = "#7DF9E4"          # 弧末端亮点
GLOW = "#14B8A6"         # 背景柔光


def _stroke_path(parts: list[str], color: str = INK) -> str:
    """把若干段折线合成一条等宽描边路径。"""
    return (
        f'<path d="{" ".join(parts)}" fill="none" stroke="{color}" '
        f'stroke-width="{STROKE}" stroke-linecap="round" stroke-linejoin="round"/>'
    )


def build_letters() -> tuple[str, tuple[float, float, float, float], tuple[float, float, float]]:
    """生成 t-o-t-p 四个字母的几何图形，并返回墨迹包围盒与 o 圆环参数。"""
    r = O_RADIUS - STROKE / 2          # 圆环中心线半径
    mid_y = (XH_TOP + BASELINE) / 2    # x-height 垂直中心

    # t：竖笔 + 横笔
    def letter_t(cx: float) -> str:
        return _stroke_path([
            f"M {cx:.1f} {ASCENDER} V {BASELINE}",          # 竖笔
            f"M {cx - 52:.1f} {CROSSBAR_Y} H {cx + 64:.1f}",  # 横笔（左短右长）
        ])

    # o：外圈为倒计时圆环（在 build_ring 里单独画），这里不产生字母笔画

    # p：竖笔 + 右侧圆碗
    def letter_p(cx: float) -> str:
        return (
            _stroke_path([f"M {cx:.1f} {XH_TOP} V {DESCENDER}"])
            + f'<circle cx="{cx + r:.1f}" cy="{mid_y:.1f}" r="{r:.1f}" '
              f'fill="none" stroke="{INK}" stroke-width="{STROKE}"/>'
        )

    t1_cx = 0.0
    o_cx = 64 + GAP + O_RADIUS                    # 紧跟第一个 t
    t2_cx = (o_cx + O_RADIUS) + GAP + 64
    p_cx = (t2_cx + 64) + GAP + STROKE / 2

    ink = (
        f'<g id="wordmark">'
        f'{letter_t(t1_cx)}'
        f'{letter_t(t2_cx)}'
        f'{letter_p(p_cx)}'
        f'</g>'
    )
    bbox = (t1_cx - 52, ASCENDER, p_cx + r + O_RADIUS, DESCENDER)
    return ink, bbox, (o_cx, mid_y, r)


def build_ring(cx: float, cy: float, r: float, progress: float) -> str:
    """把字母 o 画成倒计时圆环：底轨 + 已走过的弧 + 弧末端亮点。"""
    circumference = 2 * math.pi * r
    done = max(0.0, min(1.0, progress)) * circumference
    theta = progress * 2 * math.pi - math.pi / 2      # 从 12 点方向顺时针
    dot_x = cx + r * math.cos(theta)
    dot_y = cy + r * math.sin(theta)

    return (
        f'<g id="countdown-o">'
        # 底轨
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" '
        f'stroke="{TRACK}" stroke-width="{STROKE}"/>'
        # 已走完的弧（dash 从 12 点方向开始）
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" '
        f'stroke="{ARC}" stroke-width="{STROKE}" stroke-linecap="round" '
        f'stroke-dasharray="{done:.2f} {circumference - done:.2f}" '
        f'transform="rotate(-90 {cx:.1f} {cy:.1f})"/>'
        # 弧末端亮点
        f'<circle cx="{dot_x:.1f}" cy="{dot_y:.1f}" r="{STROKE / 2:.1f}" fill="{DOT}"/>'
        f'</g>'
    )


def build_svg(progress: float = 0.68, inset: int = 0) -> str:
    letters, (x0, y0, x1, y1), (o_cx, o_cy, o_r) = build_letters()

    # 按墨迹包围盒居中 + 等比缩放到目标字面宽度
    ink_w, ink_h = x1 - x0, y1 - y0
    scale = TARGET_INK_WIDTH / ink_w
    cx, cy = x0 + ink_w / 2, y0 + ink_h / 2

    ring = build_ring(o_cx, o_cy, o_r, progress)
    # p 的碗要盖住圆环底轨？不需要——o 与 p 分离，各自独立

    # macOS 规范：整体内缩留出透明边距，图标本体再等比缩放
    plate = SIZE - 2 * inset
    plate_scale = plate / SIZE
    corner = CORNER * plate_scale

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}"
     viewBox="0 0 {SIZE} {SIZE}" role="img" aria-label="lzy_totp 应用图标">
  <title>lzy_totp — TOTP 验证器</title>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{BG_TOP}"/>
      <stop offset="1" stop-color="{BG_BOTTOM}"/>
    </linearGradient>
    <filter id="soft-shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000000" flood-opacity="0.28"/>
    </filter>
    <radialGradient id="glow" cx="0.28" cy="0.18" r="0.85">
      <stop offset="0" stop-color="{GLOW}" stop-opacity="0.45"/>
      <stop offset="1" stop-color="{GLOW}" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <g transform="translate({SIZE / 2} {SIZE / 2}) scale({plate_scale:.6f}) translate({-SIZE / 2} {-SIZE / 2})">
    <!-- 圆角底板 + 柔光 + 内侧描边 -->
    <rect x="0" y="0" width="{SIZE}" height="{SIZE}" rx="{CORNER}" fill="url(#bg)"/>
    <rect x="0" y="0" width="{SIZE}" height="{SIZE}" rx="{CORNER}" fill="url(#glow)"/>
    <rect x="6" y="6" width="{SIZE - 12}" height="{SIZE - 12}" rx="{CORNER - 6}"
          fill="none" stroke="rgba(255,255,255,0.10)" stroke-width="6"/>
  </g>

  <!-- totp 字标：o 即倒计时圆环 -->
  <g filter="url(#soft-shadow)" transform="translate({SIZE / 2} {SIZE / 2}) scale({plate_scale * scale:.5f}) translate({-cx:.2f} {-cy:.2f})">
    {letters}
    {ring}
  </g>
</svg>
'''


def main() -> None:
    parser = argparse.ArgumentParser(description="生成 lzy_totp 应用图标 SVG")
    parser.add_argument("--progress", type=float, default=0.68,
                        help="倒计时圆环已完成比例，0~1（默认 0.68）")
    parser.add_argument("--inset", type=int, default=0,
                        help="四周透明留白像素（macOS 图标建议 112）")
    parser.add_argument("-o", "--output", default="totp_icon.svg",
                        help="输出文件（默认 totp_icon.svg）")
    args = parser.parse_args()

    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write(build_svg(args.progress, args.inset))
    extra = f"，留白 {args.inset}px" if args.inset else ""
    print(f"已生成 {args.output}（倒计时进度 {args.progress:.0%}{extra}）")


if __name__ == "__main__":
    main()
