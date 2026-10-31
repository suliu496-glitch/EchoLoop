"""EchoLoop 应用图标生成脚本。

设计稿画在 130x130 的设计坐标系里，图形中心在 (65, 65)，由三个元素组成：

  1. 一圈循环箭头（缺口在正上方，箭头指向顺时针）
  2. 环内三根高低不同的声波柱

含义是「反复听一段音频」，正好对应主功能 AB 循环跟读。

输出两类资源，都写进 android/app/src/main/res：

  A. 传统图标  mipmap-<density>/ic_launcher.png
     圆角方底 + 图形，给不使用自适应图标的启动器兜底。

  B. 自适应图标（Android 8+，本项目 minSdk 26 所以这是实际生效的那套）
     mipmap-<density>/ic_launcher_foreground.png   透明底 + 图形
     mipmap-<density>/ic_launcher_monochrome.png   Android 13+ 主题图标用
     mipmap-anydpi-v26/ic_launcher.xml             把前景和纯色背景合成
     values/ic_launcher_background.xml             背景色 #2563EB

自适应图标的关键：系统会把图裁成圆形或圆角方形，可见区域只有中心 72dp。
所以前景里的图形必须缩到中心约 66dp 以内，否则四角会被切掉。
这里的做法是让图形的**外接圆**（含箭头尖角）落在 66dp 直径内。

所有位图都用 4 倍超采样再缩小，保证边缘平滑，小尺寸下不会毛糙。

重新生成：python tool/gen_icon.py
"""

import math
import os
from pathlib import Path

from PIL import Image, ImageDraw

# ---------------------------------------------------------------- 颜色与常量

BLUE = (37, 99, 235, 255)        # #2563EB，与 App 主题 accentDeep 一致
WHITE = (255, 255, 255, 255)
LIGHT = (219, 234, 254, 255)     # #DBEAFE，两侧声波柱用浅一档的蓝
CLEAR = (0, 0, 0, 0)

SS = 4                            # 超采样倍数

DESIGN = 130.0                    # 设计坐标系边长
RING_R = 34.0                     # 循环环半径
RING_W = 9.0                      # 循环环描边宽度

# 缺口开在正上方：弧从 305 度顺时针画到 235 度，中间空出 70 度给箭头。
RING_START = 305.0
RING_END = 235.0

# 箭头画在弧的终点（235 度，左上方），沿顺时针切线方向伸出，指向缺口。
# 这样箭头是「顺着环继续往前走」的姿态，而不是横插在环上。
ARROW_AT = RING_END
ARROW_LEN = 24.0                  # 沿切线方向的长度，明显长于底边宽才有「箭」的样子
ARROW_HALF_W = 8.5                # 底边半宽（沿半径方向），比环宽一倍

GLYPH_R = 44.0                    # 图形外接半径（含箭头底角，见文件头说明）

# 自适应图标里图形要占的尺寸（dp）。72dp 是可见区，留 6dp 余量。
GLYPH_BOX_DP = 66.0
ADAPTIVE_DP = 108.0               # 自适应图标前景层的标准尺寸

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RES_DIR = str(PROJECT_ROOT / "android" / "app" / "src" / "main" / "res")
PREVIEW_DIR = str(PROJECT_ROOT / "assets" / "icon")

# 各密度对应的传统图标边长与自适应图层边长
DENSITIES = [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]

# 三根声波柱：(x0, y0, x1, y1, 圆角半径, 是否用主色)，坐标相对图形中心。
# 柱子宽度统一 8 个设计单位，小尺寸下才不会细到看不清。
BARS = [
    (-15.0, -9.0, -7.0, 9.0, 4.0, False),
    (-4.0, -15.0, 4.0, 15.0, 4.0, True),
    (7.0, -11.0, 15.0, 11.0, 4.0, False),
]


# ---------------------------------------------------------------- 绘制

def draw_glyph(draw, cx, cy, k, side_color=LIGHT, mid_color=WHITE, ring_color=WHITE):
    """把图形画到 (cx, cy) 处。

    [k] 是「设计单位 -> 像素」的缩放倍数。
    """
    ring_r = RING_R * k
    ring_w = RING_W * k
    box = [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r]

    # 循环环。PIL 的角度体系是 0 度在 3 点钟方向、顺时针增加，与设计稿一致。
    draw.arc(box, start=RING_START, end=RING_END, fill=ring_color,
             width=int(round(ring_w)))

    # 弧的两端补上圆点，做出圆头效果（PIL 的 arc 端点是平的）。
    # 只补起点那一端：终点要接箭头，补了圆头会把箭头的根部吃掉，
    # 结果看起来像环的末端被削尖，而不像一支箭头。
    for angle in (RING_START,):
        px = cx + ring_r * math.cos(math.radians(angle))
        py = cy + ring_r * math.sin(math.radians(angle))
        draw.ellipse(
            [px - ring_w / 2, py - ring_w / 2, px + ring_w / 2, py + ring_w / 2],
            fill=ring_color,
        )

    # 箭头：底部贴在弧的终点上，沿顺时针切线方向伸出
    theta = math.radians(ARROW_AT)
    ax = cx + ring_r * math.cos(theta)
    ay = cy + ring_r * math.sin(theta)
    tan_x, tan_y = -math.sin(theta), math.cos(theta)   # 顺时针切线
    rad_x, rad_y = math.cos(theta), math.sin(theta)    # 半径方向

    def point(fx, fy):
        return (ax + fx * k, ay + fy * k)

    draw.polygon(
        [
            point(tan_x * ARROW_LEN, tan_y * ARROW_LEN),
            point(rad_x * ARROW_HALF_W, rad_y * ARROW_HALF_W),
            point(-rad_x * ARROW_HALF_W, -rad_y * ARROW_HALF_W),
        ],
        fill=ring_color,
    )

    # 三根声波柱
    for x0, y0, x1, y1, radius, is_main in BARS:
        draw.rounded_rectangle(
            [cx + x0 * k, cy + y0 * k, cx + x1 * k, cy + y1 * k],
            radius=radius * k,
            fill=mid_color if is_main else side_color,
        )


