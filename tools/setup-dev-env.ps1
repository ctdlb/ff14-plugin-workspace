#requires -Version 5.1
<#
.SYNOPSIS
  重建本机 FF14 插件开发环境（换电脑、误删、重装后用）。
.DESCRIPTION
  幂等：目标目录已存在就跳过。默认全部安装到「工作区所在磁盘的根目录」下的 FF14Dev
  （工作区在 D 盘 → D:\FF14Dev；在 E 盘 → E:\FF14Dev），用 -Root 可显式指定别处。
  网络约定：api.github.com / dot.net 直连；github.com 上的下载与 clone 走本地代理。
.PARAMETER Root
  工具与知识库根目录，默认 <工作区所在盘符>:\FF14Dev。
.PARAMETER Workspace
  工作区根目录，默认取脚本所在的父目录（也就是工作区本身）；推导不出来时直接报错，要求用 -Workspace 显式指定，不猜盘符。
.PARAMETER Proxy
  github.com 用的 HTTP 代理，默认 http://127.0.0.1:7897。
.PARAMETER KnowledgeBaseRoot
  四个知识库仓库的父目录，默认 <Root>\KnowledgeBase。
.PARAMETER DevPluginsDir
  插件安装目录，默认自动探测 %APPDATA%\XIVLauncherCN…\dev\devPlugins。
.PARAMETER SkipPluginInstall
  只准备源码，不把插件发行包放进 devPlugins。
.PARAMETER IncludeMyPlugins
  连作者自己的插件一起装（克隆 TextToTalkCN / DalamudPlugins，并把 TextToTalkCN 放进 devPlugins）。
  **默认关闭**：这个脚本会被别的玩家拿去用，他们只需要运行环境和知识库，不该收到作者自己的插件。
.PARAMETER SkipViewerInit
  跳过 EXDViewer 首次设置（检测游戏目录 + 拉起 GUI）。
.PARAMETER SkipViewerLaunch
  只检测游戏目录并打印，不启动 EXDViewer 窗口（自动化/无人值守时用）。
.PARAMETER SkipGitHubToken
  不处理 GitHub 令牌。
.PARAMETER GitHubUser
  存令牌时用的用户名，默认从 origin 地址推断。
.PARAMETER GitHubToken
  个人访问令牌；给了就直接存进 Windows 凭据管理器，不再交互询问。
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\setup-dev-env.ps1
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\setup-dev-env.ps1 -SkipViewer -SkipKnowledge
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Workspace,
    [string]$Proxy = 'http://127.0.0.1:7897',
    [string]$KnowledgeBaseRoot,
    [switch]$SkipDotnet,
    [switch]$SkipGit,
    [switch]$SkipViewer,
    [switch]$SkipKnowledge,
    [switch]$SkipRepos,
    [switch]$SkipPluginInstall,
    [switch]$IncludeMyPlugins,
    [switch]$SkipViewerInit,
    [switch]$SkipViewerLaunch,
    [switch]$SkipGitHubToken,
    [string]$GitHubUser,
    [string]$GitHubToken,
    [string]$DevPluginsDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (-not $Workspace) {
    # 工作区装在哪，脚本就在哪一层的 tools 下，默认取脚本的父目录，换盘不用改脚本。
    # 推导不出来时（例如把脚本内容粘贴到窗口里执行）宁可报错，也不猜盘符——
    # 猜错会跑到别的盘上操作，报错信息全都指向无关文件，很难查。
    if (-not $PSScriptRoot) {
        throw '无法确定工作区位置：本脚本不是以文件方式运行的（$PSScriptRoot 为空）。请用 powershell -File 方式运行，或用 -Workspace 参数显式指定工作区根目录。'
    }
    $Workspace = Split-Path -Parent $PSScriptRoot
}

# 工具与知识库默认跟工作区同盘：工作区在 D 盘就 D:\FF14Dev，在 E 盘就 E:\FF14Dev。
# 真人在终端里跑时先问一句；非交互（被别的脚本调用、输出被接管）就用默认值，不阻塞。
$script:interactive = -not [Console]::IsInputRedirected
# 测试用开关：AI/CI 没有真终端，靠它把「有人在场」的提问分支跑一遍（不影响正常使用）。
if ($env:SETUP_FORCE_INTERACTIVE -eq '1') { $script:interactive = $true }
if (-not $Root) {
    $drive = (Get-Item -LiteralPath $Workspace).PSDrive.Name
    $Root = "${drive}:\FF14Dev"
    if ($script:interactive) {
        Write-Host ''
        Write-Host "工具与知识库准备装到：$Root" -ForegroundColor Cyan
        Write-Host '  （默认放在工作区所在的这块盘，和工作区并排；约 1.2 GB）' -ForegroundColor DarkGray
        $answer = Read-Host '  直接回车＝就装这里；要换位置就直接输入目录，例如 D:\tools\FF14Dev'
        if ($answer) { $Root = $answer.Trim('"').Trim() }
    }
}

