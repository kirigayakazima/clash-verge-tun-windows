# Windows PowerShell 5.1 / PowerShell 7 interactive entry point.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Disable', 'Restore')][string]$Action,
    [string]$InterfaceAlias
)

$ErrorActionPreference = 'Stop'
$script:BackupPath = Join-Path $PSScriptRoot 'state\forwarding-backup.json'

function Get-UplinkChoices {
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
        }
    })
    $choices | Sort-Object Score, Name
}

function Select-Uplink {
    $choices = @(Get-UplinkChoices)
    if (-not $choices.Count) { throw '没有找到物理网卡，请先检查网卡驱动和连接。' }
    $default = 0
    if ($choices[0].Score -lt [int]::MaxValue) { $default = 1 }
    Write-Host ''
    for ($i = 0; $i -lt $choices.Count; $i++) {
        $item = $choices[$i]
        $hint = if ($i + 1 -eq $default) { ' [推荐：活动物理网卡中默认路由总度量值最低]' } else { '' }
        Write-Host ("{0}. {1} | {2} | IPv4 转发：{3}{4}" -f ($i + 1), $item.Name, $item.Status, $item.Forwarding, $hint)
    }
    Write-Host '0. 取消'
    while ($true) {
        $prompt = if ($default) { "选择真实出口网卡（回车选 $default）" } else { '没有可推荐的默认出口，请输入网卡编号' }
        $answer = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($answer) -and $default) { $answer = [string]$default }
        if ($answer -eq '0') { return }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $choices.Count) {
            if ($choices[$number - 1].Status -ne 'Up') { Write-Host '该网卡未连接，请选择正在使用的网卡。'; continue }
            return $choices[$number - 1].Name
        }
        Write-Host '请输入列表中的数字。'
    }
}

function Show-UplinkConfig([string]$Name) {
    # JSON strings are also valid YAML scalars, including non-ASCII names.
    $quotedName = ConvertTo-Json -InputObject $Name -Compress
    Write-Host "`n对应的 Clash 配置："
    Write-Host '设置 → 虚拟网卡模式齿轮 → 关闭“自动选择流量出口接口”。'
    Write-Host '订阅 → 右键当前订阅 → 扩展覆写配置：添加或更新以下字段，保留其他内容。'
    Write-Host "interface-name: $quotedName" -ForegroundColor Cyan
    Write-Host '保存后自行开启 TUN，再从本菜单选择连通性测试。'
}

function Invoke-Repair([string]$Name) {
    if (-not $Name) { $Name = Select-Uplink }
    if (-not $Name) { return }
    Write-Host "`n目标：$Name；临时关闭 IPv4 转发并保留原值备份。"
    $forwardArgs = @{ Action = 'Disable'; InterfaceAlias = $Name }
    if ($WhatIfPreference) { $forwardArgs.WhatIf = $true }
    & (Join-Path $PSScriptRoot 'scripts\Set-Forwarding.ps1') @forwardArgs
    Show-UplinkConfig $Name
}

function Invoke-Restore {
    if (-not (Test-Path -LiteralPath $script:BackupPath)) { Write-Host '没有转发备份，无需恢复。'; return }
    $backup = Get-Content -LiteralPath $script:BackupPath -Raw | ConvertFrom-Json
    Write-Host "备份网卡：$($backup.InterfaceAlias)；恢复值：$($backup.OriginalValue)"
    if ((Read-Host '先关闭 TUN。输入 1 恢复，其他输入取消') -ne '1') { return }
    $forwardArgs = @{ Action = 'Restore'; InterfaceAlias = [string]$backup.InterfaceAlias }
    if ($InterfaceAlias) { $forwardArgs.InterfaceAlias = $InterfaceAlias }
    if ($WhatIfPreference) { $forwardArgs.WhatIf = $true }
    & (Join-Path $PSScriptRoot 'scripts\Set-Forwarding.ps1') @forwardArgs
}

Write-Host "`nClash Verge TUN 排查与修复" -ForegroundColor Cyan
Write-Host '修复和恢复需要管理员权限；可双击项目根目录的 启动修复.cmd。'
Write-Host '脚本临时修改所选物理网卡的 IPv4 转发；Clash 设置按提示确认。'
if ($Action) {
    if ($Action -eq 'Disable') { Invoke-Repair $InterfaceAlias } else { Invoke-Restore }
    return
}

try {
    $detected = @(Get-UplinkChoices)
    if ($detected.Count -and $detected[0].Score -lt [int]::MaxValue) {
        Write-Host ("自动查询：推荐出口 {0}；IPv4 转发 {1}。" -f $detected[0].Name, $detected[0].Forwarding) -ForegroundColor Cyan
    } else {
        Write-Host '自动查询：没有可推荐的物理默认出口，操作时请手动选择。'
    }
    if (Test-Path -LiteralPath $script:BackupPath) {
        $saved = Get-Content -LiteralPath $script:BackupPath -Raw | ConvertFrom-Json
        Write-Host ("已有备份：{0}；原值 {1}。可再次修复同一网卡，或选择 3 恢复。" -f $saved.InterfaceAlias, $saved.OriginalValue)
    }
} catch {
    Write-Host ("自动查询未完成：{0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

while ($true) {
    Write-Host "`n1. 修复 / 再次修复转发（自动查询并推荐网卡）"
    Write-Host '2. 查看网卡、路由与 Clash 状态（只读）'
    Write-Host '3. 从备份恢复转发'
    Write-Host '4. 测试国内外连通性'
    Write-Host '5. 选择网卡并查看对应 Clash 配置（只读）'
    Write-Host '0. 退出'
    $choice = Read-Host '输入编号'
    try {
        switch ($choice) {
            '1' { Invoke-Repair $InterfaceAlias }
            '2' { & (Join-Path $PSScriptRoot 'scripts\Get-TunStatus.ps1') }
            '3' { Invoke-Restore }
            '4' { & (Join-Path $PSScriptRoot 'scripts\Test-Connectivity.ps1') }
            '5' { $name = Select-Uplink; if ($name) { Show-UplinkConfig $name } }
            '0' { return }
            default { Write-Host '请输入 0 到 5。' }
        }
    } catch {
        Write-Host ("操作未完成：{0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host '若提示权限不足，请使用“启动修复.cmd”；网络异常时先关闭 TUN 切回系统代理。'
    }
}