def render_traditional(size):
    """传统图标：圆角方底 + 图形。"""
    canvas = size * SS
    image = Image.new("RGBA", (canvas, canvas), CLEAR)
    draw = ImageDraw.Draw(image)

    draw.rounded_rectangle(
        [0, 0, canvas - 1, canvas - 1],
        radius=canvas * 30.0 / DESIGN,
        fill=BLUE,
    )
    draw_glyph(draw, canvas / 2, canvas / 2, canvas / DESIGN)

    return image.resize((size, size), Image.LANCZOS)


def render_foreground(dp, monochrome=False):
    """自适应图标前景：透明底 + 居中的图形。

    [monochrome] 为 True 时全部用白色，供 Android 13+ 主题图标取形状。
    """
    canvas = dp * SS
    image = Image.new("RGBA", (canvas, canvas), CLEAR)
    draw = ImageDraw.Draw(image)

    # 缩放倍数要按 ADAPTIVE_DP 折算，不能用 dp（dp 是输出像素数，会随密度变化）：
    # 108dp 的画布上，1dp = canvas / ADAPTIVE_DP 像素。
    k = (canvas / ADAPTIVE_DP) * (GLYPH_BOX_DP / 2.0) / GLYPH_R

    if monochrome:
        draw_glyph(draw, canvas / 2, canvas / 2, k,
                   side_color=WHITE, mid_color=WHITE, ring_color=WHITE)
    else:
        draw_glyph(draw, canvas / 2, canvas / 2, k)

    return image.resize((dp, dp), Image.LANCZOS)


# ---------------------------------------------------------------- 遮罩预览

def adaptive_composite(size):
    """按自适应图标的规格合成一张完整图（纯色背景 + 前景图形）。"""
    image = Image.new("RGBA", (size, size), BLUE)
    image.alpha_composite(render_foreground(size))
    return image


def masked(image, shape):
    """按启动器可能用的遮罩形状裁切，还原桌面上的真实观感。

    可见区只有 108dp 图标的中心 72dp，所以这里先取中心 2/3 的区域，
    再按形状套遮罩。如果图形超出这个区域，边缘就会被切掉。
    """
    size = image.width
    visible = int(round(size * 72.0 / 108.0))
    offset = (size - visible) // 2
    box = [offset, offset, offset + visible - 1, offset + visible - 1]

    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    if shape == "circle":
        draw.ellipse(box, fill=255)
    elif shape == "squircle":
        draw.rounded_rectangle(box, radius=visible * 0.22, fill=255)
    else:
        draw.rectangle(box, fill=255)

    out = Image.new("RGBA", (size, size), CLEAR)
    out.paste(image, (0, 0), mask)
    return out.resize((144, 144), Image.LANCZOS)


def build_adaptive_preview():
    """三种常见遮罩并排，用来确认图形不会被圆形遮罩切到。"""
    composite = adaptive_composite(432)
    tile, gap = 144, 20
    preview = Image.new("RGBA", (tile * 3 + gap * 2, tile), CLEAR)
    for index, shape in enumerate(("circle", "squircle", "square")):
        preview.alpha_composite(masked(composite, shape), (index * (tile + gap), 0))
    return preview


# ---------------------------------------------------------------- 输出

def save(image, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, "PNG")
    return path


def main():
    written = []

    for density, legacy_size, adaptive_size in DENSITIES:
        folder = os.path.join(RES_DIR, f"mipmap-{density}")
        written.append(save(render_traditional(legacy_size), folder, "ic_launcher.png"))
        written.append(save(render_foreground(adaptive_size), folder, "ic_launcher_foreground.png"))
        written.append(save(render_foreground(adaptive_size, monochrome=True),
                            folder, "ic_launcher_monochrome.png"))

    # 留档用的高清主图，1024 是应用商店与设计稿的常用尺寸
    written.append(save(render_traditional(1024), PREVIEW_DIR, "icon-1024.png"))
    written.append(save(render_traditional(192), PREVIEW_DIR, "icon-preview-192.png"))
    written.append(save(render_traditional(48), PREVIEW_DIR, "icon-preview-48.png"))
    written.append(save(build_adaptive_preview(), PREVIEW_DIR, "icon-adaptive-preview.png"))

    for path in written:
        size = os.path.getsize(path)
        print(f"{size:>7} B  {os.path.relpath(path, RES_DIR)}"
              if path.startswith(RES_DIR) else f"{size:>7} B  {path}")


if __name__ == "__main__":
    main()
