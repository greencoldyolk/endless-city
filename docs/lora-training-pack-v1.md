# emptycity 风格 LoRA · 首炉训练配置包 (v1)

> 前提:装机手册(lora-setup-guide.md)Step 0–3 已完成。
> 训练集:`assets/concepts/style-corpus/` 里 36 张 png + 同名 .txt caption
> (rejected/ 与 .md 文件不参与)。触发词:`emptycity style`。

## 1 · 数据集摆放(PC 上,2 分钟)

```
D:\ai\lora\emptycity-v1\
├── img\
│   └── 12_emptycity style\    ← 36 张 png + 36 个 .txt 全部拷进来
├── model\
└── log\
```

- 从 clone 的 repo 里拷 `assets/concepts/style-corpus/*.png` 和 `*.txt`,
  **不要拷 rejected/ 子目录和任何 .md**
- `12_` = repeats;36 张 × 12 × 10 epochs ÷ batch 4 = **1080 步**,风格 LoRA 甜区内

## 2 · kohya GUI 关键字段(LoRA 页签,Flux.1 模式)

| 字段 | 值 | 为什么 |
|---|---|---|
| Pretrained model | ComfyUI 的 `flux1-dev.safetensors` 路径 | 共用,不重复下载 |
| VAE / AE | `ae.safetensors` | 同上 |
| CLIP-L / T5XXL | `clip_l.safetensors` / `t5xxl_fp16.safetensors` | 64G 用 fp16 版 |
| LoRA type | Flux1 | |
| Network Dim / Alpha | **32 / 16** | 风格容量足够,再大易过拟合 |
| Train batch size | **4** | 64G 特权,梯度更稳 |
| Epoch | **10**,每 epoch 存档 | 全存,最后对比挑 |
| Learning rate | **1e-4**,调度 cosine | Flux LoRA 社区标准起点 |
| Optimizer | AdamW8bit | 稳、省 |
| Max resolution | **1024,1024** + Enable buckets | 桶上限 1536,下限 512 |
| Mixed precision | **bf16** | 64G 不用省 |
| Gradient checkpointing | 关 | 显存管够,换训练速度 |
| Cache latents / text encoder outputs | 都开 | 36 张,缓存后飞快 |
| Sample every n epochs | 1,写入下面 4 条测试 prompt | 训练中肉眼监工 |

### 训练中样张 prompt(直接粘进 sample prompts 框)

```
emptycity style, ultra-wide panorama of a foggy city at dusk, sparse lonely window lights --w 1344 --h 768
emptycity style, a bus stop shelter in the rain, wooden bench, warm ceiling lamp --w 1024 --h 1024
emptycity style, a glowing vending machine on a wet elevated road at cold drizzle dusk --w 768 --h 1344
emptycity style, an abandoned amusement park entrance in fog, one string of lights still on --w 1344 --h 768
```

第 4 条是**从没训过的题材**——它才是"学会了风格还是背会了照片"的考题。

## 3 · 开炉后看什么(对照装机手册"三个仪表")

- 前 2 个 epoch 样张还很"Flux 默认味"= 正常;4–6 开始像;8–10 盯过拟合
  (样张复刻训练集构图 / 冒出文字碎片 = 退回上一档)
- 训完把 epoch 6/8/10 的 .safetensors 丢进 ComfyUI(LoRA loader,权重 0.8–1.0),
  用上面 4 条 prompt 各出两张对比,选"风格在、不复读、新题材也像"的那档
- 选出的定稿改名 `emptycity-style-v1.safetensors`,拷回 repo 的
  `art-src/lora/`(新建目录)并 push,两台机器共享

## 4 · 常见翻车对照表

| 症状 | 原因 | 处置 |
|---|---|---|
| 样张全程不像 | lr 太低 / 触发词没进 caption | 查 .txt 第一个词;lr 提到 2e-4 |
| 样张出现文字/水印 | 训练集混入带字图 | 找出删掉,重训(半小时而已) |
| 新题材画不动 | 过拟合 | 用更早的 epoch;或 repeats 降到 8 |
| 出图构图千篇一律 | dim 太大或步数太多 | dim 降 16;或取 epoch 6 |
