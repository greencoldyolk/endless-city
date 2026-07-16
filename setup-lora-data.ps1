# ============================================================
# LoRA 投料一键脚本:建数据集目录 + 拷语料 + 下载 Flux 模型四件套
#
# 前提(缺一会中途报错,但已完成的步骤不会重做):
#   1. 已装 Python 3.11 和 huggingface_hub[cli](hf 或 huggingface-cli 命令可用)
#   2. 已在浏览器同意 FLUX.1-dev 协议,并 hf auth login 过
#   3. 本仓库已 clone 到 PC(语料从仓库里拷)
#
# 用法(在仓库根目录的 PowerShell 里):
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\setup-lora-data.ps1
# 路径不同时可覆盖:
#   .\setup-lora-data.ps1 -ComfyModels "X:\...\ComfyUI\models" -DatasetRoot "X:\lora\emptycity-v1"
# ============================================================

param(
    [string]$ComfyModels = "Q:\portablecomfy\ComfyUI_windows_portable\ComfyUI\models",
    [string]$DatasetRoot = "Q:\lora\emptycity-v1",
    [string]$RepoDir     = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

# ---------- 找到 hf 命令(新旧名字都试) ----------
$hf = $null
if (Get-Command "hf" -ErrorAction SilentlyContinue) { $hf = "hf" }
elseif (Get-Command "huggingface-cli" -ErrorAction SilentlyContinue) { $hf = "huggingface-cli" }
if (-not $hf) {
    Write-Host "未找到 hf / huggingface-cli。先执行:py -3.11 -m pip install -U `"huggingface_hub[cli]`" 然后重开 PowerShell。" -ForegroundColor Red
    exit 1
}

# ---------- 检查登录 ----------
try {
    & $hf auth whoami *>$null
    if ($LASTEXITCODE -ne 0) { throw "not logged in" }
} catch {
    Write-Host "HuggingFace 未登录。先执行:$hf auth login(token 在 huggingface.co/settings/tokens 建,类型选 Read)" -ForegroundColor Red
    exit 1
}

# ---------- 1. 数据集目录骨架 ----------
Write-Host "==> [1/3] 建数据集目录 $DatasetRoot ..." -ForegroundColor Cyan
$imgDir = Join-Path $DatasetRoot "img\12_emptycity style"
foreach ($d in @($imgDir, (Join-Path $DatasetRoot "model"), (Join-Path $DatasetRoot "log"))) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# ---------- 2. 拷语料(36 png + 36 txt,排除 rejected/ 和 .md) ----------
Write-Host "==> [2/3] 从仓库拷贝语料..." -ForegroundColor Cyan
$corpus = Join-Path $RepoDir "assets\concepts\style-corpus"
if (-not (Test-Path $corpus)) {
    Write-Host "找不到 $corpus —— 请在仓库根目录运行本脚本,或先 git pull 拿到 style-corpus。" -ForegroundColor Red
    exit 1
}
$files = Get-ChildItem $corpus -File | Where-Object { $_.Extension -in ".png", ".txt" }
foreach ($f in $files) { Copy-Item $f.FullName $imgDir -Force }
$png = (Get-ChildItem $imgDir -Filter *.png).Count
$txt = (Get-ChildItem $imgDir -Filter *.txt).Count
Write-Host "    已就位:$png 张 png,$txt 个 caption(应为 36/36)" -ForegroundColor Green
if ($png -ne 36 -or $txt -ne 36) {
    Write-Host "    数量不是 36/36,先检查仓库是否为最新(git pull)再继续训练!" -ForegroundColor Yellow
}

# ---------- 3. 下载模型四件套(已存在的自动跳过;hf 支持断点续传) ----------
Write-Host "==> [3/3] 下载 Flux 模型(共约 33 GB,断了重跑本脚本即可续传)..." -ForegroundColor Cyan
$downloads = @(
    @{ repo = "black-forest-labs/FLUX.1-dev";        file = "flux1-dev.safetensors";       dir = "diffusion_models" },
    @{ repo = "black-forest-labs/FLUX.1-dev";        file = "ae.safetensors";              dir = "vae" },
    @{ repo = "comfyanonymous/flux_text_encoders";   file = "clip_l.safetensors";          dir = "text_encoders" },
    @{ repo = "comfyanonymous/flux_text_encoders";   file = "t5xxl_fp16.safetensors";      dir = "text_encoders" }
)
foreach ($d in $downloads) {
    $destDir = Join-Path $ComfyModels $d.dir
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    $destFile = Join-Path $destDir $d.file
    if (Test-Path $destFile) {
        Write-Host "    跳过(已存在):$($d.file)" -ForegroundColor Green
        continue
    }
    Write-Host "    下载 $($d.file) -> $destDir" -ForegroundColor Cyan
    & $hf download $d.repo $d.file --local-dir $destDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    $($d.file) 下载失败。若是 401/403:确认已在网页同意 FLUX.1-dev 协议且登录的是同一账号。" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "==> 全部就位!接下来:" -ForegroundColor Green
Write-Host "    1. 启动 ComfyUI(run_nvidia_gpu.bat),拖入 flux-dev 示例工作流验证出图"
Write-Host "    2. kohya GUI 按 docs/lora-training-pack-v1.md 第 2 节填表,开炉"
