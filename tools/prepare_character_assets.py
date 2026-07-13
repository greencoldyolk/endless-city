"""把品红底的角色图切成单帧动画资产。

输入（GPT 出图后丢进 art-src/characters/，重跑一遍即可；缺哪张就跳过哪张）：
- art-src/characters/run-raw.png   跑步循环，支持多行网格（如 2 行 × 6 帧）
- art-src/characters/jump-raw.png  跳跃序列（帧间的路障道具会被过滤）
- art-src/characters/reference.png 定妆照（正面+侧面），侧面裁出来当待机帧

输出：assets/characters/run_0.png ... jump_0.png ... idle.png
（art-src/ 里有 .gdignore，Godot 不会导入原始图）

切帧方法：品红转透明后，先按"整行都透明"的空隙切成行，行内再按
"整列都透明"的空隙切成帧，行优先排序。每帧裁到不透明像素的紧致
包围盒。明显偏矮的段是道具/色板不是人，丢弃。

运行：SDL_VIDEODRIVER=dummy .venv/bin/python tools/prepare_character_assets.py
"""
import sys
from pathlib import Path

import pygame

pygame.init()
pygame.display.set_mode((1, 1))

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_road_assets import key_magenta

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "art-src" / "characters"
OUT_DIR = ROOT / "assets" / "characters"

# GPT 偶尔把网格图的某一行整行画成镜像（朝左）。游戏里角色永远朝右，
# 哪张图的哪几行需要水平翻转，在这里手动标定（行号从 0 起）。
FLIP_ROWS = {
    # （2026-07-13 男高版 run-raw 为单行朝右，无需翻转；此表跟原图走，换图必查）
}

# GPT 画的帧往往不是连续相位（大步/收腿姿势乱序堆放），直接顺播腿会
# 来回弹。人工看图标定播放序（索引=网格里行优先的原始位置）：
# 触地→缓冲→过渡→蹬伸→腾空伸展→腾空收腿 × 两个跨步。
FRAME_ORDER = {
    # （2026-07-13 男高版 run-raw 按图上顺序播放，暂不重排；此表跟原图走，换图必查）
}


def _band_segments(is_opaque, length, min_gap):
    """一维分段：连续"有内容"的区间，被 >= min_gap 的空隙隔开。"""
    segments = []
    start, gap = None, 0
    for i in range(length):
        if is_opaque(i):
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                segments.append((start, i - gap + 1))
                start, gap = None, 0
    if start is not None:
        segments.append((start, length))
    return segments


def split_frames(img, min_gap=6, min_height_ratio=0.6, flip_rows=frozenset()):
    """先按透明行切成行，行内按透明列切帧，行优先排序。

    单行横排是"只有一行"的特例，兼容旧图。
    flip_rows 里的行（0 起）整行水平翻转（修正 GPT 画反的方向）。
    """
    w, h = img.get_size()

    def row_opaque(y):
        return any(img.get_at((x, y))[3] > 60 for x in range(0, w, 3))

    frames = []
    for row_idx, (ry0, ry1) in enumerate(_band_segments(row_opaque, h, min_gap)):
        def col_opaque(x):
            return any(img.get_at((x, y))[3] > 60 for y in range(ry0, ry1, 3))

        for x0, x1 in _band_segments(col_opaque, w, min_gap):
            ys = [
                y for y in range(ry0, ry1)
                if any(img.get_at((x, y))[3] > 60 for x in range(x0, x1, 2))
            ]
            if not ys:
                continue
            y0, y1 = min(ys), max(ys) + 1
            frame = img.subsurface((x0, y0, x1 - x0, y1 - y0)).copy()
            if row_idx in flip_rows:
                frame = pygame.transform.flip(frame, True, False)
            frames.append(frame)

    # 过滤道具/色板：高度不到最高帧 60% 的不是人
    tallest = max(f.get_height() for f in frames)
    kept = [f for f in frames if f.get_height() >= tallest * min_height_ratio]
    print(f"  分割出 {len(frames)} 段，保留 {len(kept)} 帧（过滤 {len(frames) - len(kept)} 个道具）")
    return kept


def clear_border(img, margin=4):
    """图片边缘常有一圈生成噪点，直接清透明。"""
    w, h = img.get_size()
    for rect in [(0, 0, w, margin), (0, h - margin, w, margin),
                 (0, 0, margin, h), (w - margin, 0, margin, h)]:
        img.fill((0, 0, 0, 0), rect)


