# 给 Codex：caption 生产规则

任务：为本目录每张 .png 写一个同名 .txt 训练 caption（Flux LoRA 用）。
已有的 .txt 是占位符，可直接覆盖。

## 三条硬规矩

1. **每条第一个词必须是触发词 `pworldbg`**（触发词不在开头=v1 翻车表头号死因）
2. 紧跟**地图组标签**（`city_edge` / `city_interior` / `amusement_park` /
   `airport`）和**色调标签**（`cool rainy blue hour` / `romantic purple
   twilight` / 夜景用 `cold blue night`），文件名前缀 A=city_edge、
   B=city_interior、C=amusement_park、**D=airport**（2026-07-17 建组）
3. **单行英文，只描述画面内容**（空间结构、光源、物件、天气）。
   不写画风词、画家名、"beautiful/masterpiece"类空话——caption 里写了的
   东西模型认为可被 prompt 控制，反而不烤进权重；风格必须留白给 LoRA 本体

## 注意

- 有 vending machine 的图必须在 caption 里点名它（可控性保险）
- 超宽图（文件名带"超宽"）照常写，训练 bucket 的事不归 caption 管
- 语料宪法与全部裁决见 repo docs/world-bg-v2-corpus-plan.md