$script:failures = New-Object System.Collections.ArrayList
$script:tokenReady = $false

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "    $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

function Add-Failure($msg) {
    [void]$script:failures.Add($msg)
    Write-Host "    !! $msg" -ForegroundColor Red
}

function Assert-Curl {
    $c = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $c) { throw '找不到 curl.exe（Windows 10 1803+ 自带），无法下载。' }
}

function Invoke-Curl {
    param([string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & curl.exe @Arguments 2>&1 | Out-String
    }
    finally { $ErrorActionPreference = $prev }
    if ($LASTEXITCODE -ne 0) {
        throw ("curl 失败（exit {0}）：{1}" -f $LASTEXITCODE, $out.Trim())
    }
    return $out
}

function Get-ReleaseAsset {
    param([string]$Repo, [string]$Pattern)
    $json = Invoke-Curl @('--noproxy', '*', '-sL', '--max-time', '40',
        '-A', 'dsh-setup',
        "https://api.github.com/repos/$Repo/releases/latest")
    $rel = $json | ConvertFrom-Json
    $asset = $rel.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1
    if (-not $asset) { throw "仓库 $Repo 的最新版本 $($rel.tag_name) 里找不到匹配 $Pattern 的资产。" }
    return $asset
}

function Save-Url {
    param([string]$Url, [string]$OutFile, [string]$Note, [switch]$Direct)
    if ($Note) { Write-Host "    下载 $Note" }
    $route = if ($Direct) { @('--noproxy', '*') } else { @('-x', $Proxy) }
    Invoke-Curl (@('-L', '--max-time', '1800', '-A', 'dsh-setup', '-o', $OutFile, $Url) + $route) | Out-Null
    if (-not (Test-Path $OutFile) -or (Get-Item $OutFile).Length -lt 1024) {
        throw "下载结果异常：$OutFile"
    }
    Ok ("{0}（{1:N1} MB）" -f (Split-Path $OutFile -Leaf), ((Get-Item $OutFile).Length / 1MB))
}

function Install-Plugin {
    param([string]$Repo, [string]$Pattern, [string]$Name, [string]$Target)
    $dest = Join-Path $Target $Name
    if (Test-Path (Join-Path $dest "$Name.dll")) {
        Ok "$Name 已存在：$dest"
        return
    }
    $asset = Get-ReleaseAsset -Repo $Repo -Pattern $Pattern
    $zip = Join-Path $env:TEMP $asset.name
    Save-Url -Url $asset.browser_download_url -OutFile $zip -Note "$Name $($asset.name)"
    $stage = Join-Path $env:TEMP ("stage_" + $Name)
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $stage -Force
    Remove-Item $zip -Force
    $src = $stage
    $dirs = @(Get-ChildItem $stage -Directory)
    if ($dirs.Count -eq 1 -and -not (Get-ChildItem $stage -File)) { $src = $dirs[0].FullName }
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    Copy-Item (Join-Path $src '*') -Destination $dest -Recurse -Force
    Remove-Item $stage -Recurse -Force
    Ok "$Name 已放入 $dest"
}

function Invoke-Git {
    param([string]$GitExe, [string[]]$Arguments)
    $out = & $GitExe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("git 失败：{0}" -f ($out -join ' ')) }
    return $out
}

Assert-Curl
# 建根目录：失败时（常见是 C 盘根目录没写权限、或盘满）问用户要不要换盘/换目录，最多三次。
$attempt = 0
while (-not (Test-Path $Root)) {
    $attempt++
    try {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        Ok "已创建根目录 $Root"
    }
    catch {
        $err = $_.Exception.Message
        Write-Host "    !! 无法创建根目录 $Root" -ForegroundColor Red
        Write-Host "       原因：$err" -ForegroundColor DarkGray
        if (-not $script:interactive -or $attempt -ge 3) {
            throw "无法创建根目录 $Root。请用 -Root 指定一个可写目录（例如别的盘，或 -Root ""$env:USERPROFILE\FF14Dev""）。原始错误：$err"
        }
        $answer = Read-Host '       换一个目录？直接输入新目录（例如 D:\FF14Dev），回车＝放弃'
        if (-not $answer) {
            throw "已取消安装：根目录 $Root 无法创建。请用 -Root 指定可写目录后重跑。"
        }
        $Root = $answer.Trim('"').Trim()
    }
}
Step "根目录 $Root"

