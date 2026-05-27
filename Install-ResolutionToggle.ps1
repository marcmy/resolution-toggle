[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$AppName = "Resolution Toggle"
$Version = "1.0.0"
$InstallDir = Join-Path $env:LOCALAPPDATA "ResolutionToggle"
$Desktop = [Environment]::GetFolderPath("DesktopDirectory")
$Programs = [Environment]::GetFolderPath("Programs")
$StartMenuDir = Join-Path $Programs $AppName
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ResolutionToggle"

$DesktopShortcut = Join-Path $Desktop "Toggle Resolution.lnk"
$LegacyShortcut = Join-Path $Desktop "Toggle 1920x1440 - 2560x1440.lnk"
$StartMenuToggle = Join-Path $StartMenuDir "Toggle Resolution.lnk"
$StartMenuSettings = Join-Path $StartMenuDir "Change Settings.lnk"
$StartMenuUninstall = Join-Path $StartMenuDir "Uninstall Resolution Toggle.lnk"

$FilesToInstall = @(
    "Toggle-Resolution.ps1",
    "Uninstall-ResolutionToggle.ps1",
    "Uninstall.cmd",
    "ToggleResolution.ico",
    "README.md",
    "LICENSE"
)

function Resolve-PowerShellPath {
    $pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    if ($pwsh) {
        return $pwsh
    }

    return "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
}

function Show-Message {
    param(
        [string]$Message,
        [string]$Title = $AppName
    )

    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Message, $Title, "OK", "Information") | Out-Null
    } catch {
        Write-Host $Message
    }
}

function New-AppShortcut {
    param(
        [string]$Path,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconLocation,
        [string]$Description
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    if ($IconLocation) {
        $shortcut.IconLocation = $IconLocation
    }
    $shortcut.Save()
}

trap {
    Show-Message "Install failed: $($_.Exception.Message)"
    exit 1
}

foreach ($file in $FilesToInstall) {
    $source = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Installer is missing required file: $file"
    }
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null

foreach ($file in $FilesToInstall) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $InstallDir -Force
}

$ps = Resolve-PowerShellPath
$toggleScript = Join-Path $InstallDir "Toggle-Resolution.ps1"
$uninstallScript = Join-Path $InstallDir "Uninstall-ResolutionToggle.ps1"
$icon = Join-Path $InstallDir "ToggleResolution.ico"
$iconLocation = if (Test-Path -LiteralPath $icon) { "$icon,0" } else { "$env:SystemRoot\System32\imageres.dll,109" }

Remove-Item -LiteralPath $LegacyShortcut -Force -ErrorAction SilentlyContinue

$toggleArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$toggleScript`""
$settingsArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$toggleScript`" -Configure"
$uninstallArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstallScript`""

New-AppShortcut `
    -Path $DesktopShortcut `
    -TargetPath $ps `
    -Arguments $toggleArgs `
    -WorkingDirectory $InstallDir `
    -IconLocation $iconLocation `
    -Description "Set up or toggle your display resolution"

New-AppShortcut `
    -Path $StartMenuToggle `
    -TargetPath $ps `
    -Arguments $toggleArgs `
    -WorkingDirectory $InstallDir `
    -IconLocation $iconLocation `
    -Description "Set up or toggle your display resolution"

New-AppShortcut `
    -Path $StartMenuSettings `
    -TargetPath $ps `
    -Arguments $settingsArgs `
    -WorkingDirectory $InstallDir `
    -IconLocation $iconLocation `
    -Description "Change the resolutions used by Resolution Toggle"

New-AppShortcut `
    -Path $StartMenuUninstall `
    -TargetPath $ps `
    -Arguments $uninstallArgs `
    -WorkingDirectory $InstallDir `
    -IconLocation "$env:SystemRoot\System32\imageres.dll,162" `
    -Description "Uninstall Resolution Toggle"

$estimatedSize = [math]::Ceiling(((Get-ChildItem -LiteralPath $InstallDir -File | Measure-Object -Property Length -Sum).Sum) / 1KB)
New-Item -Path $UninstallKey -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "DisplayName" -Value $AppName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "DisplayVersion" -Value $Version -PropertyType String -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "Publisher" -Value "marcmy" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "InstallLocation" -Value $InstallDir -PropertyType String -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "DisplayIcon" -Value $iconLocation -PropertyType String -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "UninstallString" -Value "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstallScript`"" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "QuietUninstallString" -Value "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstallScript`" -Quiet" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "EstimatedSize" -Value $estimatedSize -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "NoModify" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $UninstallKey -Name "NoRepair" -Value 1 -PropertyType DWord -Force | Out-Null

Show-Message "Resolution Toggle is installed.`n`nUse the Toggle Resolution icon on your desktop.`n`nThe first launch will ask for your resolutions. After that, launch it again anytime to toggle."
