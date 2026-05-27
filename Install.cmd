@echo off
setlocal
title Install Resolution Toggle

where pwsh.exe >nul 2>nul
if %errorlevel%==0 (
    set "PS=pwsh.exe"
) else (
    set "PS=powershell.exe"
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Install-ResolutionToggle.ps1"
