# Dependency-free behavioral tests. Network commands are mocked; state is temporary.
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('tun-menu-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $sandbox 'scripts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'Start-TunRepair.ps1') -Destination $sandbox
Copy-Item -LiteralPath (Join-Path $project 'scripts\Set-Forwarding.ps1') -Destination (Join-Path $sandbox 'scripts')
$global:TunTest_answers = New-Object 'System.Collections.Generic.Queue[string]'
$global:TunTest_writes = 0
$global:TunTest_forwarding = 'Enabled'
$global:TunTest_noRoute = $false
$global:TunTest_adapterName = 'Ethernet'
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
function Read-Host { param($Prompt); if (-not $global:TunTest_answers.Count) { throw "Unexpected prompt: $Prompt" }; $global:TunTest_answers.Dequeue() }
function New-Object {
    param($TypeName, $ArgumentList)
    if ($TypeName -eq 'Security.Principal.WindowsPrincipal') {
        $fake = [pscustomobject]@{}
        $fake | Add-Member -MemberType ScriptMethod -Name IsInRole -Value { param($role); $true }
        return $fake
    }
    Microsoft.PowerShell.Utility\New-Object -TypeName $TypeName -ArgumentList $ArgumentList
}
function Get-NetAdapter {
    [CmdletBinding()]param($Name)
    $adapters = @(
        [pscustomobject]@{ Name=$global:TunTest_adapterName; ifIndex=10; Status='Up'; HardwareInterface=$true; Virtual=$false; InterfaceGuid='ethernet-guid'; InterfaceDescription='Physical Ethernet' },
        [pscustomobject]@{ Name='Wi-Fi'; ifIndex=20; Status='Up'; HardwareInterface=$true; Virtual=$false; InterfaceGuid='wifi-guid'; InterfaceDescription='Physical WLAN' },
        [pscustomobject]@{ Name='vgate0'; ifIndex=30; Status='Up'; HardwareInterface=$false; Virtual=$true; InterfaceGuid='virtual-guid'; InterfaceDescription='Rust Wintun' }
    )
    if ($Name) { return $adapters | Where-Object Name -eq $Name }
    $adapters
}
function Get-NetIPInterface {
    [CmdletBinding()]param($InterfaceAlias, $AddressFamily, $PolicyStore)
    $items = @(
        [pscustomobject]@{ InterfaceAlias=$global:TunTest_adapterName; InterfaceIndex=10; InterfaceMetric=10; Forwarding=$global:TunTest_forwarding },
        [pscustomobject]@{ InterfaceAlias='Wi-Fi'; InterfaceIndex=20; InterfaceMetric=50; Forwarding='Enabled' }
    )
    if ($InterfaceAlias) { return $items | Where-Object InterfaceAlias -eq $InterfaceAlias }
    $items
}
function Get-NetRoute {
    param($AddressFamily)
    if ($global:TunTest_noRoute) { return }
    foreach ($idx in @(10,20,30)) { [pscustomobject]@{ InterfaceIndex=$idx; DestinationPrefix='0.0.0.0/0'; RouteMetric=0 } }
}
function Set-NetIPInterface {
    [CmdletBinding()]param($InterfaceAlias, $AddressFamily, $Forwarding, $PolicyStore)
    Assert ($InterfaceAlias -eq $global:TunTest_adapterName) 'Only the selected physical adapter may change'
    Assert ($PolicyStore -eq 'ActiveStore') 'Only ActiveStore may change'
    $global:TunTest_writes++
    $global:TunTest_forwarding = [string]$Forwarding
}
function Queue-Answers([string[]]$Values) { foreach ($v in $Values) { $global:TunTest_answers.Enqueue($v) } }
try {
    $entry = Join-Path $sandbox 'Start-TunRepair.ps1'
    $legacy = Join-Path $sandbox 'scripts\Set-Forwarding.ps1'
    $backupFile = Join-Path $sandbox 'state\forwarding-backup.json'
    Queue-Answers @('bad', '')
    & $legacy -Action Disable
    Assert ($global:TunTest_forwarding -eq 'Disabled' -and $global:TunTest_writes -eq 1) 'Default route selects Ethernet'
    $originalBackup = Get-Content -LiteralPath $backupFile -Raw
    $global:TunTest_forwarding = 'Enabled'
    Queue-Answers @('')
    & $entry -Action Disable
    Assert ($global:TunTest_forwarding -eq 'Disabled' -and $global:TunTest_writes -eq 2) 'Repeated repair works'
    Assert ((Get-Content -LiteralPath $backupFile -Raw) -eq $originalBackup) 'Original backup is preserved'
    & $legacy -Action Disable -InterfaceAlias Ethernet
    Assert ($global:TunTest_writes -eq 2) 'Already disabled is a no-op'
    $rejected = $false
    try { & $legacy -Action Disable -InterfaceAlias 'Wi-Fi' } catch { $rejected = $true }
    Assert $rejected 'Different adapter backup conflict is rejected'
    $rejected = $false
    try { & $legacy -Action Disable -InterfaceAlias 'vgate0' } catch { $rejected = $true }
    Assert $rejected 'Virtual adapter is rejected'
    Queue-Answers @('1')
    & $entry -Action Restore
    Assert ($global:TunTest_forwarding -eq 'Enabled' -and -not (Test-Path -LiteralPath $backupFile)) 'Restore recovers original value'
    $global:TunTest_noRoute = $true
    Queue-Answers @('', '0')
    & $entry -Action Disable
    Assert ($global:TunTest_writes -eq 3) 'No route and cancel do not mutate anything'
    $global:TunTest_noRoute = $false
    Queue-Answers @('')
    & $entry -Action Disable -WhatIf
    Assert ($global:TunTest_writes -eq 3 -and -not (Test-Path -LiteralPath $backupFile)) 'WhatIf makes no changes'
    $global:TunTest_adapterName = '以太网'
    Queue-Answers @('5', '', '0')
    & $legacy
    Assert ($global:TunTest_answers.Count -eq 0 -and $global:TunTest_writes -eq 3) 'Unicode config menu and legacy entry work'
    Write-Output 'PASS: selection, repeat repair, rollback, conflicts, virtual guard, cancellation, WhatIf and compatibility.'
} finally {
    $resolved = [IO.Path]::GetFullPath($sandbox)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'tun-menu-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