def split_blobs(img, min_height_ratio=0.6):
    """连通域分割：找出所有独立的像素岛，过滤偏矮的（道具）。

    跳跃图里人物和路障在横向上重叠，按列分割切不开，
    只能按"谁和谁连成一片"来分。
    """
    w, h = img.get_size()
    step = 2  # 抽样加速，人物是大块连通的，不会因此断开
    opaque = [[img.get_at((x, y))[3] > 60 for x in range(0, w, step)]
              for y in range(0, h, step)]
    gw, gh = len(opaque[0]), len(opaque)
    seen = [[False] * gw for _ in range(gh)]
    boxes = []

    for gy in range(gh):
        for gx in range(gw):
            if not opaque[gy][gx] or seen[gy][gx]:
                continue
            # 洪水填充这一片，记下它占了哪些格子
            stack = [(gx, gy)]
            seen[gy][gx] = True
            cells = {(gx, gy)}
            x0 = x1 = gx
            y0 = y1 = gy
            while stack:
                cx, cy = stack.pop()
                x0, x1 = min(x0, cx), max(x1, cx)
                y0, y1 = min(y0, cy), max(y1, cy)
                for nx in (cx - 1, cx, cx + 1):
                    for ny in (cy - 1, cy, cy + 1):
                        if (0 <= nx < gw and 0 <= ny < gh
                                and opaque[ny][nx] and not seen[ny][nx]):
                            seen[ny][nx] = True
                            cells.add((nx, ny))
                            stack.append((nx, ny))
            if len(cells) > 200:  # 忽略碎渣
                boxes.append(
                    ((x0 * step, y0 * step, (x1 + 1) * step, (y1 + 1) * step),
                     cells)
                )

    tallest = max(b[3] - b[1] for b, _ in boxes)
    kept = [(b, c) for b, c in boxes if (b[3] - b[1]) >= tallest * min_height_ratio]

    # 排序：先按纵向聚成行（多行网格图），行内按横向位置排
    kept.sort(key=lambda item: (item[0][1] + item[0][3]) / 2)
    rows, row_bottom = [], None
    for box, cells in kept:
        if row_bottom is None or box[1] > row_bottom - tallest * 0.3:
            rows.append([])
            row_bottom = box[3]
        rows[-1].append((box, cells))
        row_bottom = max(row_bottom, box[3])
    kept = [item for row in rows for item in sorted(row, key=lambda it: it[0][0])]
    print(f"  连通域 {len(boxes)} 个，保留 {len(kept)} 帧"
          f"（过滤 {len(boxes) - len(kept)} 个道具，{len(rows)} 行）")

    # 用掩码裁剪：包围盒里可能混进别的连通域（比如人物脚边的路障），
    # 只保留属于本片连通域格子（含一圈膨胀）的像素
    frames = []
    for (x0, y0, x1, y1), cells in kept:
        x1, y1 = min(x1, w), min(y1, h)
        frame = pygame.Surface((x1 - x0, y1 - y0), pygame.SRCALPHA)
        for py in range(y0, y1):
            for px in range(x0, x1):
                gx, gy = px // step, py // step
                if any((gx + dx, gy + dy) in cells
                       for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                    frame.set_at((px - x0, py - y0), img.get_at((px, py)))
        frames.append(frame)
    return frames


def center_on_body(frames):
    """给每帧加透明边距，使"全身像素质心"位于画布水平中心。

    紧致包围盒的中心随手脚伸展乱跳（腿迈多远直接改变包围盒），
    游戏里按图片中心对齐就会左右抖；质心受四肢摆动影响小得多。
    竖直方向不动：包围盒底边就是着地脚，游戏按底边对齐。
    """
    out = []
    for f in frames:
        w, h = f.get_size()
        total, moment = 0.0, 0.0
        for x in range(w):
            col = sum(f.get_at((x, y))[3] for y in range(0, h, 2))
            total += col
            moment += col * x
        cx = moment / total
        cw = int(2 * max(cx, w - cx)) + 2
        canvas = pygame.Surface((cw, h), pygame.SRCALPHA)
        canvas.blit(f, (round(cw / 2 - cx), 0))
        out.append(canvas)
    return out


def load_raw(name):
    path = RAW_DIR / name
    if not path.exists():
        print(f"跳过 {name}（art-src/characters/ 里没有这张图）")
        return None
    img = pygame.image.load(str(path)).convert_alpha()
    print(f"处理 {name} ...")
    key_magenta(img)
    clear_border(img)
    return img


def prepare_sheet(raw_name, prefix, splitter=None):
    img = load_raw(raw_name)
    if img is None:
        return
    if splitter is None:
        frames = split_frames(img, flip_rows=FLIP_ROWS.get(raw_name, frozenset()))
    else:
        frames = splitter(img)
    order = FRAME_ORDER.get(raw_name)
    if order:
        frames = [frames[i] for i in order]
    frames = center_on_body(frames)
    # 清掉旧帧，防止新帧数变少时残留混入动画。
    # .import 也要删：只删 png 的话 Godot 缓存里还有旧帧，游戏照样加载得出来
    for old in list(OUT_DIR.glob(f"{prefix}_*.png")) + list(OUT_DIR.glob(f"{prefix}_*.png.import")):
        old.unlink()
    for i, frame in enumerate(frames):
        out = OUT_DIR / f"{prefix}_{i}.png"
        pygame.image.save(frame, str(out))
        print(f"  {out.name}: {frame.get_size()}")


def prepare_idle():
    """定妆照的侧面（右边那个人）裁出来当待机帧。

    用连通域而不是列切割：定妆照右侧的色板圆点纵跨多行，
    会干扰按行/列的切割，但按连通域就是一个个矮块，直接被过滤。
    """
    img = load_raw("reference.png")
    if img is None:
        return
    frames = split_blobs(img)
    idle = frames[-1]  # 左正面右侧面，取最后一个
    pygame.image.save(idle, str(OUT_DIR / "idle.png"))
    print(f"  idle.png: {idle.get_size()}")


if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # 跑步图也走连通域：大步幅的帧会在列方向探进邻帧地盘，按列切不开
    prepare_sheet("run-raw.png", "run", splitter=split_blobs)
    prepare_sheet("jump-raw.png", "jump", splitter=split_blobs)
    prepare_idle()
