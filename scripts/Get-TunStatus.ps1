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
$generatedPath = Join-Path $configDir 'clash-verge.yaml'
$usesDomesticGroup = $true
if (Test-Path -LiteralPath $generatedPath) {
    $references = @(Select-String -LiteralPath $generatedPath -Encoding UTF8 -Pattern '^\s*-\s*.+,\s*🇨🇳 国内网站\s*(,\s*no-resolve\s*)?$')
    $usesDomesticGroup = $references.Count -gt 0
    Write-Output "=== Generated rules: domestic group references = $($references.Count) ==="
    if (-not $usesDomesticGroup) {
        Write-Output 'No generated top-level rules target this group; its saved selection alone does not determine routing. Check DIRECT rules and connection records.'
    }
}
if ($usesDomesticGroup -and (Test-Path -LiteralPath $profilesPath)) {
    Write-Output "=== profiles.yaml: domestic group check ==="
    $lines = Get-Content -LiteralPath $profilesPath -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'name:\s*.*国内网站') {
            $nameLine = $lines[$i].Trim()
            $nowLine = if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Trim() } else { '' }
            Write-Output "  $nameLine | $nowLine"
            if ($nowLine -notmatch 'now:\s*DIRECT\b') {
                Write-Warning "此订阅记录中的 '国内网站' 未选 DIRECT；请结合当前订阅、生成规则和连接记录确认实际出口，国内视频 CDN 可能受影响。"
            }
        }
    }
}
