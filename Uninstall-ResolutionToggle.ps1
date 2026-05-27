[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$AppName = "Resolution Toggle"
$InstallDir = Join-Path $env:LOCALAPPDATA "ResolutionToggle"
$Desktop = [Environment]::GetFolderPath("DesktopDirectory")
$Programs = [Environment]::GetFolderPath("Programs")
$StartMenuDir = Join-Path $Programs $AppName
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ResolutionToggle"
$Shortcuts = @(
    (Join-Path $Desktop "Toggle Resolution.lnk"),
    (Join-Path $Desktop "Toggle 1920x1440 - 2560x1440.lnk")
)

function Show-Message {
    param([string]$Message)

    if ($Quiet) {
        return
    }

    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Message, $AppName, "OK", "Information") | Out-Null
    } catch {
        Write-Host $Message
    }
}

try {
    foreach ($shortcut in $Shortcuts) {
        Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $StartMenuDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue

    Show-Message "Resolution Toggle has been uninstalled."

    $cleanupScript = Join-Path $env:TEMP ("ResolutionToggleCleanup-{0}.cmd" -f $PID)
    $cleanupContent = @"
@echo off
timeout /t 2 /nobreak >nul
rmdir /s /q "$InstallDir" 2>nul
del "%~f0" 2>nul
"@
    Set-Content -LiteralPath $cleanupScript -Value $cleanupContent -Encoding ASCII
    Start-Process -FilePath "$env:ComSpec" -ArgumentList "/c", "`"$cleanupScript`"" -WindowStyle Hidden
} catch {
    if (-not $Quiet) {
        Show-Message "Uninstall failed: $($_.Exception.Message)"
    }
    exit 1
}
