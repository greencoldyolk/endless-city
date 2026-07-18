# pworldbg-v0 风格 LoRA · 配方档案

> 定档：2026-07-17，用户裁决 epoch 6。
> 模型本体不进 git（153MB 超 GitHub 上限），两台机器各存一份：
> - PC：`Q:\lora\pworldbg-v0\model\pworldbg-v0-000006.safetensors`
> - Mac：`art-src/lora/pworldbg-v0.safetensors`
> - md5：`713755296d66972fec9aae2f6ab517a0`

## 训练配方（可复现）

- 底模 Flux.1-dev + clip_l + t5xxl_fp16 + ae（ComfyUI 共用那套）
- 语料：repo `assets/concepts/world-bg-v2/corpus-candidates/` 18 png + 18 txt
  （commit 705342c 状态），触发词 `pworldbg`
- kohya：batch 2 / repeats 8（目录 `8_pworldbg`）/ 10 epochs ≈ 720 步、
  lr 1e-4 cosine、AdamW8bit、Dim 16 / Alpha 8、1024+buckets(512–1536)、
  bf16、双缓存、梯度检查点开、seed 42
- 实际机器：64G 内存（v1 手册"64G 显存"系笔误）

## 选档依据（2026-07-17 遥控评测）

- e1–e3 素模主导；e4 LoRA 影响过阈值；**e7 起服从侵蚀**
  （茶杯人数 e5:1→e7:2、乱码招牌 e5:0→e7:2、红点增多）→ 取 e6
- 六卷战绩：天桥(防复读)✓、茶杯(组内泛化)✓、她开/关(三层制开关)✓✓、
  机场(语料外)△需降权、远景层毛坯✓
- 七帧旅程实验：车站→游乐园色温/地标/尺度全连续，"一炉两章节"验收通过

## 使用纪律

- **语料内题材：权重 0.85；语料外或指令敏感：0.7**（机场的人 0.7 退场）
- 采样：euler + simple、steps 20–28、guidance 3.5、FluxGuidance 节点
- prompt 常备护栏：no palm trees / warm golden lights（夜景轮灯防粉紫）/
  no text, no lettering / empty carousel with no riders（见惊悚阈值条目）

## 已知系统病（v2 补课清单）

1. 红点渗漏（语料未洗的红色航空灯被学入）——v2 前 inpaint 清账
2. 乱码文字（底模先验，大门/招牌高发）——prompt 压制+后期
3. 夜景轮灯偏粉紫霓虹——prompt 写死暖金
4. 机场组零语料——v2 补
5. 木马骑手错觉——见 corpus-plan 惊悚阈值条目
