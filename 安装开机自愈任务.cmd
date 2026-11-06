@echo off
setlocal
set "SCRIPT_ENTRY=%~dp0scripts\Install-StartupTask.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ""' + $env:SCRIPT_ENTRY + '""') -Wait -PassThru; exit $p.ExitCode"
if errorlevel 1 pause
