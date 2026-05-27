@echo off
setlocal
title Install Resolution Toggle

powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Install-ResolutionToggle.ps1"
