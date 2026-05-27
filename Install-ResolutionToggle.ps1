[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "ResolutionToggle"
$ToggleScript = Join-Path $InstallDir "Toggle-Resolution.ps1"
$Desktop = [Environment]::GetFolderPath("DesktopDirectory")
$ShortcutPath = Join-Path $Desktop "Toggle Resolution.lnk"
$LegacyShortcutPath = Join-Path $Desktop "Toggle 1920x1440 - 2560x1440.lnk"
$SourceIcon = Join-Path $PSScriptRoot "ToggleResolution.ico"
$InstalledIcon = Join-Path $InstallDir "ToggleResolution.ico"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if (Test-Path $SourceIcon) {
    Copy-Item $SourceIcon $InstalledIcon -Force
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class DisplayUtil {
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
    public const int DM_PELSWIDTH = 0x80000;
    public const int DM_PELSHEIGHT = 0x100000;
    public const int DM_DISPLAYFREQUENCY = 0x400000;
    public const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x00000004;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplayDevices(string lpDevice, int iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, int dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);
}
"@

function Get-PrimaryDisplayName {
    for ($i = 0; $i -lt 16; $i++) {
        $dd = New-Object DisplayUtil+DISPLAY_DEVICE
        $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)

        if ([DisplayUtil]::EnumDisplayDevices($null, $i, [ref]$dd, 0)) {
            if (($dd.StateFlags -band [DisplayUtil]::DISPLAY_DEVICE_PRIMARY_DEVICE) -ne 0) {
                return $dd.DeviceName
            }
        }
    }

    throw "Could not find primary display."
}

function Get-CurrentMode {
    param([string]$Display)

    $mode = New-Object DisplayUtil+DEVMODE
    $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)

    if (-not [DisplayUtil]::EnumDisplaySettings($Display, [DisplayUtil]::ENUM_CURRENT_SETTINGS, [ref]$mode)) {
        throw "Could not read current display mode."
    }

    [pscustomobject]@{
        Width = [int]$mode.dmPelsWidth
        Height = [int]$mode.dmPelsHeight
        Frequency = [int]$mode.dmDisplayFrequency
        BitsPerPel = [int]$mode.dmBitsPerPel
    }
}

function Get-DisplayModes {
    param([string]$Display)

    $modes = New-Object System.Collections.Generic.List[object]

    for ($i = 0; ; $i++) {
        $mode = New-Object DisplayUtil+DEVMODE
        $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)

        if (-not [DisplayUtil]::EnumDisplaySettings($Display, $i, [ref]$mode)) {
            break
        }

        if ($mode.dmPelsWidth -gt 0 -and $mode.dmPelsHeight -gt 0 -and $mode.dmDisplayFrequency -gt 0) {
            $modes.Add([pscustomobject]@{
                Width = [int]$mode.dmPelsWidth
                Height = [int]$mode.dmPelsHeight
                Frequency = [int]$mode.dmDisplayFrequency
                BitsPerPel = [int]$mode.dmBitsPerPel
            })
        }
    }

    $modes |
        Group-Object Width, Height, Frequency |
        ForEach-Object { $_.Group[0] } |
        Sort-Object Width, Height, Frequency
}

function Get-ResolutionSummary {
    param([object[]]$Modes)

    $Modes |
        Group-Object Width, Height |
        ForEach-Object {
            $best = $_.Group | Sort-Object Frequency -Descending | Select-Object -First 1
            [pscustomobject]@{
                Width = [int]$best.Width
                Height = [int]$best.Height
                MaxFrequency = [int]$best.Frequency
                Pixels = [int64]$best.Width * [int64]$best.Height
            }
        } |
        Sort-Object Pixels, Width, Height -Descending
}

function Find-BestModeForResolution {
    param(
        [object[]]$Modes,
        [int]$Width,
        [int]$Height
    )

    $Modes |
        Where-Object { $_.Width -eq $Width -and $_.Height -eq $Height } |
        Sort-Object Frequency, BitsPerPel -Descending |
        Select-Object -First 1
}

function Parse-Resolution {
    param([string]$Text)

    if ($Text -match '^\s*(\d{3,5})\s*[xX,* ]\s*(\d{3,5})\s*$') {
        return [pscustomobject]@{
            Width = [int]$Matches[1]
            Height = [int]$Matches[2]
        }
    }

    return $null
}

