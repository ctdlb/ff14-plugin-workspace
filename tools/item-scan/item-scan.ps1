<#
.SYNOPSIS
    按条件扫描游戏数据表（默认 Item），输出表格或 CSV。

.EXAMPLE
    .\item-scan.ps1 --where "Description.Length >= 150" --columns RowId,Name --limit 10

.EXAMPLE
    .\item-scan.ps1 --where "ItemSearchCategory.RowId != 0" --limit 20 --csv items.csv

.NOTES
    条件写法：Prop[.Sub] [.Length] 运算符 值
    运算符：== != > < >= <=；值可加引号。数字按数值比，其余按字符串比。
    常用：RowId / Name / Description / Description.Length / ItemSearchCategory.RowId
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$exe = Join-Path $root 'bin\Release\net10.0\ItemScan.exe'

# 定位 dotnet：环境变量 FF14DEV_ROOT > 工作区同盘 <盘符>:\FF14Dev > PATH > 常见备用位置
function Resolve-Dotnet {
    $candidates = @()
    if ($env:FF14DEV_ROOT) { $candidates += (Join-Path $env:FF14DEV_ROOT 'dotnet\dotnet.exe') }
    $ws = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # tools\item-scan → 工作区
    if ($ws) {
        $drive = (Get-Item -LiteralPath $ws).PSDrive.Name
        $candidates += "${drive}:\FF14Dev\dotnet\dotnet.exe"
    }
    $candidates += 'E:\FF14Dev\dotnet\dotnet.exe'
    $candidates += 'D:\FF14Dev\dotnet\dotnet.exe'
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    return $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

$dotnet = Resolve-Dotnet
if (-not $dotnet) {
    throw '找不到 dotnet.exe：请先跑 tools\setup-dev-env.ps1 安装，或把 FF14Dev 目录设到环境变量 FF14DEV_ROOT。'
}

if (-not (Test-Path $exe)) {
    Write-Host '首次运行，正在编译…'
    & $dotnet build (Join-Path $root 'ItemScan.csproj') -c Release -v q --nologo | Out-Host
    if (-not (Test-Path $exe)) { throw '编译失败' }
}

& $exe @Args