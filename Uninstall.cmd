@echo off
setlocal
title Uninstall Resolution Toggle

where pwsh.exe >nul 2>nul
if %errorlevel%==0 (
    set "PS=pwsh.exe"
) else (
    set "PS=powershell.exe"
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$Desktop=[Environment]::GetFolderPath('DesktopDirectory'); Remove-Item (Join-Path $Desktop 'Toggle Resolution.lnk') -Force -ErrorAction SilentlyContinue; Remove-Item (Join-Path $Desktop 'Toggle 1920x1440 - 2560x1440.lnk') -Force -ErrorAction SilentlyContinue; Remove-Item (Join-Path $env:LOCALAPPDATA 'ResolutionToggle') -Recurse -Force -ErrorAction SilentlyContinue; Write-Host 'Resolution Toggle removed.'"

echo.
pause
