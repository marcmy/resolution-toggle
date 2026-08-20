[CmdletBinding()]
param(
    [switch]$Guard,
    [switch]$Configure
)

$ErrorActionPreference = "Stop"

$AppName = "Resolution Toggle"
$MainScript = Join-Path $PSScriptRoot "Toggle-Resolution.ps1"
$ConfigPath = Join-Path $PSScriptRoot "settings.json"
$LogPath = Join-Path $PSScriptRoot "ResolutionToggle.log"
$StopSignalPath = Join-Path $PSScriptRoot "custom-guard.stop"
$PowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ResolutionGuardDisplayUtil {
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
    public const int DM_BITSPERPEL = 0x40000;
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

function Write-Log {
    param([string]$Message)

    try {
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        Add-Content -LiteralPath $LogPath -Value "[$stamp] $Message" -Encoding UTF8
    } catch {
    }
}

function New-DevMode {
    $mode = New-Object ResolutionGuardDisplayUtil+DEVMODE
    $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)
    return $mode
}

function Get-PrimaryDisplayName {
    for ($i = 0; $i -lt 16; $i++) {
        $dd = New-Object ResolutionGuardDisplayUtil+DISPLAY_DEVICE
        $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)
        if ([ResolutionGuardDisplayUtil]::EnumDisplayDevices($null, $i, [ref]$dd, 0)) {
            if (($dd.StateFlags -band [ResolutionGuardDisplayUtil]::DISPLAY_DEVICE_PRIMARY_DEVICE) -ne 0) {
                return $dd.DeviceName
            }
        }
    }

    throw "Could not find the primary display."
}

function Get-CurrentMode {
    param([string]$Display)

    $mode = New-DevMode
    if (-not [ResolutionGuardDisplayUtil]::EnumDisplaySettings($Display, [ResolutionGuardDisplayUtil]::ENUM_CURRENT_SETTINGS, [ref]$mode)) {
        throw "Could not read the current display mode."
    }
    return $mode
}

function Get-BestModeIndex {
    param(
        [string]$Display,
        [int]$Width,
        [int]$Height
    )

    $bestIndex = -1
    $bestFrequency = -1
    $bestBits = -1

    for ($i = 0; ; $i++) {
        $mode = New-DevMode
        if (-not [ResolutionGuardDisplayUtil]::EnumDisplaySettings($Display, $i, [ref]$mode)) {
            break
        }

        if ($mode.dmPelsWidth -eq $Width -and $mode.dmPelsHeight -eq $Height) {
            if ($mode.dmDisplayFrequency -gt $bestFrequency -or ($mode.dmDisplayFrequency -eq $bestFrequency -and $mode.dmBitsPerPel -gt $bestBits)) {
                $bestIndex = $i
                $bestFrequency = [int]$mode.dmDisplayFrequency
                $bestBits = [int]$mode.dmBitsPerPel
            }
        }
    }

    return $bestIndex
}