# ---------------------------------------------------------------- .NET SDK
if (-not $SkipDotnet) {
    $dotnetExe = Join-Path $Root 'dotnet\dotnet.exe'
    if (Test-Path $dotnetExe) {
        Ok ".NET SDK 已存在：$dotnetExe（$(& $dotnetExe --version)）"
    }
    else {
        Step '安装 .NET 10 SDK'
        $installer = Join-Path $env:TEMP 'dotnet-install.ps1'
        Save-Url -Url 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer -Note 'dotnet-install.ps1' -Direct
        # 下载脚本走代理，安装本身不联网
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Channel '10.0' -InstallDir (Join-Path $Root 'dotnet') -NoPath
        if ($LASTEXITCODE -ne 0) { Add-Failure '.NET SDK 安装失败' }
        else { Ok ("SDK {0}" -f (& $dotnetExe --version)) }
    }
}

# ---------------------------------------------------------------- MinGit
$gitExe = Join-Path $Root 'git\cmd\git.exe'
if (-not $SkipGit) {
    if (Test-Path $gitExe) {
        Ok "git 已存在：$gitExe（$(& $gitExe --version)）"
    }
    else {
        Step '安装 MinGit'
        $asset = Get-ReleaseAsset -Repo 'git-for-windows/git' -Pattern 'MinGit-*-64-bit.zip'
        $zip = Join-Path $env:TEMP $asset.name
        Save-Url -Url $asset.browser_download_url -OutFile $zip -Note $asset.name
        Expand-Archive -Path $zip -DestinationPath (Join-Path $Root 'git') -Force
        Remove-Item $zip -Force
        Ok ("git {0}" -f (& $gitExe --version))
    }
}

if (-not (Test-Path $gitExe) -and -not ($SkipGit -and $SkipKnowledge -and $SkipRepos)) {
    Add-Failure "git 不可用，跳过后续 clone：$gitExe"
}

# ---------------------------------------------------------------- EXDViewer
$viewerExe = Join-Path $Root 'EXDViewer\current\viewer.exe'
if (-not $SkipViewer) {
    if (Test-Path $viewerExe) {
        Ok "EXDViewer 已存在：$viewerExe"
    }
    else {
        Step '安装 EXDViewer（便携版，内置 MCP）'
        $asset = Get-ReleaseAsset -Repo 'AtmoOmen/EXDViewer' -Pattern 'EXDViewer-win-Portable.zip'
        $zip = Join-Path $env:TEMP $asset.name
        Save-Url -Url $asset.browser_download_url -OutFile $zip -Note $asset.name
        Expand-Archive -Path $zip -DestinationPath (Join-Path $Root 'EXDViewer') -Force
        Remove-Item $zip -Force
        Ok "EXDViewer 解压完成：$viewerExe"
    }

    # 首次配置：EXDViewer 只认「GUI 保存过」的配置，伪造 app.ron 会被判「找不到已保存的设置」，
    # 所以这里只做两件能自动的事：从 XIVLauncher 配置里查出游戏路径、把 GUI 拉起来让人点一下。
    if (-not $SkipViewerInit) {
        $viewerCfg = Join-Path $env:APPDATA 'EXDViewer\data\app.ron'
        if (Test-Path $viewerCfg) {
            Ok ' EXDViewer 已有配置（跳过首次设置）'
        }
        else {
            Step 'EXDViewer 首次设置'
            $gameDir = $null
            foreach ($cf in @(
                    (Join-Path $env:APPDATA 'XIVLauncherCN\launcherConfigV3.json'),
                    (Join-Path $env:APPDATA 'XIVLauncher\launcherConfigV3.json'))) {
                if (-not $gameDir -and (Test-Path $cf)) {
                    try {
                        $cfg = Get-Content -LiteralPath $cf -Raw -Encoding UTF8 | ConvertFrom-Json
                        $gp = $cfg.GamePath
                        if ($gp) {
                            $cand = Join-Path $gp 'game'
                            if (Test-Path $cand) { $gameDir = $cand } else { $gameDir = $gp }
                        }
                    }
                    catch { }
                }
            }
            if ($gameDir) { Ok " 检测到游戏数据目录：$gameDir" }
            else { Warn ' 没能自动检测到游戏目录，请在设置里手动指认' }
            Warn ' 接下来会弹出 EXDViewer：在「设置」里把游戏目录填成上面那行，然后关掉窗口'
            if ($SkipViewerLaunch) {
                Ok ' （-SkipViewerLaunch：本次不启动 GUI，请自己打开一次）'
            }
            else {
                try {
                    Start-Process -FilePath $viewerExe | Out-Null
                    Ok ' 已启动 EXDViewer，设置完关掉窗口即可'
                }
                catch { Add-Failure "启动 EXDViewer 失败：$($_.Exception.Message)" }
            }
        }
    }
}

