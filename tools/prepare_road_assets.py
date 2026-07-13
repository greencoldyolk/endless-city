"""把品红底（#FF00FF）的道路原图处理成透明底可用资产。

输入输出（GPT 重新出图后，覆盖 -raw 文件再跑一遍即可）：
- assets/roads/road-a-station-raw.png -> assets/roads/road-a-station.png
- assets/roads/road-b-vending-raw.png -> assets/roads/road-b-vending.png

处理内容：
1. 品红转透明，贴边像素按"前景混品红"反推真实透明度和原色（消品红边）
2. 左右裁到路面完全不透明的列，保证 chunk 拼接无缝
3. 打印自动探测的路面线位置（游戏加载时也会自己探测，这里只是给人看）

运行：SDL_VIDEODRIVER=dummy .venv/bin/python tools/prepare_road_assets.py
"""
import pygame

pygame.init()
pygame.display.set_mode((1, 1))

JOBS = [
    ("assets/roads/road-a-station-raw.png", "assets/roads/road-a-station.png"),
    ("assets/roads/road-b-vending-raw.png", "assets/roads/road-b-vending.png"),
]


def key_magenta(surface):
    """品红底转透明。

    生成的"品红"不一定是纯 #FF00FF（见过 (237,7,205)），所以背景色
    从图片四角实测。品红度 m = min(r,b) - g：背景 m=m_bg，正常景物 m≈0。
    透明度 = 1 - m/m_bg，再按混合公式反推原色，边缘不会留品红圈。
    """
    w, h = surface.get_size()
    corners = [
        surface.get_at((x, y))[:3]
        for x, y in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
    ]
    m_values = sorted(min(r, b) - g for r, g, b in corners)
    m_bg = m_values[len(m_values) // 2]  # 取中位数，防某个角落被物件占了
    bg = corners[m_values.index(m_bg) if m_bg in m_values else 0]
    bg_r, bg_g, bg_b = max(c[0] for c in corners), min(c[1] for c in corners), max(c[2] for c in corners)

    # 只处理"和背景连成一片"的像素：从图片边框洪水填充，穿过所有
    # 品红度足够高的像素。画面内部的粉色苔花、紫灰路面虽然品红度
    # 不为零，但碰不到背景，不会被误伤。
    threshold = max(24.0, m_bg * 0.12)

    m_map = [
        [min(row_pixels[0], row_pixels[2]) - row_pixels[1]
         for row_pixels in (surface.get_at((x, y)) for x in range(w))]
        for y in range(h)
    ]

    connected = [[False] * w for _ in range(h)]
    stack = []
    for x in range(w):
        for y in (0, h - 1):
            if m_map[y][x] > threshold and not connected[y][x]:
                connected[y][x] = True
                stack.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if m_map[y][x] > threshold and not connected[y][x]:
                connected[y][x] = True
                stack.append((x, y))
    while stack:
        cx, cy = stack.pop()
        for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
            if (0 <= nx < w and 0 <= ny < h and not connected[ny][nx]
                    and m_map[ny][nx] > threshold):
                connected[ny][nx] = True
                stack.append((nx, ny))

    # 长椅下面、栏杆之间这类被内容围死的"品红口袋"，洪水填充进不去，
    # 但品红度明显高于正常景物（实测最高约 49）的像素只能是背景——
    # 包括处在阴影里被压暗的品红
    definitely_bg = max(55.0, m_bg * 0.25)

    fringe = []  # 需要处理的过渡像素 (x, y, alpha)
    for y in range(h):
        for x in range(w):
            if not connected[y][x] and m_map[y][x] < definitely_bg:
                continue
            alpha = 1.0 - m_map[y][x] / m_bg
            # 太接近背景的残留（噪点）直接清零
            if alpha < 0.25:
                surface.set_at((x, y), (0, 0, 0, 0))
                m_map[y][x] = 999  # 标记为"非内容"，借色时跳过
            else:
                fringe.append((x, y, alpha))
                m_map[y][x] = 998

    # 过渡像素的颜色不可信：生成图的边缘不是干净的线性混合，
    # 按公式反推会系统性偏红（细护栏、草叶轮廓整体红移）。
    # 改为借用最近的纯内容像素的颜色，只保留算出的透明度。
    def is_content(x, y):
        return m_map[y][x] <= threshold

    for x, y, alpha in fringe:
        color = None
        for radius in range(1, 7):
            best = None
            for ny in range(max(0, y - radius), min(h, y + radius + 1)):
                for nx in range(max(0, x - radius), min(w, x + radius + 1)):
                    if is_content(nx, ny):
                        best = surface.get_at((nx, ny))
                        break
                if best:
                    break
            if best:
                color = best
                break
        if color is None:
            # 周围找不到纯内容（孤立的半品红噪团），当背景清掉
            surface.set_at((x, y), (0, 0, 0, 0))
        else:
            surface.set_at(
                (x, y), (color[0], color[1], color[2], int(alpha * 255))
            )


def find_surface_row(surface, min_run=60):
    """路面线 = 连续 min_run 行都几乎整行不透明的起始行。

    要求连续成片是为了跳过护栏横杆和路面上的花草带（都不够厚）。
    """
    w, h = surface.get_size()
    run_start, run = 0, 0
    for y in range(h):
        opaque = sum(
            1 for x in range(0, w, 8) if surface.get_at((x, y))[3] > 200
        )
        if opaque / (w // 8) > 0.95:
            if run == 0:
                run_start = y
            run += 1
            if run >= min_run:
                return run_start
        else:
            run = 0
    raise ValueError("没找到连续不透明的路面")


def solid_col_range(surface, surface_row):
    """在路面区域找左右两端完全不透明的列，裁掉半透明边缘。"""
    w = surface.get_width()
    rows = range(surface_row + 5, surface_row + 45, 10)

    def col_solid(x):
        return all(surface.get_at((x, y))[3] > 200 for y in rows)

    left = next(x for x in range(w) if col_solid(x))
    right = next(x for x in range(w - 1, -1, -1) if col_solid(x))
    return left, right


def pavement_mean(img, surface_row):
    """路面带的中位颜色，用于两张图之间的色调匹配。

    只采路面线下 5~30 行（再深就是暗色的平台侧壁了），
    用中位数避免被杂草、阴影这些局部暗块拉偏。
    """
    channels = ([], [], [])
    for y in range(surface_row + 5, surface_row + 30, 3):
        for x in range(0, img.get_width(), 15):
            r, g, b, a = img.get_at((x, y))
            if a > 200:
                channels[0].append(r)
                channels[1].append(g)
                channels[2].append(b)
    return [sorted(c)[len(c) // 2] for c in channels]


def match_colors(img, gains):
    """按通道增益整体调色（拉齐两张图的色调，接缝不跳色）。"""
    w, h = img.get_size()
    for y in range(h):
        for x in range(w):
            r, g, b, a = img.get_at((x, y))
            if a == 0:
                continue
            img.set_at((x, y), (
                min(255, int(r * gains[0])),
                min(255, int(g * gains[1])),
                min(255, int(b * gains[2])),
                a,
            ))


if __name__ == "__main__":
    processed = []
    for raw_path, out_path in JOBS:
        img = pygame.image.load(raw_path).convert_alpha()
        key_magenta(img)
        surface_row = find_surface_row(img)
        left, right = solid_col_range(img, surface_row)
        trimmed = img.subsurface(
            (left, 0, right - left + 1, img.get_height())
        ).copy()
        processed.append((out_path, trimmed, surface_row))
        print(f"{out_path}: 路面线 y={surface_row}，裁边 {left}..{right}")

    # 色调匹配：以第一张（车站段）为基准，把其余图的路面平均色拉齐，
    # 消除不同批次生成的色差，接缝处不跳色
    base_mean = pavement_mean(processed[0][1], processed[0][2])
    for out_path, img, surface_row in processed[1:]:
        mean = pavement_mean(img, surface_row)
        gains = [b / m for b, m in zip(base_mean, mean)]
        if all(0.85 <= g <= 1.15 for g in gains):
            print(f"{out_path}: 色调增益 R={gains[0]:.2f} G={gains[1]:.2f} B={gains[2]:.2f}")
            match_colors(img, gains)
        else:
            print(f"{out_path}: 色差过大（增益 {[f'{g:.2f}' for g in gains]}），"
                  "跳过校正——建议用参考图重新生成这一张")

    # 各图路面线以下的厚度裁成一致，站立线对齐后平台底边才不会错位
    common_depth = min(
        img.get_height() - row for _, img, row in processed
    )
    for out_path, img, surface_row in processed:
        cropped = img.subsurface(
            (0, 0, img.get_width(), surface_row + common_depth)
        ).copy()
        pygame.image.save(cropped, out_path)
        print(f"{out_path}: {cropped.get_size()}（路面下厚度统一为 {common_depth}）")
