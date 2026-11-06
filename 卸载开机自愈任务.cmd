@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$script = (Resolve-Path '.\scripts\Uninstall-StartupTask.ps1').Path; Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script) -Wait"
if errorlevel 1 pause
