# Read-only Windows/Clash TUN diagnostics. Does not display subscription data.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Output '=== Active IPv4 interfaces ==='
Get-NetIPInterface -AddressFamily IPv4 -PolicyStore ActiveStore |
    Where-Object { $_.ConnectionState -eq 'Connected' -and $_.InterfaceAlias -notmatch '^Loopback ' } |
    Select-Object InterfaceAlias, InterfaceIndex, Forwarding, InterfaceMetric, ConnectionState |
    Format-Table -AutoSize

Write-Output '=== IPv4 default and split-default routes ==='
Get-NetRoute -AddressFamily IPv4 |
    Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1') } |
    Select-Object DestinationPrefix, InterfaceAlias, NextHop, RouteMetric |
    Format-Table -AutoSize

Write-Output '=== Relevant adapters ==='
Get-NetAdapter |
    Where-Object { $_.Status -eq 'Up' -or $_.Name -match 'Mihomo|vgate' } |
    Select-Object Name, Status, InterfaceDescription, LinkSpeed |
    Format-Table -AutoSize

Write-Output '=== O+ Connect service ==='
Get-Service -Name 'O+Connect Service' -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType |
    Format-Table -AutoSize

$configDir = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
foreach ($name in @('verge.yaml', 'clash-verge.yaml')) {
    $path = Join-Path $configDir $name
    if (-not (Test-Path -LiteralPath $path)) { continue }
    Write-Output "=== ${name}: selected safe fields ==="
    Select-String -LiteralPath $path -Pattern '^enable_tun_mode:', '^enable_system_proxy:', '^interface-name:', '^  auto-detect-interface:', '^  auto-route:', '^  stack:', '^  enable:' |
        ForEach-Object { $_.Line }
}

$profilesPath = Join-Path $configDir 'profiles.yaml'
if (Test-Path -LiteralPath $profilesPath) {
    Write-Output "=== profiles.yaml: domestic group check ==="
    $lines = Get-Content -LiteralPath $profilesPath -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'name:\s*.*国内网站') {
            $nameLine = $lines[$i].Trim()
            $nowLine = if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Trim() } else { '' }
            Write-Output "  $nameLine | $nowLine"
            if ($nowLine -notmatch 'now:\s*DIRECT\b') {
                Write-Warning "【警告】'国内网站' 策略组当前未选中 DIRECT！这会导致国内视频流（如 B站 bilivideo）走代理而无法播放/黑屏。"
            }
        }
    }
}
