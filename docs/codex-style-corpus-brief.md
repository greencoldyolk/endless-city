# Codex Task Brief: Style-LoRA Training Corpus · Batch Generation

> Goal: generate **candidate images for style-LoRA training**. The LoRA must
> learn the *style* of this world, so the corpus needs MAXIMUM subject
> diversity with STRICT style unity. These are not game assets — geometry,
> composition and exact sizes are relaxed; palette, light and mood are not.

## Step 0 — Anchors (read all three, in this order)

1. `assets/scenes/loop.png` — master palette (cold blue-violet dusk after rain,
   sparse warm lamps). Reuse the `PALETTE_LINE` from
   `assets/concepts/a1-batch/round1b/manifest.md` verbatim as the color anchor.
2. `assets/concepts/a1-batch/final/a1-far-city-warm-v1.png` — the approved
   warm-state look.
3. `assets/concepts/north-star-ui.png` — brightness floor: nothing gloomier.

## Shared style preamble (prepend to every image prompt)

```
Cinematic matte painting, atmospheric realism. {PALETTE_LINE}. A quiet
empty city at rainy blue-hour dusk — everything rain-wet and gently
overgrown with vines and moss. The city is INTACT, just empty: no
destruction, no apocalypse, no ruins. It feels like everyone left
politely and the machines kept everything running. Sparse warm lights
(lamps, vending machines, a few lonely windows) against cool blue-violet
ambience. The mood is quiet and melancholic yet gentle, never oppressive.
ABSOLUTELY NO readable text, letters, logos, signage, people, faces,
vehicles in focus, or lit screens anywhere.
{WEATHER_LINE}
{SUBJECT_LINE}
```

`{WEATHER_LINE}` — alternate within each bucket, 2 images each:
- warm: `Warm dusk afterglow breaking through after the rain.`
- cold: `Cold gray-blue drizzle light, pale luminous sky, thin rain veils.`

## The 10 subject buckets (4 images each = 40 total)

| # | Bucket | Size to request | SUBJECT_LINE |
|---|---|---|---|
| 01 | station | 1536×1024 | `An old elevated-road bus station: mossy canopy, weathered bench beneath, dim ceiling lamp.` |
| 02 | road-surface | 1536×1024 | `Wet cracked asphalt of an elevated road at eye level: puddles reflecting the sky, moss in the cracks, faded lane markings.` |
| 03 | railing-plants | 1536×1024 | `A rusted guardrail on an elevated road, half swallowed by vines and small wildflowers, raindrops on the leaves.` |
| 04 | vending-machine | 1024×1536 | `A glowing vending machine standing alone in the rain on an elevated road, its warm light spilling onto the wet ground.` |
| 05 | under-bridge | 1024×1536 | `Looking up at massive concrete bridge piers from below, vines hanging, soft fog between the pillars.` |
| 06 | street-level | 1536×1024 | `A narrow empty city street at ground level between mid-rise buildings, wet pavement, one street lamp on.` |
| 07 | lane-objects | 1024×1024 | `A yellow A-frame warning board and a few faded traffic cones on a wet elevated road, no markings on them.` |
| 08 | sky-only | 1536×1024 | `Only sky: dusk clouds over a city, soft shapes with visible edges, no buildings below the lower frame edge.` |
| 09 | mid-distance | 1536×1024 | `A city block seen from a few hundred meters: fog-softened buildings, a couple of lit windows, rooftop water tanks.` |
| 10 | ferris-tease | 1536×1024 | `Far beyond wet rooftops, the faint silhouette of a great ferris wheel dissolving in fog, one string of tiny lights still on.` |

## Generation rules

- $imagegen (gpt-image-2). Request the size listed per bucket; accept whatever
  comes back
- Never refine, edit, or iterate — fresh pulls only. Bad pulls stay; they are
  curation data
- No transparency, no magenta

## Archive

1. All images → `assets/concepts/style-corpus/` named
   `{bucket}-{warm|cold}-{1|2}.png`, e.g. `04-vending-machine-cold-2.png`
2. `assets/concepts/style-corpus/manifest.md`: full prompt per image

## Do NOT

- Touch `assets/scenes/`, `a1-batch/`, any docs, or game code
- Post-process anything
- Invent extra buckets or extra pulls

---

## 人工挑选标准（挑图人用，Codex 忽略本节）

目标：40 张里留 **25–35 张**。宁缺毋滥——LoRA 会把入选图的一切当圣旨学走。

| 检查项 | 说明 |
|---|---|
| □ 色族一致 | 和 loop.png / A1 定稿并排看是一家人（蓝紫冷底+零星暖光） |
| □ 明度结构 | 暗部不死黑、亮部不过曝；雾是亮的空气 |
| □ 湿润感在 | 表面有雨后的反光/水痕 |
| □ 完好而空 | 无废墟感、无灾难感；只是没有人 |
| □ 无文字杂物 | 楼身/牌子/机身上没有可读文字（LoRA 会学会乱写字！） |
| □ 情绪温柔 | 不压抑、不恐怖 |

淘汰即删或移入 `style-corpus/rejected/`（不删也行，训练只喂入选目录）。
每桶至少保 2 张；某桶全废的话记下来，补抽时改词。
