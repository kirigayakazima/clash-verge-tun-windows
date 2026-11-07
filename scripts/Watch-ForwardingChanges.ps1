# Windows PowerShell 5.1 / PowerShell 7 Forwarding Intrusion Detection & Monitor.
[CmdletBinding()]
param(
    [string]$InterfaceAlias = '以太网',
    [int]$IntervalMs = 500,
    [bool]$AutoSuppress = $true
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot 'state\incidents'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "🔍 物理网卡转发篡改实时侦听雷达 (Intrusion Detection Radar)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  - 监控网卡: $InterfaceAlias"
Write-Host "  - 探测频率: 每 ${IntervalMs} 毫秒"
Write-Host "  - 管理员权限: $(if ($isAdmin) { '已具备 (支持自动压制与全量进程透视)' } else { '普通权限 (建议以管理员运行以捕获完整进程信息)' })"
Write-Host "  - 自动压制: $(if ($AutoSuppress) { '开启 (抓拍到证据后立即压制为 Disabled)' } else { '关闭 (仅抓拍不修改)' })"
Write-Host "==================================================================`n" -ForegroundColor Cyan

# Check initial status
$current = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue
if (-not $current) {
    # If "以太网" not found, find physical adapter automatically
    $choice = Get-NetAdapter | Where-Object { $_.HardwareInterface -and -not $_.Virtual -and $_.Status -eq 'Up' } | Select-Object -First 1
    if ($choice) {
        $InterfaceAlias = $choice.Name
        $current = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue
        Write-Host "⚠️ 未找到默认“以太网”，已自动匹配主物理网卡: $InterfaceAlias" -ForegroundColor Yellow
    } else {
        throw "未找到网卡: $InterfaceAlias"
    }
}

if ($current.Forwarding -eq 'Enabled') {
    Write-Host "⚠️ [初始状态异常] 当前 $InterfaceAlias 的 IPv4 转发已经是 Enabled！" -ForegroundColor Yellow
    if ($isAdmin -and $AutoSuppress) {
        Write-Host "🔧 正在将其重置为 Disabled 以开启侦听..." -ForegroundColor Yellow
        Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Forwarding Disabled -PolicyStore ActiveStore -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
}

Write-Host "🚀 实时监控已启动！按 Ctrl+C 可随时停止监控并退出。`n" -ForegroundColor Green

$lastState = (Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).Forwarding
$loopCount = 0

while ($true) {
    Start-Sleep -Milliseconds $IntervalMs
    $loopCount++

    $now = Get-Date
    $cur = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $cur) { continue }
    $currentState = $cur.Forwarding

    # Print heartbeat every 5 seconds (10 loops at 500ms)
    if ($loopCount % 10 -eq 0) {
        $statusColor = if ($currentState -eq 'Disabled') { 'DarkGray' } else { 'Red' }
        Write-Host ("[{0}] 正在侦听 {1}... 当前转发状态: [{2}]" -f $now.ToString('HH:mm:ss'), $InterfaceAlias, $currentState) -ForegroundColor $statusColor
    }

    # TRIGGER: When state flips from Disabled to Enabled
    if ($lastState -eq 'Disabled' -and $currentState -eq 'Enabled') {
        try { [Console]::Beep(1200, 300) } catch {}
        $timestampStr = $now.ToString('yyyy-MM-dd HH:mm:ss.fff')
        $incidentTime = $now

        Write-Host "`n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
        Write-Host "🚨 警报！捕获到网卡 IPv4 转发被篡改现场！" -ForegroundColor Red
        Write-Host "  - 捕获时刻: $timestampStr" -ForegroundColor Yellow
        Write-Host "  - 目标网卡: $InterfaceAlias" -ForegroundColor Yellow
        Write-Host "  - 状态变化: Disabled  ===>  Enabled (已反弹)" -ForegroundColor Red
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`n" -ForegroundColor Red

        # 1. Inspect suspected processes
        Write-Host "--- 1. 嫌疑进程与后台服务状态快照 ---" -ForegroundColor Cyan
        $suspectServices = @('O+Connect Service', 'OplusRemoteService', 'SharedAccess', 'dist_service', 'DistributedService', 'MAFSvr')
        $svcStatus = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $suspectServices })
        foreach ($s in $svcStatus) {
            $stateColor = if ($s.State -eq 'Running') { 'Yellow' } else { 'DarkGray' }
            Write-Host ("  [服务] {0,-20} 状态: {1,-8} PID: {2,-6} 路径: {3}" -f $s.Name, $s.State, $s.ProcessId, $s.PathName) -ForegroundColor $stateColor
        }

        # 2. Inspect active network adapters (especially vgate0, utun8, Wi-Fi Direct)
        Write-Host "`n--- 2. 虚拟网卡与网络通道关联快照 ---" -ForegroundColor Cyan
        $relatedAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'vgate|utun|wintun|Wi-Fi Direct|Mihomo' -or $_.InterfaceDescription -match 'Wintun|Wi-Fi Direct' })
        foreach ($a in $relatedAdapters) {
            $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            Write-Host ("  [网卡] {0,-25} 状态: {1,-10} IP: {2,-16} 描述: {3}" -f $a.Name, $a.Status, ($ip -join ','), $a.InterfaceDescription) -ForegroundColor Cyan
        }

        # 3. Query recent NetworkProfile event logs (within last 30 seconds)
        Write-Host "`n--- 3. 系统网络事件日志关联证据 ---" -ForegroundColor Cyan
        $recentEvents = @(Get-WinEvent -LogName 'Microsoft-Windows-NetworkProfile/Operational' -MaxEvents 10 -ErrorAction SilentlyContinue |
            Where-Object { $_.TimeCreated -ge $incidentTime.AddSeconds(-30) })
        if ($recentEvents.Count) {
            foreach ($e in $recentEvents) {
                $msgFirstLine = ($e.Message -split "`r?`n")[0]
                Write-Host ("  [事件 {0}] {1} (ID: {2}): {3}" -f $e.TimeCreated.ToString('HH:mm:ss.fff'), $e.ProviderName, $e.Id, $msgFirstLine) -ForegroundColor Magenta
            }
        } else {
            Write-Host "  (最近 30 秒内未记录 NetworkProfile 突发事件)" -ForegroundColor DarkGray
        }

        # 4. Generate forensic incident report file
        $reportFile = Join-Path $logDir ("incident-{0}.log" -f $now.ToString('yyyyMMdd-HHmmss'))
        $reportLines = @(
            "==================================================================",
            "Clash Verge TUN 转发篡改现场证据报告",
            "==================================================================",
            "记录时刻: $timestampStr",
            "受影响网卡: $InterfaceAlias",
            "状态变更: Disabled -> Enabled",
            "",
            "[嫌疑服务与常驻进程]",
            ($svcStatus | ForEach-Object { "{0} | {1} | PID: {2} | {3}" -f $_.Name, $_.State, $_.ProcessId, $_.PathName }),
            "",
            "[关联虚拟网卡状态]",
            ($relatedAdapters | ForEach-Object { "{0} | {1} | {2}" -f $_.Name, $_.Status, $_.InterfaceDescription }),
            "",
            "[关联系统事件日志]",
            ($recentEvents | ForEach-Object { "[{0}] ID:{1} {2}" -f $_.TimeCreated.ToString('o'), $_.Id, ($_.Message -replace "`r?`n", " ") })
        )
        $reportLines | Out-File -LiteralPath $reportFile -Encoding UTF8
        Write-Host "`n📄 完整现场报告已写入: $reportFile" -ForegroundColor Green

        # 5. Auto suppression if enabled
        if ($isAdmin -and $AutoSuppress) {
            Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Forwarding Disabled -PolicyStore ActiveStore -ErrorAction SilentlyContinue
            Write-Host "🛡️ [自愈机制] 已即时将 $InterfaceAlias 的 IPv4 转发重新锁死为 Disabled！`n" -ForegroundColor Green
            $currentState = 'Disabled'
        } else {
            Write-Host "ℹ️ 提示: 未开启自动压制或无管理员权限，网卡保持 Enabled。`n" -ForegroundColor Yellow
        }
    }

    $lastState = $currentState
}
