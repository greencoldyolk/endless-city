# Windows 安装 Git + Python 3.11 并搭建 LoRA 训练环境

## 一、快速安装(推荐)

以**管理员身份**打开 PowerShell,运行仓库根目录的一键脚本:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\setup-windows.ps1
```

或者直接手动执行两条命令:

```powershell
winget install --id Git.Git -e
winget install --id Python.Python.3.11 -e
```

装完后**重开一个终端**验证:

```powershell
git --version        # 例如 git version 2.50.x
py -3.11 --version   # 例如 Python 3.11.9
```

> Python 3.11.9 是 3.11 系列最后一个提供 Windows 安装包的版本,winget 装的就是它。

## 二、手动安装(winget 不可用时)

| 软件 | 下载地址 | 安装注意 |
|------|---------|---------|
| Git | https://git-scm.com/download/win | 一路默认下一步即可 |
| Python 3.11.9 | https://www.python.org/downloads/release/python-3119/ | 选 "Windows installer (64-bit)",**务必勾选 "Add python.exe to PATH"** |

## 三、LoRA 训练环境

以下以最常见的 **Stable Diffusion LoRA(kohya sd-scripts)** 为例。

### 1. 前置要求

- NVIDIA 显卡,建议 8GB 显存以上(SDXL 建议 12GB+)
- 安装最新 NVIDIA 显卡驱动:https://www.nvidia.com/drivers
- (可选)kohya_ss GUI 官方推荐 Python 3.10.x;用 3.11 跑 sd-scripts 一般没问题,如遇兼容性报错可再装一个 3.10 并用 `py -3.10` 创建虚拟环境。

### 2. 克隆并创建虚拟环境

```powershell
git clone https://github.com/kohya-ss/sd-scripts.git
cd sd-scripts
py -3.11 -m venv venv
.\venv\Scripts\activate
```

### 3. 安装 PyTorch(CUDA 版)和依赖

```powershell
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
pip install -r requirements.txt
pip install xformers --index-url https://download.pytorch.org/whl/cu124
```

验证 GPU 可用:

```powershell
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

输出 `True` 加你的显卡型号即为成功。

### 4. 开始训练

- 想要图形界面:安装 [kohya_ss GUI](https://github.com/bmaltais/kohya_ss)(其 `setup.bat` 会自动处理依赖)。
- 命令行训练示例(SD1.5 LoRA):

```powershell
accelerate launch train_network.py `
  --pretrained_model_name_or_path="模型路径.safetensors" `
  --train_data_dir="训练集目录" `
  --output_dir="输出目录" `
  --network_module=networks.lora `
  --network_dim=32 --network_alpha=16 `
  --resolution=512,512 --train_batch_size=1 `
  --learning_rate=1e-4 --max_train_epochs=10 `
  --mixed_precision=fp16 --save_model_as=safetensors
```

### 如果你练的是 LLM 的 LoRA(不是画图)

用 HuggingFace 生态即可,Python 3.11 完全兼容:

```powershell
py -3.11 -m venv venv
.\venv\Scripts\activate
pip install torch --index-url https://download.pytorch.org/whl/cu124
pip install transformers peft datasets accelerate bitsandbytes
```

## 四、常见问题

- **`winget` 命令不存在**:在 Microsoft Store 安装「应用安装程序 (App Installer)」,或走手动安装。
- **`pip install` 很慢**:可用国内镜像,例如 `pip install -i https://pypi.tuna.tsinghua.edu.cn/simple 包名`(PyTorch CUDA 版仍需官方 index-url)。
- **显存不足 (CUDA out of memory)**:降低 `train_batch_size`、分辨率,或加 `--gradient_checkpointing`、用 8bit 优化器 `--optimizer_type=AdamW8bit`。
- **激活 venv 报执行策略错误**:先运行 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。
