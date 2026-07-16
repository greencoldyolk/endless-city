# Codex Task Brief: A1 Far-City Background · Batch Generation

> Current task: **Round 2 — final focused batch**. Direction locked: **embers**
> (warm dim dusk, sparse lonely lights).
> `round1/` and `round1b/` are archived calibration passes — do not regenerate,
> modify, or delete them. If a Round 3 is ever needed, Claude will add it here;
> **do not improvise one**.

## Lessons already baked into the prompt (do not undo or re-add)

- Clouds are shapes with visible edges and open sky around them — never a dark
  unbroken ceiling (Round 1 rejection reason)
- The far city reads pale, like bright air — never a mid-dark mass (Round 1)
- City structure continues to both edges; only marginal haze (Round 1)
- **No billboard screen in the image at all.** Generated screens looked like
  flat rectangular stickers (Round 1B) — the screen is now a separate sprite
  composited in-engine. Any lit screen in the output = rejected pull
- Window lights sparse and lonely. Dense lights read as an inhabited city
  (Round 1B) — this world is empty, with machines still running

## Steps

### Step 0 — Palette

Reuse the `PALETTE_LINE` from `assets/concepts/a1-batch/round1b/manifest.md`
**verbatim** — do not re-derive it. Re-read `assets/concepts/north-star-ui.png`
once: the brightness floor still applies — nothing you generate may come out
gloomier than that mockup.

### Step 1 — Generate with $imagegen (gpt-image-2)

- Size: request **2304×768** (exactly 3:1; earlier rounds returned 2172×724 —
  that outcome is acceptable, archive whatever comes back)
- **8 images, all from the identical final prompt below** (only `{PALETTE_LINE}`
  substituted). No variant axes this round — this is the focused pull
- Never refine, edit, or iterate on a generated image. Fresh pulls only
- No transparency, no magenta matte — A1 is an opaque full image including sky

### Final prompt (identical for all 8 images)

```
A vast city skyline dissolving into rain haze at dusk, cinematic matte
painting, atmospheric realism. {PALETTE_LINE}. The skyline sits low and
far: building silhouettes recede layer by layer into fog toward a faint
mountain ridge dissolving in haze, and the sky fills the upper 55-60% of
the frame — keep the skyline low, the city must not crowd the sky. The
far city stays pale, barely darker than the sky itself, fog reading as
bright luminous air, every distant layer lifted toward the sky's value
by atmospheric perspective; no single tower dominates. Clouds are shapes
with visible soft edges and open pale sky around them, thinning toward
the top of the frame — never a heavy unbroken cloud ceiling. Moderate
fog under a dim warm dusk. Only sparse scattered window lights: a few
lonely lit windows here and there across the whole city, most windows
dark. The city continues naturally past both left and right edges of
the frame, with only a slight extra veil of haze at the outermost
margins — never an empty wall of fog. The mood is quiet and melancholic
yet gentle, never oppressive. ABSOLUTELY NO lit billboard screens of any
kind, no readable text, letters, logos, signage, neon, no people, faces,
vehicles, roads, or foreground objects anywhere in the image.
```

### Step 2 — Archive

1. Move all 8 images into `assets/concepts/a1-batch/round2/`
2. Naming: `a1-r2-1.png` … `a1-r2-8.png` (generation order)
3. Write `assets/concepts/a1-batch/round2/manifest.md`: the full final prompt
   (with `{PALETTE_LINE}` substituted) once at the top, then one line per image
   with filename and any generation notes

### Do NOT

- Modify `asset-request-v1.md`, touch `assets/scenes/`, `round1/`, `round1b/`,
  or write game code
- Upscale, crop, or post-process any image — that happens downstream
- Execute a Round 3

---

## Round 2 人工验收表（出图人用，Codex 忽略本节）

每张图对照打勾，缩略到 40% 看剪影：

| 检查项 | 说明 |
|---|---|
| □ 天空占比 | 上方 55–60%，天际线压得低（embers 上一轮偏挤，重点看这条） |
| □ 剪影层次 | 40% 缩略下楼群仍分层进雾，远城亮如空气 |
| □ 无抢视线单体 | 没有一栋楼跳出来 |
| □ 色调同族 | 和 loop.png / north-star-ui.png 并排看不违和 |
| □ 孤灯而非灯海 | 亮窗稀疏零星，大部分窗是暗的，不像"有人住" |
| □ 无任何亮屏 | 屏已改引擎合成，图里出现任何亮屏=废卡 |
| □ 无文字/logo/人脸 | 任何位置，放大检查楼身 |
| □ 两端可缝 | 楼群延伸出画外，边缘只轻微加雾，不是空雾墙 |
| □ 情绪不窒息 | 云露边不压顶、远城发亮、不比 north-star 阴郁 |

预期废卡原因：窗灯又变多、天际线爬高挤掉天空、偷偷画了一块屏。

## 定稿后下游（Claude 的活，Codex 忽略）

1. 选定 1 张 → 裁切放大到 ≥2560×720（3.56:1 等效构图）
2. 40% 剪影终检 + 楼身文字扫查
3. 大屏小贴图（asset-request D4）+ 引擎合成 + 呼吸微光
4. 冷态（drizzle 方向已验证）从暖态定稿派生，切换藏雨帘后
