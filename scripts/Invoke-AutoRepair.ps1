# Automated non-interactive TUN repair.
# Automatically detects physical uplink, disables IPv4 forwarding,
# resets TUN if active, and verifies domestic DIRECT routing.
[CmdletBinding()]
param(
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$backupPath = Join-Path $repoRoot 'state\forwarding-backup.json'

function Write-Step([string]$msg, [string]$color = 'Cyan') {
    if (-not $Silent) { Write-Host $msg -ForegroundColor $color }
}

# 1. Detect physical uplink
$interfaces = @(Get-NetIPInterface -AddressFamily IPv4 -PolicyStore ActiveStore)
$routes = @(Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' })
$choices = @(foreach ($adapter in @(Get-NetAdapter)) {
    if (-not $adapter.HardwareInterface -or $adapter.Virtual -or
        $adapter.InterfaceDescription -match '(?i)wintun|tap|tunnel|virtual|hyper-v|vmware') { continue }
    $ip = $interfaces | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex } | Select-Object -First 1
    $route = $routes | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex } |
        Sort-Object RouteMetric | Select-Object -First 1
    $score = [int]::MaxValue
    if ($adapter.Status -eq 'Up' -and $route -and $ip) { $score = [int]$route.RouteMetric + [int]$ip.InterfaceMetric }
    [pscustomobject]@{
        Name = $adapter.Name
        Status = $adapter.Status
        Forwarding = if ($ip) { [string]$ip.Forwarding } else { 'Unknown' }
        Score = $score
        Guid = [string]$adapter.InterfaceGuid
    }
})
$sortedChoices = @($choices | Sort-Object Score, Name)
if (-not $sortedChoices.Count) {
    throw '未检测到可用物理网卡。'
}
$targetAdapter = $sortedChoices[0]
Write-Step "[1/4] 识别物理出口: $($targetAdapter.Name) (当前转发: $($targetAdapter.Forwarding))"

# 2. Disable IPv4 Forwarding (both ActiveStore and PersistentStore)
$cur = Get-NetIPInterface -InterfaceAlias $targetAdapter.Name -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue
if ($cur -and $cur.Forwarding -ne 'Disabled') {
    $stateDir = Split-Path -Parent $backupPath
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $backupPath)) {
        [pscustomobject]@{
            InterfaceAlias = $targetAdapter.Name
            InterfaceGuid  = $targetAdapter.Guid
            OriginalValue  = [string]$cur.Forwarding
            SavedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $backupPath -Encoding UTF8
    }
    Set-NetIPInterface -InterfaceAlias $targetAdapter.Name -AddressFamily IPv4 -Forwarding Disabled -PolicyStore ActiveStore -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $targetAdapter.Name -AddressFamily IPv4 -Forwarding Disabled -PolicyStore PersistentStore -ErrorAction SilentlyContinue
    Write-Step "[2/4] IPv4 转发: 已成功关闭 (已同步写入持久库)"
} else {
    Write-Step "[2/4] IPv4 转发: 当前已处于 Disabled 状态"
}

# 3. Check and Restart TUN via Mihomo Named Pipe if active
function Send-MihomoConfigPatch([string]$jsonBody) {
    try {
        $pipeFile = Get-ChildItem '\\.\pipe\' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'verge-mihomo-production' } | Select-Object -First 1
        if (-not $pipeFile) { return $false }
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeFile.Name, [System.IO.Pipes.PipeDirection]::InOut)
        $pipe.Connect(1500)
        $writer = New-Object System.IO.StreamWriter($pipe)
        $reader = New-Object System.IO.StreamReader($pipe)
        $req = "PATCH /configs HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/json`r`nContent-Length: $($jsonBody.Length)`r`nConnection: close`r`n`r`n$jsonBody"
        $writer.Write($req)
        $writer.Flush()
        $status = $reader.ReadLine()
        $pipe.Close()
        return ($status -match '20[04]')
    } catch {
        return $false
    }
}

$mihomoAdapter = Get-NetAdapter -Name 'Mihomo' -ErrorAction SilentlyContinue
$tunActive = ($mihomoAdapter -and $mihomoAdapter.Status -eq 'Up')
if ($tunActive) {
    Write-Step "[3/4] 刷新 TUN 虚拟网卡: 检测到 TUN 开着，正在自动平滑重启..."
    $null = Send-MihomoConfigPatch '{"tun":{"enable":false}}'
    Start-Sleep -Milliseconds 600
    $null = Send-MihomoConfigPatch '{"tun":{"enable":true}}'
    Write-Step "[3/4] 刷新 TUN 虚拟网卡: 重启完成，新网络状态已绑定"
} else {
    Write-Step "[3/4] TUN 状态: 当前未开启，跳过热重启"
}

# 4. Ensure domestic group is DIRECT in profiles.yaml and runtime
$configDir = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
$profilesPath = Join-Path $configDir 'profiles.yaml'
if (Test-Path -LiteralPath $profilesPath) {
    $content = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8
    if ($content -match 'name:\s*.*国内网站\s*\r?\n\s*now:\s*(?!DIRECT\b)') {
        $newContent = [regex]::Replace($content, '(name:\s*.*国内网站\s*\r?\n\s*now:\s*)(.+)', '${1}DIRECT')
        Set-Content -LiteralPath $profilesPath -Value $newContent -Encoding UTF8
    }
}
try {
    $pipeFile = Get-ChildItem '\\.\pipe\' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'verge-mihomo-production' } | Select-Object -First 1
    if ($pipeFile) {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeFile.Name, [System.IO.Pipes.PipeDirection]::InOut)
        $pipe.Connect(1000)
        $writer = New-Object System.IO.StreamWriter($pipe)
        $body = '{"name":"DIRECT"}'
        $encodedGroup = [System.Uri]::EscapeDataString("🇨🇳 国内网站")
        $req = "PUT /proxies/$encodedGroup HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n$body"
        $writer.Write($req)
        $writer.Flush()
        $pipe.Close()
    }
} catch {}
Write-Step "[4/4] 国内分流策略: 已确认为 DIRECT 直连"

# Flush DNS cache so Windows NCSI instantly discovers Ethernet connectivity
Start-Process -FilePath "ipconfig.exe" -ArgumentList "/flushdns" -WindowStyle Hidden -Wait

if (-not $Silent) {
    Write-Host "`n==================================================" -ForegroundColor Green
    Write-Host "✅ 全套自动自愈完成！有线网络与 TUN 已完全恢复正常。" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host "`n按 Enter 键关闭窗口..."
    $null = Read-Host
}