function Set-DisplayModeTemporary {
    param(
        [string]$Display,
        [int]$Width,
        [int]$Height
    )

    $index = Get-BestModeIndex -Display $Display -Width $Width -Height $Height
    if ($index -lt 0) {
        throw "${Width}x${Height} is not currently exposed by Windows."
    }

    $mode = New-DevMode
    if (-not [ResolutionGuardDisplayUtil]::EnumDisplaySettings($Display, $index, [ref]$mode)) {
        throw "Could not read display mode index $index."
    }

    $mode.dmFields = $mode.dmFields -bor [ResolutionGuardDisplayUtil]::DM_BITSPERPEL -bor [ResolutionGuardDisplayUtil]::DM_PELSWIDTH -bor [ResolutionGuardDisplayUtil]::DM_PELSHEIGHT -bor [ResolutionGuardDisplayUtil]::DM_DISPLAYFREQUENCY
    $result = [ResolutionGuardDisplayUtil]::ChangeDisplaySettingsEx($Display, [ref]$mode, [IntPtr]::Zero, 0, [IntPtr]::Zero)
    if ($result -ne [ResolutionGuardDisplayUtil]::DISP_CHANGE_SUCCESSFUL) {
        throw "Windows rejected guard restore to ${Width}x${Height}. Result code: $result"
    }

    return [int]$mode.dmDisplayFrequency
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function Save-Config {
    param([object]$Config)

    $json = $Config | ConvertTo-Json -Depth 4
    $tempPath = "$ConfigPath.launcher.$PID.tmp"
    $backupPath = "$ConfigPath.launcher.bak"

    try {
        $json | Set-Content -LiteralPath $tempPath -Encoding UTF8 -ErrorAction Stop
        $null = Get-Content -LiteralPath $tempPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            [System.IO.File]::Replace($tempPath, $ConfigPath, $backupPath, $true)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        } else {
            [System.IO.File]::Move($tempPath, $ConfigPath)
        }
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-ConfigProperty {
    param(
        [object]$Config,
        [string]$Name,
        [object]$Value
    )

    if ($Config.PSObject.Properties[$Name]) {
        $Config.$Name = $Value
    } else {
        $Config | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Stop-CustomGuard {
    try {
        Set-Content -LiteralPath $StopSignalPath -Value (Get-Date).ToString("o") -Encoding ASCII -Force
    } catch {
    }
    Start-Sleep -Milliseconds 500
}

function Start-CustomGuard {
    Remove-Item -LiteralPath $StopSignalPath -Force -ErrorAction SilentlyContinue
    $args = "-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Guard"
    Start-Process -FilePath $PowerShellPath -ArgumentList $args -WindowStyle Hidden | Out-Null
}

function Invoke-MainScript {
    param([switch]$RunConfigure)

    $args = "-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$MainScript`""
    if ($RunConfigure) {
        $args += " -Configure"
    }

    Start-Process -FilePath $PowerShellPath -ArgumentList $args -WindowStyle Hidden -Wait | Out-Null
}

if ($Guard) {
    $createdGuard = $false
    $guardMutex = New-Object System.Threading.Mutex($true, "Local\ResolutionToggleCustomGuard", [ref]$createdGuard)

    try {
        if (-not $createdGuard) {
            exit 0
        }

        $display = Get-PrimaryDisplayName
        Write-Log "Custom guard started."
        $lastRestoreAt = [DateTime]::MinValue

        while ($true) {
            if (Test-Path -LiteralPath $StopSignalPath -PathType Leaf) {
                Write-Log "Custom guard stop signal received."
                break
            }

            $config = Read-Config
            if ($null -eq $config -or [string]$config.LastTarget -ne "Custom") {
                Write-Log "Custom guard exiting because Custom is no longer the intended state."
                break
            }

            $width = [int]$config.Custom.Width
            $height = [int]$config.Custom.Height
            $current = Get-CurrentMode -Display $display

            if ($current.dmPelsWidth -ne $width -or $current.dmPelsHeight -ne $height) {
                $now = Get-Date
                if (($now - $lastRestoreAt).TotalMilliseconds -ge 350) {
                    Write-Log ("WINDOWS RESET DETECTED: actual={0}x{1}@{2}Hz; restoring {3}x{4}." -f $current.dmPelsWidth, $current.dmPelsHeight, $current.dmDisplayFrequency, $width, $height)
                    $frequency = Set-DisplayModeTemporary -Display $display -Width $width -Height $height
                    Start-Sleep -Milliseconds 120
                    $after = Get-CurrentMode -Display $display
                    Write-Log ("Guard restore result. Actual={0}x{1}@{2}Hz requestedRefresh={3}Hz" -f $after.dmPelsWidth, $after.dmPelsHeight, $after.dmDisplayFrequency, $frequency)
                    $lastRestoreAt = $now
                }
            }

            Start-Sleep -Milliseconds 250
        }
    } catch {
        Write-Log "Custom guard error: $($_.Exception.Message)"
    } finally {
        if ($guardMutex) {
            if ($createdGuard) {
                try { $guardMutex.ReleaseMutex() } catch {}
            }
            $guardMutex.Dispose()
        }
    }

    exit 0
}

$createdLauncher = $false
$launcherMutex = New-Object System.Threading.Mutex($true, "Local\ResolutionToggleLauncher", [ref]$createdLauncher)

try {
    if (-not $createdLauncher) {
        exit 0
    }

    Stop-CustomGuard

    if ($Configure) {
        Invoke-MainScript -RunConfigure
        exit 0
    }

    $config = Read-Config
    if ($null -eq $config) {
        Invoke-MainScript
        exit 0
    }

    $display = Get-PrimaryDisplayName
    $current = Get-CurrentMode -Display $display
    $isCustom = $current.dmPelsWidth -eq [int]$config.Custom.Width -and $current.dmPelsHeight -eq [int]$config.Custom.Height
    $intendedCustom = [string]$config.LastTarget -eq "Custom"

    # LastTarget represents what the user asked for, not merely what Windows happens
    # to be showing. This matters when Windows has silently reverted Custom to Native.
    if ($intendedCustom) {
        if ($isCustom) {
            Set-ConfigProperty -Config $config -Name "LastSwitchAt" -Value $null
            Save-Config $config
            Invoke-MainScript
        } else {
            # Windows already reset us to native. A click now means "stay native / turn
            # custom mode off", so do not accidentally switch custom back on.
            Set-ConfigProperty -Config $config -Name "LastTarget" -Value "Native"
            Set-ConfigProperty -Config $config -Name "LastSwitchAt" -Value (Get-Date).ToString("o")
            Save-Config $config
            Write-Log ("Launcher stopped Custom while Windows was already at {0}x{1}." -f $current.dmPelsWidth, $current.dmPelsHeight)
        }
    } else {
        if (-not $isCustom) {
            Set-ConfigProperty -Config $config -Name "LastSwitchAt" -Value $null
            Save-Config $config
            Invoke-MainScript
        } else {
            Set-ConfigProperty -Config $config -Name "LastTarget" -Value "Custom"
            Save-Config $config
        }
    }

    $config = Read-Config
    if ($null -ne $config -and [string]$config.LastTarget -eq "Custom") {
        $current = Get-CurrentMode -Display $display
        if ($current.dmPelsWidth -eq [int]$config.Custom.Width -and $current.dmPelsHeight -eq [int]$config.Custom.Height) {
            Start-CustomGuard
            Write-Log "Launcher started Custom guard."
        }
    }
} catch {
    Write-Log "Launcher error: $($_.Exception.Message)"
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $AppName, "OK", "Error") | Out-Null
    } catch {
    }
    exit 1
} finally {
    if ($launcherMutex) {
        if ($createdLauncher) {
            try { $launcherMutex.ReleaseMutex() } catch {}
        }
        $launcherMutex.Dispose()
    }
}
