@echo off
setlocal
set "TUN_REPAIR_ENTRY=%~dp0Start-TunRepair.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ""' + $env:TUN_REPAIR_ENTRY + '""') -Wait -PassThru; exit $p.ExitCode"
if errorlevel 1 pause
