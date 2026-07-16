# ============================================================
# Windows 一键安装脚本:Git + Python 3.11.x(用于 LoRA 训练)
#
# 用法:
#   1. 按 Win 键,输入 "PowerShell",右键 -> 以管理员身份运行
#   2. 执行:Set-ExecutionPolicy -Scope Process Bypass -Force
#   3. 执行:.\setup-windows.ps1
# ============================================================

$ErrorActionPreference = "Stop"

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

Write-Host "==> 检查 winget(Windows 包管理器)..." -ForegroundColor Cyan
if (-not (Test-Command "winget")) {
    Write-Host "未找到 winget。请先从 Microsoft Store 安装『应用安装程序 (App Installer)』:" -ForegroundColor Yellow
    Write-Host "  https://apps.microsoft.com/detail/9NBLGGH4NNS1"
    Write-Host "或者手动下载安装包:"
    Write-Host "  Git:          https://git-scm.com/download/win"
    Write-Host "  Python 3.11:  https://www.python.org/downloads/release/python-3119/"
    exit 1
}

# ---------- Git ----------
Write-Host "==> 安装 Git..." -ForegroundColor Cyan
if (Test-Command "git") {
    Write-Host "Git 已安装:$(git --version)" -ForegroundColor Green
} else {
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
}

# ---------- Python 3.11 ----------
Write-Host "==> 安装 Python 3.11.x..." -ForegroundColor Cyan
$py311 = $false
if (Test-Command "py") {
    try {
        $ver = & py -3.11 --version 2>$null
        if ($ver -match "3\.11") { $py311 = $true }
    } catch {}
}
if ($py311) {
    Write-Host "Python 3.11 已安装:$(py -3.11 --version)" -ForegroundColor Green
} else {
    # Python.Python.3.11 会安装最新的 3.11.x(3.11.9)
    winget install --id Python.Python.3.11 -e --source winget --accept-package-agreements --accept-source-agreements
}

Write-Host ""
Write-Host "==> 安装完成!请关闭并重新打开 PowerShell,然后验证:" -ForegroundColor Green
Write-Host "    git --version"
Write-Host "    py -3.11 --version"
Write-Host ""
Write-Host "==> 下一步(LoRA 训练环境)请参考仓库里的 docs/LORA_SETUP.md" -ForegroundColor Cyan
