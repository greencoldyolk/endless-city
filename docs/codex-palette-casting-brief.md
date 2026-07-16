# Codex Task Brief: Palette Casting · 7 Color Directions, One Scene

> Goal: choose the game's color constitution deliberately. **One identical
> scene, seven palettes.** Composition variety is NOT wanted — the closer the
> seven images are in content, the better the color comparison. This brief is
> standalone; do not touch other briefs or assets.

## The fixed scene (identical for all 7; only {PALETTE_LINE} changes)

```
Cinematic matte painting, atmospheric realism, after the rain. An
overgrown elevated highway seen from the side: a mossy bus-station
canopy sheltering a weathered bench, a glowing vending machine spilling
light onto the wet road, vines swallowing the rusted guardrail, puddles
mirroring the sky, and beyond the railing a vast fog-softened city
skyline with a faint mountain ridge, beneath a wide dusk sky filling the
upper half of the frame. {PALETTE_LINE} The city is INTACT, just empty —
no destruction, no ruins; it feels like everyone left politely and the
machines kept everything running. Quiet, melancholic yet gentle, never
oppressive. ABSOLUTELY NO readable text, letters, logos, signage,
people, faces, vehicles, or lit screens anywhere.
```

- Size: request **2304×768** for every image (game-view aspect; accept whatever
  comes back)
- **1 image per palette, 7 total.** Never refine or iterate; single fresh pull
  each. If one pull is a technical failure (deformed), one re-pull max

## The 7 palettes ({PALETTE_LINE})

| Code | Name | PALETTE_LINE |
|---|---|---|
| A | incumbent 蓝紫雨暮 | Reuse the `PALETTE_LINE` from `assets/concepts/a1-batch/round1b/manifest.md` verbatim |
| B | 青瓷雨暮 | `Cool celadon and gray-green rain dusk: jade-teal fog, moss-green shadows, warm tangerine lamp accents.` |
| C | 暖褐薄暮 | `Warm sepia dusk: amber and umber haze, faded brown shadows, a soft cream sky, lamps glowing golden.` |
| D | 靛蓝深暮 | `Deep indigo blue hour: cold navy shadows, slate-blue sky, the warm lights burning noticeably brighter against the dark.` |
| E | 桃灰黄昏 | `Soft peach-pink dusk over warm gray: pastel rose sky, dove-gray buildings, gentle apricot lamps.` |
| F | 银灰雨日 | `Almost monochrome silver rain-day: pale gray light, white fog, colors nearly drained except the faint warm lamps.` |
| G | 金绿雨后 | `After-rain golden light washing over wet greenery: honey light on vines and moss, teal-gray shadows, a bright soft sky.` |

## Archive

1. Images → `assets/concepts/palette-casting/` named `palette-A.png` … `palette-G.png`
2. `manifest.md` there: full prompt per image

## Do NOT

- Touch any other directory or brief; no post-processing; no extra palettes

---

## 挑色指南（选色人用，Codex 忽略本节）

这是在选**游戏的色彩宪法**，会锁进 LoRA 和所有后续资产。三个问题按顺序问自己：

1. **想不想住进去**——第一眼的身体反应，别分析；
2. **暖点跳不跳**——售货机/灯的暖光在这个底色里是不是全画面最想看的点
   （这个游戏的光语言全靠"冷底暖点"成立）；
3. **缩到 40% 还认得吗**——小屏幕上色彩关系是否依然清楚。

注意：A 是现任（A1 定稿、北极星都是它的家族），有主场优势——尽量把七张
洗乱了盲看再揭代号。选出前二后如果纠结，可以让下一轮只对这两个色各抽
两张车站近景加赛。