# ---------------------------------------------------------------- GitHub 令牌
# 令牌只能由用户提供（生成需要浏览器登录），但「存进凭据管理器」可以自动做：
# 之后 git push 不再弹窗。没有令牌就跳过，不阻塞安装。
if (-not $SkipGitHubToken) {
    $user = $GitHubUser
    if (-not $user) {
        $remoteUrl = (& $gitExe -C $Workspace remote get-url origin 2>$null)
        if ($remoteUrl -match 'github\.com[:/]([^/]+)/') { $user = $Matches[1] }
    }
    if (-not $user) { $user = 'git' }
    $token = $GitHubToken
    if (-not $token -and $script:interactive) {
        Step 'GitHub 令牌（可跳过）'
        Write-Host '  粘贴个人访问令牌后回车即可存进 Windows 凭据管理器；不想现在弄就直接回车跳过。' -ForegroundColor DarkGray
        $token = Read-Host "  令牌（用户 $user）"
    }
    if ($token) {
        Step "把 GitHub 令牌存进凭据管理器（用户 $user）"
        try {
            $payload = "protocol=https`nhost=github.com`nusername=$user`npassword=$token`n`n"
            $payload | & $gitExe credential approve
            if ($LASTEXITCODE -eq 0) { Ok ' 已保存，之后 push 不再弹窗'; $script:tokenReady = $true }
            else { Add-Failure "git credential approve 退出码 $LASTEXITCODE" }
        }
        catch { Add-Failure "存令牌失败：$($_.Exception.Message)" }
    }
    elseif (-not $SkipGitHubToken) {
        Ok ' 未提供令牌，跳过（之后 push 会提示你输入）'
    }
}

# ---------------------------------------------------------------- 知识库
if (-not $SkipKnowledge) {
    Step '克隆知识库源码（--depth 1）'
    if (-not (Test-Path $gitExe)) {
        Add-Failure '没有 git，跳过知识库'
    }
    else {
        $kbRoot = if ($KnowledgeBaseRoot) { $KnowledgeBaseRoot } else { Join-Path $Root 'KnowledgeBase' }
        if (-not (Test-Path $kbRoot)) { New-Item -ItemType Directory -Path $kbRoot -Force | Out-Null }
        $repos = @(
            @{ Name = 'Dalamud'; Url = 'https://github.com/Dalamud-DailyRoutines/Dalamud.git' },
            @{ Name = 'FFXIVClientStructs'; Url = 'https://github.com/Dalamud-DailyRoutines/FFXIVClientStructs.git' },
            @{ Name = 'FFXIVNetworkOpcodes'; Url = 'https://github.com/Yarukon/FFXIVNetworkOpcodes.git' },
            @{ Name = 'imgui'; Url = 'https://github.com/ocornut/imgui.git' }
        )
        foreach ($r in $repos) {
            $dest = Join-Path $kbRoot $r.Name
            if (Test-Path (Join-Path $dest '.git')) {
                Ok "$($r.Name) 已存在"
                continue
            }
            try {
                Invoke-Git -GitExe $gitExe -Arguments @(
                    '-c', "http.proxy=$Proxy", 'clone', '--depth', '1', '--single-branch',
                    $r.Url, $dest) | Out-Null
                Ok "$($r.Name) 克隆完成"
            }
            catch { Add-Failure "$($r.Name) 克隆失败：$($_.Exception.Message)" }
        }
    }
}

