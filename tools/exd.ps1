#requires -Version 5.1
<#
    exd.ps1 — 通过 EXDViewer 内置 MCP（stdio）查询 FFXIV 游戏数据表 / 资源

    用法（注意：从命令行传 JSON 时 PowerShell 5.1 会吃掉双引号，改用 -JsonB64 或 -Params）：
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\exd.ps1 -ListTools
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\exd.ps1 -Tool get_row -Params 'name=Item;row_id=4551'
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\exd.ps1 -Tool query_rows -Params 'name=Item;limit=5'
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\exd.ps1 -Tool query_rows -JsonB64 <base64(json)>

    -Params 语法：`键=值;键=值`，纯数字按整数传，其余按字符串；复杂结构用 -JsonB64。

    说明：
      - 首次使用前必须先启动一次 GUI（viewer.exe）完成设置，否则 MCP 会报「找不到已保存的设置」。
      - 配置存于 %APPDATA%\EXDViewer\data\app.ron，游戏根目录由设置界面写入。
      - 返回值为 MCP 的 result.content[].text，若为 JSON 则格式化输出。
#>
param(
    [string]$Exe = '',
    [switch]$ListTools,
    [string]$Tool,
    [string]$Json = '',
    [string]$JsonB64 = '',
    [string]$Params = '',
    [switch]$Brief,
    [int]$TimeoutMs = 180000
)

$ErrorActionPreference = 'Stop'

# 定位 EXDViewer：-Exe > 环境变量 FF14DEV_ROOT > 工作区同盘 <盘符>:\FF14Dev > 常见备用位置
if (-not $Exe) {
    $candidates = @()
    if ($env:FF14DEV_ROOT) { $candidates += (Join-Path $env:FF14DEV_ROOT 'EXDViewer\current\viewer.exe') }
    if ($PSScriptRoot) {
        $drive = (Get-Item -LiteralPath $PSScriptRoot).PSDrive.Name
        $candidates += "${drive}:\FF14Dev\EXDViewer\current\viewer.exe"
    }
    $candidates += 'E:\FF14Dev\EXDViewer\current\viewer.exe'
    $candidates += 'D:\FF14Dev\EXDViewer\current\viewer.exe'
    $Exe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) {
    Write-Error "找不到 EXDViewer。请先跑 tools\setup-dev-env.ps1 安装，或用 -Exe 指定 viewer.exe 的完整路径（也可设环境变量 FF14DEV_ROOT 指向 FF14Dev 目录）。"
    exit 1
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $Exe
$psi.Arguments              = '--mcp-stdio'
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true
$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
$psi.StandardErrorEncoding  = [Text.Encoding]::UTF8

$proc = [System.Diagnostics.Process]::Start($psi)
$outQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
$errQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]

$null = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action {
    if ($EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) }
} -MessageData $outQueue
$null = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
    if ($EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) }
} -MessageData $errQueue

$proc.BeginOutputReadLine()
$proc.BeginErrorReadLine()

function Send-Json($obj) {
    $line = $obj | ConvertTo-Json -Compress -Depth 20
    # PS 5.1 的 ProcessStartInfo 没有 StandardInputEncoding，直接写 UTF-8 字节
    $bytes = [Text.Encoding]::UTF8.GetBytes($line + "`n")
    $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $proc.StandardInput.BaseStream.Flush()
}

# 等待某个 id 的响应行；返回该行 JSON 字符串
function Wait-Response([int]$id, [int]$timeoutMs) {
    $deadline = (Get-Date).AddMilliseconds($timeoutMs)
    while ((Get-Date) -lt $deadline) {
        $line = $null
        $batch = @()
        while ($outQueue.TryDequeue([ref]$line)) { $batch += $line }
        foreach ($l in $batch) {
            if ($l -match ('"id"\s*:\s*' + $id + '\b')) { return $l }
        }
        if ($proc.HasExited -and $batch.Count -eq 0) { break }
        Start-Sleep -Milliseconds 80
    }
    return $null
}

