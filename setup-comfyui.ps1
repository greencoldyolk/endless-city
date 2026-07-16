# ============================================================
# ComfyUI Portable 一键安装脚本(NVIDIA / 4090)
#
# 版本:v0.28.0(2026-07-15 发布,ComfyUI_windows_portable_nvidia.7z,约 1.95 GB)
# 自带独立 Python,不依赖也不影响系统里的 Python 3.11。
#
# 用法(普通 PowerShell 即可,无需管理员):
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\setup-comfyui.ps1                    # 默认装到 D:\
#   .\setup-comfyui.ps1 -InstallDir E:\AI  # 或指定目录
# ============================================================

param(
    [string]$InstallDir = "D:\"
)

$ErrorActionPreference = "Stop"

$Version = "v0.28.0"
$AssetName = "ComfyUI_windows_portable_nvidia.7z"
$Url = "https://github.com/comfyanonymous/ComfyUI/releases/download/$Version/$AssetName"
$Archive = Join-Path $InstallDir $AssetName

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

# ---------- 磁盘空间检查(解压后 + 模型约需 100 GB) ----------
$drive = (Get-Item $InstallDir).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB, 1)
Write-Host "==> 安装盘剩余空间:$freeGB GB" -ForegroundColor Cyan
if ($freeGB -lt 100) {
    Write-Host "警告:手册要求 ≥100 GB(Flux 模型全套约 40 GB),当前不足,继续安装但请先清理空间再下模型。" -ForegroundColor Yellow
}

# ---------- 下载 ----------
if (Test-Path $Archive) {
    Write-Host "==> 发现已下载的 $AssetName,跳过下载" -ForegroundColor Green
} else {
    Write-Host "==> 下载 ComfyUI $Version(约 1.95 GB,取决于网速)..." -ForegroundColor Cyan
    try {
        Start-BitsTransfer -Source $Url -Destination $Archive
    } catch {
        Write-Host "BITS 下载失败,改用 Invoke-WebRequest..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $Url -OutFile $Archive
    }
}

# ---------- 确保有 7-Zip ----------
$sevenZip = $null
foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
    if (Test-Path $p) { $sevenZip = $p; break }
}
if (-not $sevenZip) {
    Write-Host "==> 未找到 7-Zip,用 winget 安装..." -ForegroundColor Cyan
    winget install --id 7zip.7zip -e --accept-package-agreements --accept-source-agreements
    $sevenZip = "$env:ProgramFiles\7-Zip\7z.exe"
}

# ---------- 解压 ----------
$TargetDir = Join-Path $InstallDir "ComfyUI_windows_portable"
if (Test-Path $TargetDir) {
    Write-Host "==> $TargetDir 已存在,跳过解压(如需重装请先删除该目录)" -ForegroundColor Yellow
} else {
    Write-Host "==> 解压到 $InstallDir ..." -ForegroundColor Cyan
    & $sevenZip x $Archive "-o$InstallDir" -y | Out-Null
}

Write-Host ""
Write-Host "==> ComfyUI $Version 安装完成!" -ForegroundColor Green
Write-Host ""
Write-Host "启动方式:双击 $TargetDir\run_nvidia_gpu.bat"
Write-Host "然后浏览器打开 http://127.0.0.1:8188"
Write-Host ""
Write-Host "Flux.1-dev 模型放置(见 docs/lora-setup-guide.md Step 1):" -ForegroundColor Cyan
Write-Host "  flux1-dev.safetensors    -> $TargetDir\ComfyUI\models\diffusion_models\"
Write-Host "  ae.safetensors           -> $TargetDir\ComfyUI\models\vae\"
Write-Host "  clip_l.safetensors       -> $TargetDir\ComfyUI\models\text_encoders\"
Write-Host "  t5xxl_fp16.safetensors   -> $TargetDir\ComfyUI\models\text_encoders\"
Write-Host ""
Write-Host "如启动报 CUDA/驱动版本错误:先更新 NVIDIA 驱动;实在不能升驱动时,改用同一 Release 页的 ComfyUI_windows_portable_nvidia_cu126.7z(旧驱动兼容版)。" -ForegroundColor Yellow