# ---------------------------------------------------------------- 插件仓库（默认不装）
# 这个脚本会被别的玩家拿去用：他们只要运行环境 + 知识库 + 规则，
# 不需要作者自己的插件仓库，所以默认跳过，只有 -IncludeMyPlugins 才克隆。
if ($IncludeMyPlugins -and -not $SkipRepos) {
    Step "克隆插件仓库到 $Workspace"
    if (-not (Test-Path $gitExe)) {
        Add-Failure '没有 git，跳过插件仓库'
    }
    else {
        if (-not (Test-Path $Workspace)) { New-Item -ItemType Directory -Path $Workspace -Force | Out-Null }
        $repos = @(
            @{ Name = 'TextToTalkCN'; Url = 'https://github.com/ctdlb/TextToTalkCN.git' },
            @{ Name = 'DalamudPlugins'; Url = 'https://github.com/ctdlb/DalamudPlugins.git' }
        )
        foreach ($r in $repos) {
            $dest = Join-Path $Workspace $r.Name
            if (Test-Path (Join-Path $dest '.git')) {
                Ok "$($r.Name) 已存在"
                continue
            }
            try {
                Invoke-Git -GitExe $gitExe -Arguments @(
                    '-c', "http.proxy=$Proxy", 'clone',
                    $r.Url, $dest) | Out-Null
                Ok "$($r.Name) 克隆完成"
            }
            catch { Add-Failure "$($r.Name) 克隆失败：$($_.Exception.Message)" }
        }
    }
}
elseif (-not $SkipRepos) {
    Step '插件仓库：默认跳过（作者自己的插件，别人用不上）'
    Ok '要一起装请加 -IncludeMyPlugins'
}

# ---------------------------------------------------------------- 插件本装（默认不装）
if ($IncludeMyPlugins -and -not $SkipPluginInstall) {
    $hooks = if ($DevPluginsDir) { $DevPluginsDir } else {
        $cn = Join-Path $env:APPDATA 'XIVLauncherCN\addon\Hooks\dev'
        $intl = Join-Path $env:APPDATA 'XIVLauncher\addon\Hooks\dev'
        if (Test-Path $cn) { Join-Path $cn 'devPlugins' }
        elseif (Test-Path $intl) { Join-Path $intl 'devPlugins' }
        else { Join-Path $cn 'devPlugins' }
    }
    Step "把插件发行包放进 devPlugins：$hooks"
    try { Install-Plugin -Repo 'ctdlb/TextToTalkCN' -Pattern 'TextToTalkCN-v*-cn.zip' -Name 'TextToTalkCN' -Target $hooks }
    catch { Add-Failure "TextToTalkCN 安装失败：$($_.Exception.Message)" }
}
elseif (-not $SkipPluginInstall) {
    Step 'devPlugins：默认跳过（作者自己的插件发行包）'
    Ok '要一起装请加 -IncludeMyPlugins'
}

# 用户级 AGENTS.md 不在这里处理：它的正本在 ctdlb/dsh-plugins 仓库（一个换机装回用的独立仓库），
# 与 FF14 插件开发无关，也不该跟着本工作区发给别的玩家。

# ---------------------------------------------------------------- 收尾
Write-Host ''
Step '结果'
if ($script:failures.Count -eq 0) {
    Ok '全部完成'
}
else {
    Write-Host '    以下步骤失败，需要手动处理：' -ForegroundColor Red
    foreach ($f in $script:failures) { Write-Host "      - $f" -ForegroundColor Red }
}

Write-Host ''
Write-Host '接下来手动做：' -ForegroundColor Cyan
$n = 0
if (-not (Test-Path (Join-Path $env:APPDATA 'EXDViewer\data\app.ron'))) {
    $n++; Write-Host "  $n. 启动一次 $viewerExe ，在「设置」里把游戏目录指到 ...\最终幻想XIV\game，退出"
}
$n++; Write-Host "  $n. 验证数据查询：powershell -NoProfile -File tools\exd.ps1 -Tool health_check"
$n++; Write-Host "  $n. 进游戏 /xlplugins，添加插件库或安装你需要的插件（本脚本默认不装任何插件）"
if (-not $script:tokenReady) {
    $n++; Write-Host "  $n. GitHub 令牌：在凭据管理器存一条 target 为 git:https://<用户名>@github.com 的令牌，推送才走 HTTPS（或重跑本脚本用 -GitHubToken 自动存）"
}
$n++; Write-Host "  $n. 用 AI 客户端打开工作区，让它先读 AGENTS.md"