function Show-ModeList {
    param([object[]]$Modes)

    $summary = @(Get-ResolutionSummary -Modes $Modes)
    $top = @($summary | Select-Object -First 30)

    Write-Host "Detected primary-display modes, max refresh per resolution:"
    foreach ($mode in $top) {
        Write-Host ("  {0}x{1} @ {2}Hz" -f $mode.Width, $mode.Height, $mode.MaxFrequency)
    }

    if ($summary.Count -gt $top.Count) {
        Write-Host ("  ...and {0} more" -f ($summary.Count - $top.Count))
    }
}

function Prompt-Resolution {
    param(
        [string]$Title,
        [string]$DefaultValue,
        [object[]]$Modes
    )

    while ($true) {
        $inputText = Read-Host "$Title [$DefaultValue]"
        if ([string]::IsNullOrWhiteSpace($inputText)) {
            $inputText = $DefaultValue
        }

        $parsed = Parse-Resolution $inputText
        if (-not $parsed) {
            Write-Host "Invalid format. Use something like 1920x1440." -ForegroundColor Yellow
            continue
        }

        $bestMode = Find-BestModeForResolution -Modes $Modes -Width $parsed.Width -Height $parsed.Height
        if (-not $bestMode) {
            Write-Host ""
            Write-Host "$($parsed.Width)x$($parsed.Height) is not currently exposed as a valid mode for the primary monitor." -ForegroundColor Yellow
            Write-Host "Create it first in NVIDIA/AMD/Intel display settings, or pick one of the detected modes below."
            Write-Host ""
            Show-ModeList -Modes $Modes
            Write-Host ""
            continue
        }

        return [pscustomobject]@{
            Width = [int]$parsed.Width
            Height = [int]$parsed.Height
            Frequency = [int]$bestMode.Frequency
        }
    }
}

$display = Get-PrimaryDisplayName
$current = Get-CurrentMode -Display $display
$modes = @(Get-DisplayModes -Display $display)

if (-not $modes -or $modes.Count -eq 0) {
    throw "Could not enumerate display modes for the primary display."
}

$resSummary = @(Get-ResolutionSummary -Modes $modes)
$detectedNative = $resSummary | Select-Object -First 1

Write-Host ""
Write-Host "Resolution Toggle Installer"
Write-Host "==========================="
Write-Host ""
Write-Host "Primary display: $display"
Write-Host ("Current mode:    {0}x{1} @ {2}Hz" -f $current.Width, $current.Height, $current.Frequency)
Write-Host ("Default guess:   {0}x{1} @ {2}Hz" -f $detectedNative.Width, $detectedNative.Height, $detectedNative.MaxFrequency)
Write-Host ""
Show-ModeList -Modes $modes
Write-Host ""

$stretch = Prompt-Resolution `
    -Title "Secondary/stretch resolution" `
    -DefaultValue "1920x1440" `
    -Modes $modes

$defaultValue = "{0}x{1}" -f $detectedNative.Width, $detectedNative.Height

$native = Prompt-Resolution `
    -Title "Default/native resolution" `
    -DefaultValue $defaultValue `
    -Modes $modes

$toggleTemplate = @'
$StretchWidth = @STRETCH_WIDTH@
$StretchHeight = @STRETCH_HEIGHT@
$DefaultWidth = @DEFAULT_WIDTH@
$DefaultHeight = @DEFAULT_HEIGHT@

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class DisplayUtil {
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
    public const int DM_PELSWIDTH = 0x80000;
    public const int DM_PELSHEIGHT = 0x100000;
    public const int DM_DISPLAYFREQUENCY = 0x400000;
    public const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x00000004;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplayDevices(string lpDevice, int iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, int dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);
}
"@

function Show-ErrorBox {
    param([string]$Message)

    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        $Message,
        "Resolution Toggle",
        "OK",
        "Error"
    ) | Out-Null
}

