# LoRA 工作站装机手册(4090 机器用)

> 目标:装好 ComfyUI(出图)+ kohya_ss(训练),下载 Flux.1-dev 全套模型,
> 建好数据集目录。做完这些,等语料挑选完成,拿到 caption 和训练配置就能开炉。
> 以下按 Windows 写;Linux 只有安装命令不同,逻辑一致。

## Step 0 · 检查底子(5 分钟)

- [ ] 磁盘空闲 ≥ 100 GB(模型约 40G + 环境 + 产出)
- [ ] NVIDIA 驱动更新到近期版本(GeForce Experience 或官网),`nvidia-smi` 能看到卡
- [ ] 安装 [Git for Windows](https://git-scm.com/download/win)
- [ ] 安装 [Python 3.11.x](https://www.python.org/downloads/)(装时勾选 **Add to PATH**;
      不要装 3.13,生态兼容最稳的是 3.10/3.11)

## Step 1 · ComfyUI(出图端,约 20 分钟 + 下载时间)

1. 最省事:下载 **ComfyUI Portable**(官方 GitHub Releases 的
   `ComfyUI_windows_portable_nvidia.7z`),解压即用,自带独立 Python
2. 启动:双击 `run_nvidia_gpu.bat`,浏览器开 `http://127.0.0.1:8188`
3. 模型下载(Flux.1-dev 在 HuggingFace 上是 gated,先注册账号点同意):
   | 文件 | 放到 | 说明 |
   |---|---|---|
   | `flux1-dev.safetensors` (~23G) | `models/diffusion_models/` | 主模型,黑森林官方仓库 |
   | `ae.safetensors` (~335M) | `models/vae/` | Flux VAE,同仓库 |
   | `clip_l.safetensors` (~246M) | `models/text_encoders/` | comfyanonymous/flux_text_encoders |
   | `t5xxl_fp16.safetensors` (~9.8G) | `models/text_encoders/` | 同上;显存 64G 用 fp16 版 |
4. 验证:官方 Flux 示例工作流(ComfyUI examples 页面有 flux-dev 的 json,
   拖进浏览器窗口即加载),跑一张 1024×1024,一两分钟内出图即通

## Step 2 · kohya_ss(训练端,约 20 分钟)

```bat
git clone --recursive https://github.com/bmaltais/kohya_ss.git
cd kohya_ss
setup.bat        :: 选 1 安装;装完选 torch/CUDA 默认项
gui.bat          :: 启动网页 GUI,默认 http://127.0.0.1:7860
```

- 训练用的模型文件和 ComfyUI 共享:GUI 里路径直接指向上面下载的四个文件,
  不用重复下载
- Linux 用 `setup.sh` / `gui.sh`,其余一致

## Step 3 · 数据集目录骨架(2 分钟)

```
D:\lora\emptycity-v1\
├── img\
│   └── 12_emptycity style\     ← 挑选后的图 + 同名 .txt caption 放这里
├── model\                      ← 训练产出的 .safetensors
└── log\
```

- 目录名 `12_emptycity style` 不是随便起的:`12` 是 **repeats**(每个 epoch
  每张图被看 12 遍),下划线后面是**触发词**。30 张 × 12 repeats × 10 epochs
  ≈ 3600 步,是风格 LoRA 的合理区间(实际步数以我给的配置为准)
- 图片到位后,每张旁边放同名 `.txt`(caption),由 Claude 生成后一起拷过来

## Step 4 · 等投料

语料挑选完成后,Claude 交付:
1. 入选图打包(缩放/裁剪到训练分辨率桶)
2. 每张的 `.txt` caption(含触发词 `emptycity style`)
3. kohya 训练配置 json(按 64G 显存调好:fp16、batch 4、
   network dim 32 / alpha 16、分辨率桶 1024、AdamW8bit、lr 1e-4、
   每 epoch 存档 + 4 张固定样张)
4. 训练中怎么看曲线、怎么从 10 个 epoch 存档里挑最佳的验收清单

## 训练时的三个仪表(先记住,开炉时用)

- **Loss 曲线**:前期快速下降后进入缓坡属正常;完全不降=学不动(lr 太小或
  数据问题),断崖下降到极低=开始死记硬背(过拟合前兆)
- **样张**(训练器每个 epoch 用固定 prompt 出的小图):风格越来越像=健康;
  开始复刻训练集的具体构图/冒出文字碎片=过拟合,取前一个 epoch 的存档
- **挑存档**:最终不是取"最后一个",而是拿 3–4 个 epoch 的存档在 ComfyUI 里
  用同一组测试 prompt(全景/车站/物件/**从没训过的题材**各一)对比,
  选"风格在、又不复读"的那个
