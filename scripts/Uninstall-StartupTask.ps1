# Unregister Windows Scheduled Task for Clash Verge TUN Auto Repair.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '卸载计划任务需要管理员权限，请在管理员 PowerShell 中运行。'
}

$taskName = 'ClashVergeTunAutoRepair'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "`n✅ 已成功注销开机自愈计划任务 [$taskName]。" -ForegroundColor Green
} else {
    Write-Host "`n未发现计划任务 [$taskName]，无需卸载。" -ForegroundColor Yellow
}
Write-Host "`n按 Enter 键关闭窗口..."
$null = Read-Host
