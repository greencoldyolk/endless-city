# Codex Task Brief: Protagonist Face Casting · Round 1 (Direction)

> Goal: choose the protagonist's identity direction (hair + eyes + overall
> presence). Round 1 varies HAIR/COLOR direction only; everything else is
> locked. Rounds 2 (feature tuning) and 3 (final reference sheet) will be
> added after human review — do not improvise them.

## Locked for every image

```
Painterly semi-realistic digital portrait, anime facial proportions,
realistic fabric rendering, soft luminous rim light. Bust portrait of a
quiet, aloof teenage boy (about 17), slender. He wears a dark
high-collar zip-up windbreaker with the collar zipped all the way up,
hiding his mouth and chin — only his eyes, brows and nose bridge are
visible. Calm, distant gaze, slightly narrowed eyes, composed — cool
but never hostile or gloomy. Background: soft out-of-focus rainy
blue-hour city bokeh, cold blue-violet ambience with one warm light
source from the side catching his hair and collar edge. Fine drizzle
in the air. ABSOLUTELY NO text, no logos, no visible mouth, no smiling,
no other people.
{HAIR_LINE}
```

- Size: **1024×1536** (portrait)
- **2 images per direction × 4 directions = 8 total**
- Never refine or iterate; fresh pulls only
- This is an ORIGINAL character: do not imitate any existing anime/game
  character's exact design

## The 4 hair directions ({HAIR_LINE})

| Code | Direction | HAIR_LINE |
|---|---|---|
| ash | 银灰白 | `Silvery ash-white hair, soft straight fringe falling over his brows, slightly tousled by wind.` |
| ink | 墨黑 | `Ink-black hair, straight soft fringe over his brows, a few strands catching the warm rim light.` |
| oat | 亚麻浅棕 | `Light ash-brown hair, loose soft fringe, gently windblown.` |
| slate | 青灰蓝 | `Muted slate blue-gray hair, soft fringe over his brows, faintly catching the cold light.` |

Eye color: pick what harmonizes with each hair direction (muted tones only —
gray, dark brown, dim blue-violet; nothing neon or saturated).

## Archive

- `assets/concepts/face-casting/round1/` named `face-r1-{code}-{1|2}.png`
- `manifest.md` there: full prompt per image

---

## Round 2 — jacket color swap (execute when asked)

Final recipe direction: **everything stays as the Round 1 ash images —
dark jacket (never light-colored), silvery ash-white hair, muted gray-blue
eyes. ONLY the hairstyle changes** (to distance the face from the
reference character). Hair color line for both variants:
`silvery ash-white hair, muted gray-blue eyes`.

2 per hairstyle, 4 total:

| Code | HAIRSTYLE line |
|---|---|
| part | `thin, choppy fringe swept slightly to one side, one eyebrow showing` |
| wind | `slightly longer top hair pushed back and tousled by wind, forehead partly visible` |

Archive to `assets/concepts/face-casting/round2/` as
`face-r2-{part|wind}-{1|2}.png` plus manifest.md. Fresh pulls only.

## Round 3 — the ordinary boy (execute when asked)

Round 3 recipe: **slate hair + Round 2 hairstyles, still handsome**
(silver-white retired for being too "chosen one"; slate keeps the cool
tone without the halo). Same locked block as Round 1 EXCEPT:

- Hair color: `muted slate blue-gray hair, faintly catching the cold
  light` (from Round 1 slate)
- Hairstyles, 2 images each:
  - `face-r3-part-{1|2}`: thin choppy fringe swept slightly to one side,
    one eyebrow showing
  - `face-r3-wind-{1|2}`: slightly longer top hair pushed back and
    tousled by wind, forehead partly visible
- Face: handsome as in previous rounds; eyes muted gray-blue

**4 images**, archive to `assets/concepts/face-casting/round3/`
plus manifest.md. Fresh pulls only.

## 选角指南（选人用，Codex 忽略本节）

这是在选"你要陪伴很多小时的那个人"。按顺序问：

1. **想不想当他**——第一眼的投射感，别分析；
2. **清冷 ≠ 阴郁**——眼神应该是"安静地看着远处"，不是"心里有仇"；
3. **剪影测试**——缩到指甲盖大小，发型轮廓还认得出他吗？（跑动 sprite
   全靠发型剪影 + 领子形状活着）；
4. **既视感检查**——像不像某个你叫得出名字的现有角色？像=毙（换装可救的
   程度除外）。

选出 1–2 个方向后告诉 Claude：胜出方向 + 想微调的点（眼型再怎样、刘海
再怎样、年龄感偏大偏小）。Round 2 据此细修五官。
