@echo off
setlocal
title Uninstall Resolution Toggle

powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Uninstall-ResolutionToggle.ps1"
