# Temporarily change IPv4 forwarding on one physical adapter, with rollback.
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Disable', 'Restore')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$InterfaceAlias
)

$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run PowerShell as Administrator.'
}

$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
if (@($adapter).Count -ne 1 -or $adapter.Name -cne $InterfaceAlias) {
    throw 'InterfaceAlias must be the exact name of one adapter; wildcards are not accepted.'
}
if ($adapter.InterfaceDescription -match '(?i)wintun|tap|tunnel|virtual|hyper-v|vmware') {
    throw "'$InterfaceAlias' appears to be a virtual adapter. Choose the actual physical uplink."
}

$stateDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'state'
$backupPath = Join-Path $stateDir 'forwarding-backup.json'
$current = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop

if ($Action -eq 'Disable') {
    if (Test-Path -LiteralPath $backupPath) {
        throw "A previous backup exists at '$backupPath'. Restore it before starting another test."
    }
    if ($current.Forwarding -eq 'Disabled') {
        Write-Output "IPv4 forwarding on '$InterfaceAlias' is already Disabled; no backup was created."
        return
    }
    if (-not $PSCmdlet.ShouldProcess($InterfaceAlias, 'Back up and disable active IPv4 forwarding')) { return }

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    [pscustomobject]@{
        InterfaceAlias = $InterfaceAlias
        InterfaceGuid  = [string]$adapter.InterfaceGuid
        OriginalValue  = [string]$current.Forwarding
        SavedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $backupPath -Encoding UTF8

    Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Forwarding Disabled -PolicyStore ActiveStore -ErrorAction Stop
    $after = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop
    if ($after.Forwarding -ne 'Disabled') { throw 'Forwarding did not remain Disabled. Another application may have changed it.' }
    Write-Output "IPv4 forwarding on '$InterfaceAlias' is Disabled. Backup: $backupPath"
    return
}

if (-not (Test-Path -LiteralPath $backupPath)) { throw "No backup found at '$backupPath'." }
$backup = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json
if ($backup.InterfaceAlias -ne $InterfaceAlias -or $backup.InterfaceGuid -ne [string]$adapter.InterfaceGuid) {
    throw 'Backup does not match this adapter. No change was made.'
}
if ($backup.OriginalValue -notin @('Enabled', 'Disabled')) { throw 'Backup contains an invalid forwarding value.' }
if (-not $PSCmdlet.ShouldProcess($InterfaceAlias, "Restore active IPv4 forwarding to $($backup.OriginalValue)")) { return }

Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Forwarding $backup.OriginalValue -PolicyStore ActiveStore -ErrorAction Stop
$after = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop
if ([string]$after.Forwarding -ne $backup.OriginalValue) { throw 'Restore verification failed; backup was kept.' }
Remove-Item -LiteralPath $backupPath -Force
Write-Output "IPv4 forwarding on '$InterfaceAlias' restored to $($backup.OriginalValue)."