try {
    function Get-PrimaryDisplayName {
        for ($i = 0; $i -lt 16; $i++) {
            $dd = New-Object DisplayUtil+DISPLAY_DEVICE
            $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)

            if ([DisplayUtil]::EnumDisplayDevices($null, $i, [ref]$dd, 0)) {
                if (($dd.StateFlags -band [DisplayUtil]::DISPLAY_DEVICE_PRIMARY_DEVICE) -ne 0) {
                    return $dd.DeviceName
                }
            }
        }

        throw "Could not find primary display."
    }

    function Get-CurrentMode {
        param([string]$Display)

        $mode = New-Object DisplayUtil+DEVMODE
        $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)

        if (-not [DisplayUtil]::EnumDisplaySettings($Display, [DisplayUtil]::ENUM_CURRENT_SETTINGS, [ref]$mode)) {
            throw "Could not read current display mode."
        }

        return $mode
    }

    function Get-BestMode {
        param(
            [string]$Display,
            [int]$Width,
            [int]$Height
        )

        $best = $null

        for ($i = 0; ; $i++) {
            $mode = New-Object DisplayUtil+DEVMODE
            $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)

            if (-not [DisplayUtil]::EnumDisplaySettings($Display, $i, [ref]$mode)) {
                break
            }

            if ($mode.dmPelsWidth -eq $Width -and $mode.dmPelsHeight -eq $Height) {
                if (
                    $null -eq $best -or
                    $mode.dmDisplayFrequency -gt $best.dmDisplayFrequency -or
                    (
                        $mode.dmDisplayFrequency -eq $best.dmDisplayFrequency -and
                        $mode.dmBitsPerPel -gt $best.dmBitsPerPel
                    )
                ) {
                    $best = $mode
                }
            }
        }

        return $best
    }

    function Set-BestDisplayMode {
        param(
            [string]$Display,
            [int]$Width,
            [int]$Height
        )

        $targetMode = Get-BestMode -Display $Display -Width $Width -Height $Height

        if ($null -eq $targetMode) {
            throw "${Width}x${Height} is not exposed as a valid display mode for the primary monitor."
        }

        $targetMode.dmFields = [DisplayUtil]::DM_PELSWIDTH -bor [DisplayUtil]::DM_PELSHEIGHT -bor [DisplayUtil]::DM_DISPLAYFREQUENCY

        $result = [DisplayUtil]::ChangeDisplaySettingsEx($Display, [ref]$targetMode, [IntPtr]::Zero, 0, [IntPtr]::Zero)

        if ($result -ne [DisplayUtil]::DISP_CHANGE_SUCCESSFUL) {
            throw "Failed to switch to ${Width}x${Height} @ $($targetMode.dmDisplayFrequency)Hz. Result code: $result"
        }
    }

    $display = Get-PrimaryDisplayName
    $current = Get-CurrentMode -Display $display

    if ($current.dmPelsWidth -eq $StretchWidth -and $current.dmPelsHeight -eq $StretchHeight) {
        Set-BestDisplayMode -Display $display -Width $DefaultWidth -Height $DefaultHeight
    } else {
        Set-BestDisplayMode -Display $display -Width $StretchWidth -Height $StretchHeight
    }
} catch {
    Show-ErrorBox $_.Exception.Message
}
'@

$toggleScriptContent = $toggleTemplate.
    Replace("@STRETCH_WIDTH@", [string]$stretch.Width).
    Replace("@STRETCH_HEIGHT@", [string]$stretch.Height).
    Replace("@DEFAULT_WIDTH@", [string]$native.Width).
    Replace("@DEFAULT_HEIGHT@", [string]$native.Height)

Set-Content -Path $ToggleScript -Value $toggleScriptContent -Encoding UTF8

$Pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $Pwsh) {
    $Pwsh = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
}

Remove-Item $LegacyShortcutPath -Force -ErrorAction SilentlyContinue

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $Pwsh
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ToggleScript`""
$Shortcut.WorkingDirectory = $InstallDir
if (Test-Path $InstalledIcon) {
    $Shortcut.IconLocation = "$InstalledIcon,0"
} else {
    $Shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
}
$Shortcut.Description = "Toggle resolution between $($stretch.Width)x$($stretch.Height) and $($native.Width)x$($native.Height), using max refresh"
$Shortcut.Save()

Write-Host ""
Write-Host "Installed desktop shortcut:"
Write-Host "  $ShortcutPath"
Write-Host ""
Write-Host "Configured toggle:"
Write-Host ("  Secondary/stretch: {0}x{1} @ {2}Hz max" -f $stretch.Width, $stretch.Height, $stretch.Frequency)
Write-Host ("  Default/native:    {0}x{1} @ {2}Hz max" -f $native.Width, $native.Height, $native.Frequency)
Write-Host ""
Write-Host "The shortcut uses a custom monitor/toggle icon."
Write-Host "Click 'Toggle Resolution' on the desktop to switch between the two modes."
Write-Host "Rerun Install.cmd anytime to reconfigure."
Write-Host ""
