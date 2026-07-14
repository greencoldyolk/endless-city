"""把多段全幅场景图拼接烘焙成游戏用的 loop.png + lights.json。

输入：art-src/scenes/segment-a.png（候车亭+售货机）、segment-b.png（安静段）
输出：assets/scenes/loop.png、assets/scenes/lights.json

流程（新母图为"整幅画面"，与旧品红分层管线不同）：
1. 每段的路面线（角色站立线）在 SURFACE_Y 里手动标定——生成图保证不了等高
2. 统一到 FINAL_H 高、路面线对齐到 SURFACE_FRACTION（和 main.gd 一致）：
   天空不够的段顶部补渐变天，路下沿不够的底部延伸暗色桥体
3. B 段路面颜色向 A 段拉齐（中位色增益）
4. 横向拼接，接缝处 SEAM_FADE 像素做交叉渐变（天际线差异化作雾）
5. 水坑按"路面带里明显偏亮"的像素自动检测
6. 灯光/拾取点位是内容坐标，换图必须重标——写在 LIGHTS/PICKUP_SPOTS

运行：SDL_VIDEODRIVER=dummy .venv/bin/python tools/build_scene_from_segments.py
"""
import json
from pathlib import Path

import pygame

pygame.init()
pygame.display.set_mode((1, 1))

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art-src" / "scenes"
OUT = ROOT / "assets" / "scenes"

SURFACE_FRACTION = 0.68  # 必须和 main.gd 的 SURFACE_FRACTION 一致
FINAL_H = 600
SEAM_FADE = 120       # 路面/护栏带的接缝宽度（两段这部分本来就对得齐）
SKY_FADE = 480        # 天空/天际线带的接缝宽度：两段楼群构图不同，
SKY_BOTTOM = 310      # 用超宽雾化过渡把"换城"变成"雾里换景"；此行以上算天空带

# 每段的路面线 y（手动标定：角色脚该踩的那条线。取步道中部，
# 太靠下会显得贴着路沿跑）
SEGMENTS = [
    ("segment-a.png", 394),
    ("segment-b.png", 304),
]

# 灯光与拾取点位（最终 loop.png 里的内容坐标——环形闭合已把整图左移
# SEAM_FADE 像素，此处坐标为移位后的值。换母图必须重新标定）
LIGHTS = [
    {"x": 310, "y": 155, "energy": 0.75, "scale": 3.0, "_note": "候车亭顶灯"},
    {"x": 985, "y": 265, "energy": 0.5, "scale": 1.8, "_note": "自动售货机"},
]
PICKUP_SPOTS = [
    {"x": 1110, "item": "coffee", "_note": "售货机旁只出咖啡"},
    {"x": 350, "item": "radio", "_note": "候车亭长椅：有人留下的旧收音机"},
    {"x": 2575, "item": "umbrella", "_note": "B段栏杆边：被风吹来的透明伞"},
]


def normalize(path: Path, surface_y: int, sky_ref=None) -> pygame.Surface:
    """统一到 FINAL_H 高，路面线对齐到 SURFACE_FRACTION。

    sky_ref: 顶部补天用的参考色 (c_top, c_edge)——所有段共用第一段的
    天色，避免补出来的天和邻段差一条横线。
    """
    img = pygame.image.load(str(path)).convert_alpha()
    w, h = img.get_size()
    target_surface = round(FINAL_H * SURFACE_FRACTION)

    canvas = pygame.Surface((w, FINAL_H), pygame.SRCALPHA)
    top_pad = target_surface - surface_y
    canvas.blit(img, (0, top_pad))

    if top_pad > 0 and sky_ref:
        c_top, c_edge = sky_ref
        for y in range(top_pad):
            t = y / max(top_pad - 1, 1)
            color = [round(c_top[i] * (1 - t) + c_edge[i] * t) for i in range(3)]
            pygame.draw.line(canvas, (*color, 255), (0, y), (w, y))

    # 底部延伸暗色桥体：按 16 列一组取均色再渐暗，避免逐列的梳齿条纹
    bottom_src = top_pad + h
    if bottom_src < FINAL_H:
        depth = FINAL_H - bottom_src
        for gx in range(0, w, 16):
            gw = min(16, w - gx)
            cols = [img.get_at((x, h - 2)) for x in range(gx, gx + gw, 4)]
            r = sum(c[0] for c in cols) // len(cols)
            g = sum(c[1] for c in cols) // len(cols)
            b = sum(c[2] for c in cols) // len(cols)
            for y in range(depth):
                t = min(y / 60.0, 1.0)
                k = 1.0 - 0.55 * t
                pygame.draw.line(
                    canvas, (round(r * k), round(g * k), round(b * k), 255),
                    (gx, bottom_src + y), (gx + gw - 1, bottom_src + y))
    return canvas


