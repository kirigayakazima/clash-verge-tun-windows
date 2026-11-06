# Register Windows Scheduled Task for silent boot & logon self-healing.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '注册计划任务需要管理员权限，请在管理员 PowerShell 中运行。'
}

$taskName = 'ClashVergeTunAutoRepair'
$targetScript = Join-Path $PSScriptRoot 'Invoke-AutoRepair.ps1'

if (-not (Test-Path -LiteralPath $targetScript)) {
    throw "未找到自愈脚本: $targetScript"
}

# Construct action
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetScript`" -Silent"

# Triggers: 1) System boot, 2) User logon (delay 5s for desktop/service readiness)
$triggerBoot = New-ScheduledTaskTrigger -AtStartup
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn
$triggerLogon.Delay = 'PT5S'

# Principal: Highest privilege SYSTEM account (silent, no UAC prompts)
$taskPrincipal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest

# Settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Unregister existing task if already present
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Register new scheduled task
Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger @($triggerBoot, $triggerLogon) `
    -Principal $taskPrincipal `
    -Settings $settings `
    -Force `
    -Description 'Clash Verge TUN 模式开机自愈任务：自动检测物理出口、静默关闭转发防回环死锁、确保有线网络与TUN正常。' | Out-Null

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host "✅ 开机自愈任务 [$taskName] 注册成功！" -ForegroundColor Green
Write-Host "  - 触发机制 1: 系统开机启动时 (AtStartup，最早执行)"
Write-Host "  - 触发机制 2: 用户登录桌面时 (AtLogon，延迟 5 秒二次兜底)"
Write-Host "  - 运行权限: SYSTEM 最高权限 (后台纯静默，无黑框)"
Write-Host "==================================================" -ForegroundColor Green
Write-Host "`n按 Enter 键关闭窗口..."
$null = Read-Host