# 构造工具参数对象
function Build-Arguments {
    if ($JsonB64) {
        $raw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($JsonB64))
        return ($raw | ConvertFrom-Json)
    }
    if ($Params) {
        $h = @{}
        foreach ($pair in ($Params -split ';')) {
            if (-not $pair.Trim()) { continue }
            $kv = $pair -split '=', 2
            $k = $kv[0].Trim()
            $v = if ($kv.Count -gt 1) { $kv[1].Trim() } else { '' }
            if ($v -match '^-?\d+$') { $h[$k] = [int]$v }
            elseif ($v -eq 'true') { $h[$k] = $true }
            elseif ($v -eq 'false') { $h[$k] = $false }
            else { $h[$k] = $v }
        }
        return $h
    }
    if ($Json) { return ($Json | ConvertFrom-Json) }
    return @{}
}

$exitCode = 0
try {
    Send-Json @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{
        protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'dsh-exd'; version = '1.0' } } }
    $init = Wait-Response 1 20000
    if (-not $init) {
        $err = $null
        $errs = @()
        while ($errQueue.TryDequeue([ref]$err)) { $errs += $err }
        Write-Error ("MCP 初始化失败。" + ($errs -join ' '))
        exit 1
    }
    Send-Json @{ jsonrpc = '2.0'; method = 'notifications/initialized' }

    if ($ListTools) {
        Send-Json @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} }
        $resp = Wait-Response 2 20000
        $obj = $resp | ConvertFrom-Json
        $obj.result.tools | ForEach-Object {
            $head = ($_.description -split "`n")[0]
            "{0,-26} {1}" -f $_.name, $head
        }
    }
    elseif ($Tool) {
        $argObj = Build-Arguments
        Send-Json @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = $Tool; arguments = $argObj } }
        $resp = Wait-Response 2 $TimeoutMs
        if (-not $resp) { Write-Error "工具 $Tool 调用超时"; exit 1 }
        $obj = $resp | ConvertFrom-Json
        if ($obj.error) {
            Write-Error ("MCP 错误: " + ($obj.error | ConvertTo-Json -Depth 10))
            exit 1
        }
        if ($obj.result.isError) { $exitCode = 2 }
        foreach ($item in $obj.result.content) {
            if ($item.type -eq 'text') {
                $text = $item.text
                try {
                    $parsed = $text | ConvertFrom-Json -ErrorAction Stop
                    if ($Brief -and $parsed.rows) {
                        $cols = @($parsed.columns)
                        $disp = @()
                        for ($i = 0; $i -lt $cols.Count; $i++) { if ($cols[$i].is_display) { $disp += $i } }
                        $rowsOut = @()
                        foreach ($r in @($parsed.rows)) {
                            $m = [ordered]@{ row_id = $r.row_id }
                            foreach ($i in $disp) { $m[$cols[$i].name] = @($r.values)[$i] }
                            $rowsOut += $m
                        }
                        [ordered]@{
                            sheet = $parsed.sheet
                            total_rows = $parsed.total_rows
                            matched_rows = $parsed.matched_rows
                            rows = $rowsOut
                        } | ConvertTo-Json -Depth 6
                    }
                    elseif ($Brief -and $parsed.columns -and $parsed.values) {
                        $map = [ordered]@{ sheet = $parsed.sheet; row_id = $parsed.row_id }
                        $cols = @($parsed.columns)
                        $vals = @($parsed.values)
                        for ($i = 0; $i -lt [Math]::Min($cols.Count, $vals.Count); $i++) {
                            $map[$cols[$i].name] = $vals[$i]
                        }
                        $map | ConvertTo-Json -Depth 5
                    }
                    else {
                        $parsed | ConvertTo-Json -Depth 20
                    }
                }
                catch {
                    $text
                }
            }
            else {
                "[{0}] {1}" -f $item.type, (($item | ConvertTo-Json -Depth 5 -Compress))
            }
        }
    }
    else {
        Write-Error "需要 -ListTools 或 -Tool <名称>（参数用 -JsonB64 或 -Params 传）"
        $exitCode = 1
    }
}
finally {
    try { $proc.StandardInput.Close() } catch { }
    Start-Sleep -Milliseconds 200
    if (-not $proc.HasExited) { try { $proc.Kill() } catch { } }
    Get-EventSubscriber | Unregister-Event -ErrorAction SilentlyContinue
}

exit $exitCode