def sky_colors(path: Path):
    """取一段图顶部的天色（供所有段补天共用）。"""
    img = pygame.image.load(str(path)).convert()
    w = img.get_width()

    def row_avg(y):
        cols = [img.get_at((x, y)) for x in range(0, w, 24)]
        return [sum(c[i] for c in cols) // len(cols) for i in range(3)]
    return row_avg(1), row_avg(6)


def pavement_median(img: pygame.Surface):
    """路面带中位色（路面线下 4~20px），用于段间色调匹配。"""
    y0 = round(FINAL_H * SURFACE_FRACTION) + 4
    channels = ([], [], [])
    for y in range(y0, y0 + 16, 3):
        for x in range(0, img.get_width(), 15):
            px = img.get_at((x, y))
            for i in range(3):
                channels[i].append(px[i])
    return [sorted(c)[len(c) // 2] for c in channels]


def match_colors(img: pygame.Surface, gains):
    w, h = img.get_size()
    for y in range(h):
        for x in range(w):
            r, g, b, a = img.get_at((x, y))
            img.set_at((x, y), (
                min(255, round(r * gains[0])),
                min(255, round(g * gains[1])),
                min(255, round(b * gains[2])), a))


def stitch(a: pygame.Surface, b: pygame.Surface) -> pygame.Surface:
    """横向拼接，重叠 SEAM_FADE 像素做交叉渐变。"""
    w = a.get_width() + b.get_width() - SEAM_FADE
    out = pygame.Surface((w, FINAL_H), pygame.SRCALPHA)
    out.blit(a, (0, 0))
    bx = a.get_width() - SEAM_FADE
    out.blit(b, (bx, 0), (SEAM_FADE, 0, b.get_width() - SEAM_FADE, FINAL_H))
    for i in range(SEAM_FADE):
        t = i / (SEAM_FADE - 1)
        x = bx + i
        for y in range(FINAL_H):
            ca = a.get_at((x, y))
            cb = b.get_at((i, y))
            out.set_at((x, y), (
                round(ca[0] * (1 - t) + cb[0] * t),
                round(ca[1] * (1 - t) + cb[1] * t),
                round(ca[2] * (1 - t) + cb[2] * t), 255))
    return out


def detect_puddles(img: pygame.Surface):
    """路面带里明显比周围亮的像素 = 积水倒影。"""
    w = img.get_width()
    y0 = round(FINAL_H * SURFACE_FRACTION) + 3
    rows = range(y0, y0 + 18, 5)
    sums = []
    for x in range(w):
        s = 0
        for y in rows:
            px = img.get_at((x, y))
            s += px[0] + px[1] + px[2]
        sums.append(s / len(list(rows)))
    med = sorted(sums)[w // 2]
    is_puddle = [s > med * 1.18 for s in sums]
    zones, start = [], None
    for x, v in enumerate(is_puddle + [False]):
        if v and start is None:
            start = x
        elif not v and start is not None:
            if zones and start - zones[-1][1] < 40:
                zones[-1][1] = x
            else:
                zones.append([start, x])
            start = None
    return [z for z in zones if z[1] - z[0] >= 50]


def circular_close(parts_stitched: pygame.Surface, first: pygame.Surface) -> pygame.Surface:
    """环形闭合：把首段开头也拼进末尾接缝并裁掉重复，
    使 loop 最后一列恰好衔接到 loop 第一列（首尾平铺无缝）。"""
    head = first.subsurface((0, 0, SEAM_FADE * 2, FINAL_H)).copy()
    f = stitch(parts_stitched, head)
    w = parts_stitched.get_width()
    return f.subsurface((SEAM_FADE, 0, w - SEAM_FADE, FINAL_H)).copy()


if __name__ == "__main__":
    sky_ref = sky_colors(SRC / SEGMENTS[0][0])
    parts = [normalize(SRC / name, sy, sky_ref) for name, sy in SEGMENTS]
    base_med = pavement_median(parts[0])
    for p in parts[1:]:
        med = pavement_median(p)
        gains = [b / max(m, 1) for b, m in zip(base_med, med)]
        if all(0.8 <= g <= 1.25 for g in gains):
            print(f"色调增益 R={gains[0]:.2f} G={gains[1]:.2f} B={gains[2]:.2f}")
            match_colors(p, gains)
        else:
            print(f"色差过大（{[f'{g:.2f}' for g in gains]}），跳过校正")

    loop = parts[0]
    for p in parts[1:]:
        loop = stitch(loop, p)
    loop = circular_close(loop, parts[0])
    pygame.image.save(loop, str(OUT / "loop.png"))
    print(f"loop.png: {loop.get_size()}")

    puddles = detect_puddles(loop)
    total = sum(z[1] - z[0] for z in puddles)
    print(f"水坑 {len(puddles)} 段，占比 {100 * total // loop.get_width()}%")

    data = {
        "image_width": loop.get_width(),
        "image_height": FINAL_H,
        "lights": LIGHTS,
        "pickup_spots": PICKUP_SPOTS,
        "puddles": puddles,
    }
    with open(OUT / "lights.json", "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("lights.json 已写入")
