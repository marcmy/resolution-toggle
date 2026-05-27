[CmdletBinding()]
param(
    [switch]$Configure,
    [switch]$DebugErrors
)

$ErrorActionPreference = "Stop"

$AppName = "Resolution Toggle"
$ConfigPath = Join-Path $PSScriptRoot "settings.json"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class DisplayUtil {
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
    public const int DISP_CHANGE_NOTUPDATED = -3;
    public const int CDS_UPDATEREGISTRY = 0x00000001;
    public const int DM_PELSWIDTH = 0x80000;
    public const int DM_PELSHEIGHT = 0x100000;
    public const int DM_DISPLAYFREQUENCY = 0x400000;
    public const int DM_DISPLAYFIXEDOUTPUT = 0x20000000;
    public const int DMDFO_DEFAULT = 0;
    public const int DMDFO_STRETCH = 1;
    public const int DMDFO_CENTER = 2;
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

function Show-Message {
    param(
        [string]$Message,
        [string]$Title = $AppName,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon) | Out-Null
}

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

    $primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen
    if ($primaryScreen -and -not [string]::IsNullOrWhiteSpace($primaryScreen.DeviceName)) {
        return $primaryScreen.DeviceName
    }

    return $null
}

function New-DevMode {
    $mode = New-Object DisplayUtil+DEVMODE
    $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)
    return $mode
}

function Get-CurrentMode {
    param([string]$Display)

    $mode = New-DevMode
    if (-not [DisplayUtil]::EnumDisplaySettings($Display, [DisplayUtil]::ENUM_CURRENT_SETTINGS, [ref]$mode)) {
        throw "Could not read the current display mode."
    }

    return $mode
}

function Get-DisplayModes {
    param([string]$Display)

    $modes = New-Object System.Collections.Generic.List[object]
    for ($i = 0; ; $i++) {
        $mode = New-DevMode
        if (-not [DisplayUtil]::EnumDisplaySettings($Display, $i, [ref]$mode)) {
            break
        }

        if ($mode.dmPelsWidth -gt 0 -and $mode.dmPelsHeight -gt 0 -and $mode.dmDisplayFrequency -gt 0) {
            $modes.Add([pscustomobject]@{
                Index = [int]$i
                Width = [int]$mode.dmPelsWidth
                Height = [int]$mode.dmPelsHeight
                Frequency = [int]$mode.dmDisplayFrequency
                BitsPerPel = [int]$mode.dmBitsPerPel
            })
        }
    }

    return @($modes.ToArray())
}

function Find-BestMode {
    param(
        [object[]]$Modes,
        [int]$Width,
        [int]$Height
    )

    $best = $null
    foreach ($mode in $Modes) {
        if ($mode.Width -ne $Width -or $mode.Height -ne $Height) {
            continue
        }

        if (
            $null -eq $best -or
            $mode.Frequency -gt $best.Frequency -or
            (
                $mode.Frequency -eq $best.Frequency -and
                $mode.BitsPerPel -gt $best.BitsPerPel
            )
        ) {
            $best = $mode
        }
    }

    return $best
}

function Get-DisplayModeByIndex {
    param(
        [string]$Display,
        [int]$Index
    )

    $mode = New-DevMode
    if (-not [DisplayUtil]::EnumDisplaySettings($Display, $Index, [ref]$mode)) {
        throw "Could not read the selected display mode."
    }

    return $mode
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

function Format-Resolution {
    param(
        [int]$Width,
        [int]$Height
    )

    return ("{0}x{1}" -f $Width, $Height)
}

function Get-SuggestedStretchResolution {
    param([object]$CurrentMode)

    $height = [int]$CurrentMode.dmPelsHeight
    $width = [int][math]::Round($height * 4 / 3)
    return Format-Resolution -Width $width -Height $height
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $null
    }

    Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

function Save-Config {
    param([object]$Config)

    $Config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
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

function Test-RapidRelaunch {
    param([object]$Config)

    if (-not $Config.LastSwitchAt) {
        return $false
    }

    $lastSwitch = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Config.LastSwitchAt, [ref]$lastSwitch)) {
        return $false
    }

    return ((Get-Date) - $lastSwitch).TotalSeconds -lt 3
}

function Get-VideoVendor {
    try {
        $names = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { $_.Name })
        $joined = ($names -join " ")
        if ($joined -match 'NVIDIA') {
            return "NVIDIA"
        }
        if ($joined -match 'AMD|Radeon|Advanced Micro Devices') {
            return "AMD"
        }
    } catch {
    }

    return "Unknown"
}

function Get-ScalingHelpText {
    param([string]$Scaling)

    $targetText = if ($Scaling -eq "Stretch") { "stretched fullscreen" } else { "black bars / centered" }
    $vendor = Get-VideoVendor

    $common = "Resolution Toggle asked Windows for $targetText mode, but your display driver did not confirm it.`n`nIf the picture does not look right, set it manually here:"

    $nvidia = "NVIDIA App: if your NVIDIA App has display scaling, look under System > Displays. If you do not see scaling there, use NVIDIA Control Panel instead.`n`nNVIDIA Control Panel: right-click the desktop > NVIDIA Control Panel > Display > Adjust desktop size and position > Scaling tab. Choose Full-screen for stretched, or Aspect ratio / No scaling for black bars, then click Apply."
    $amd = "AMD Software: right-click the desktop > AMD Software: Adrenalin Edition or AMD Radeon Settings > Display. Turn GPU Scaling on, then set Scaling Mode. Choose Full panel for stretched, or Preserve aspect ratio / Center for black bars."

    if ($vendor -eq "NVIDIA") {
        return "$common`n`n$nvidia"
    }
    if ($vendor -eq "AMD") {
        return "$common`n`n$amd"
    }

    return "$common`n`n$nvidia`n`n$amd"
}

function Show-SetupForm {
    param([object]$CurrentMode)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Resolution Toggle Setup"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(430, 305)
    $form.TopMost = $true

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = "Choose the two resolutions you want the desktop icon to switch between."
    $intro.Location = New-Object System.Drawing.Point(14, 14)
    $intro.Size = New-Object System.Drawing.Size(400, 36)

    $nativeLabel = New-Object System.Windows.Forms.Label
    $nativeLabel.Text = "Normal/native resolution"
    $nativeLabel.Location = New-Object System.Drawing.Point(14, 58)
    $nativeLabel.Size = New-Object System.Drawing.Size(190, 20)

    $nativeBox = New-Object System.Windows.Forms.TextBox
    $nativeBox.Location = New-Object System.Drawing.Point(214, 55)
    $nativeBox.Size = New-Object System.Drawing.Size(185, 24)
    $nativeBox.Text = Format-Resolution -Width $CurrentMode.dmPelsWidth -Height $CurrentMode.dmPelsHeight

    $customLabel = New-Object System.Windows.Forms.Label
    $customLabel.Text = "Custom/stretch resolution"
    $customLabel.Location = New-Object System.Drawing.Point(14, 92)
    $customLabel.Size = New-Object System.Drawing.Size(190, 20)

    $customBox = New-Object System.Windows.Forms.TextBox
    $customBox.Location = New-Object System.Drawing.Point(214, 89)
    $customBox.Size = New-Object System.Drawing.Size(185, 24)
    $customBox.Text = Get-SuggestedStretchResolution -CurrentMode $CurrentMode

    $scalingGroup = New-Object System.Windows.Forms.GroupBox
    $scalingGroup.Text = "When using the custom resolution"
    $scalingGroup.Location = New-Object System.Drawing.Point(14, 130)
    $scalingGroup.Size = New-Object System.Drawing.Size(385, 105)

    $stretchRadio = New-Object System.Windows.Forms.RadioButton
    $stretchRadio.Text = "Stretch to fill the whole screen"
    $stretchRadio.Location = New-Object System.Drawing.Point(14, 24)
    $stretchRadio.Size = New-Object System.Drawing.Size(330, 20)
    $stretchRadio.Checked = $true

    $centerRadio = New-Object System.Windows.Forms.RadioButton
    $centerRadio.Text = "Use black bars / centered"
    $centerRadio.Location = New-Object System.Drawing.Point(14, 49)
    $centerRadio.Size = New-Object System.Drawing.Size(330, 20)

    $defaultRadio = New-Object System.Windows.Forms.RadioButton
    $defaultRadio.Text = "Leave my driver setting alone"
    $defaultRadio.Location = New-Object System.Drawing.Point(14, 74)
    $defaultRadio.Size = New-Object System.Drawing.Size(330, 20)

    $scalingGroup.Controls.AddRange(@($stretchRadio, $centerRadio, $defaultRadio))

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "Save"
    $okButton.Location = New-Object System.Drawing.Point(235, 255)
    $okButton.Size = New-Object System.Drawing.Size(78, 28)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(321, 255)
    $cancelButton.Size = New-Object System.Drawing.Size(78, 28)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton
    $form.Controls.AddRange(@($intro, $nativeLabel, $nativeBox, $customLabel, $customBox, $scalingGroup, $okButton, $cancelButton))

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $scaling = "Default"
    if ($stretchRadio.Checked) {
        $scaling = "Stretch"
    } elseif ($centerRadio.Checked) {
        $scaling = "Center"
    }

    return [pscustomobject]@{
        NativeText = $nativeBox.Text
        CustomText = $customBox.Text
        Scaling = $scaling
    }
}

function Configure-ResolutionToggle {
    param(
        [string]$Display,
        [object[]]$Modes,
        [object]$CurrentMode
    )

    while ($true) {
        $entry = Show-SetupForm -CurrentMode $CurrentMode
        if ($null -eq $entry) {
            return
        }

        $native = Parse-Resolution $entry.NativeText
        $custom = Parse-Resolution $entry.CustomText
        if (-not $native -or -not $custom) {
            Show-Message "Use a resolution like 1920x1080 or 1440x1080." "Resolution Toggle Setup" ([System.Windows.Forms.MessageBoxIcon]::Warning)
            continue
        }

        $nativeMode = Find-BestMode -Modes $Modes -Width $native.Width -Height $native.Height
        $customMode = Find-BestMode -Modes $Modes -Width $custom.Width -Height $custom.Height

        if (-not $nativeMode) {
            Show-Message "$(Format-Resolution $native.Width $native.Height) is not available right now. Pick a resolution Windows already shows for this monitor." "Resolution Toggle Setup" ([System.Windows.Forms.MessageBoxIcon]::Warning)
            continue
        }

        if (-not $customMode) {
            Show-Message "$(Format-Resolution $custom.Width $custom.Height) is not available right now.`n`nCreate that custom resolution first in Windows, NVIDIA, AMD, or your monitor settings, then run Toggle Resolution again." "Resolution Toggle Setup" ([System.Windows.Forms.MessageBoxIcon]::Warning)
            continue
        }

        if ($native.Width -eq $custom.Width -and $native.Height -eq $custom.Height) {
            Show-Message "Pick two different resolutions." "Resolution Toggle Setup" ([System.Windows.Forms.MessageBoxIcon]::Warning)
            continue
        }

        $scalingLabel = switch ($entry.Scaling) {
            "Stretch" { "Stretch to fill the whole screen" }
            "Center" { "Black bars / centered" }
            default { "Leave my driver setting alone" }
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Save these settings?`n`nNormal: $(Format-Resolution $native.Width $native.Height)`nCustom: $(Format-Resolution $custom.Width $custom.Height)`nFullscreen look: $scalingLabel",
            "Resolution Toggle Setup",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            continue
        }

        Save-Config ([pscustomobject]@{
            Native = [pscustomobject]@{
                Width = $native.Width
                Height = $native.Height
            }
            Custom = [pscustomobject]@{
                Width = $custom.Width
                Height = $custom.Height
            }
            Scaling = $entry.Scaling
            ScalingHelpShown = $false
            LastSwitchAt = $null
            CreatedAt = (Get-Date).ToString("s")
        })

        Show-Message "Setup is done.`n`nLaunch Toggle Resolution again to switch resolutions."
        return
    }
}

function Set-BestDisplayMode {
    param(
        [string]$Display,
        [object[]]$Modes,
        [int]$Width,
        [int]$Height,
        [string]$Scaling
    )

    $bestMode = Find-BestMode -Modes $Modes -Width $Width -Height $Height
    if ($null -eq $bestMode) {
        throw "$(Format-Resolution $Width $Height) is not available right now."
    }

    [DisplayUtil+DEVMODE]$targetMode = Get-DisplayModeByIndex -Display $Display -Index ([int]$bestMode.Index)
    $scalingRequested = $Scaling -eq "Stretch" -or $Scaling -eq "Center"
    $targetMode.dmFields = [DisplayUtil]::DM_PELSWIDTH -bor [DisplayUtil]::DM_PELSHEIGHT -bor [DisplayUtil]::DM_DISPLAYFREQUENCY

    if ($scalingRequested) {
        $targetMode.dmFields = $targetMode.dmFields -bor [DisplayUtil]::DM_DISPLAYFIXEDOUTPUT
        if ($Scaling -eq "Stretch") {
            $targetMode.dmDisplayFixedOutput = [DisplayUtil]::DMDFO_STRETCH
        } else {
            $targetMode.dmDisplayFixedOutput = [DisplayUtil]::DMDFO_CENTER
        }
    }

    $flags = [DisplayUtil]::CDS_UPDATEREGISTRY
    $result = [DisplayUtil]::ChangeDisplaySettingsEx($Display, [ref]$targetMode, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
    $retriedWithoutScaling = $false
    $usedTemporaryFallback = $false

    if ($result -ne [DisplayUtil]::DISP_CHANGE_SUCCESSFUL -and $scalingRequested) {
        $retriedWithoutScaling = $true
        [DisplayUtil+DEVMODE]$targetMode = Get-DisplayModeByIndex -Display $Display -Index ([int]$bestMode.Index)
        $targetMode.dmFields = [DisplayUtil]::DM_PELSWIDTH -bor [DisplayUtil]::DM_PELSHEIGHT -bor [DisplayUtil]::DM_DISPLAYFREQUENCY
        $result = [DisplayUtil]::ChangeDisplaySettingsEx($Display, [ref]$targetMode, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
    }

    if ($result -eq [DisplayUtil]::DISP_CHANGE_NOTUPDATED) {
        $usedTemporaryFallback = $true
        [DisplayUtil+DEVMODE]$targetMode = Get-DisplayModeByIndex -Display $Display -Index ([int]$bestMode.Index)
        $targetMode.dmFields = [DisplayUtil]::DM_PELSWIDTH -bor [DisplayUtil]::DM_PELSHEIGHT -bor [DisplayUtil]::DM_DISPLAYFREQUENCY
        $result = [DisplayUtil]::ChangeDisplaySettingsEx($Display, [ref]$targetMode, [IntPtr]::Zero, 0, [IntPtr]::Zero)
    }

    if ($result -ne [DisplayUtil]::DISP_CHANGE_SUCCESSFUL) {
        throw "Windows could not switch to $(Format-Resolution $Width $Height). Result code: $result"
    }

    $actual = Get-CurrentMode -Display $Display
    $expectedFixedOutput = $null
    if ($Scaling -eq "Stretch") {
        $expectedFixedOutput = [DisplayUtil]::DMDFO_STRETCH
    } elseif ($Scaling -eq "Center") {
        $expectedFixedOutput = [DisplayUtil]::DMDFO_CENTER
    }

    [pscustomobject]@{
        Frequency = [int]$targetMode.dmDisplayFrequency
        ScalingRequested = $scalingRequested
        ScalingConfirmed = (-not $scalingRequested) -or ($actual.dmDisplayFixedOutput -eq $expectedFixedOutput)
        RetriedWithoutScaling = $retriedWithoutScaling
        UsedTemporaryFallback = $usedTemporaryFallback
    }
}

try {
    $display = Get-PrimaryDisplayName
    $current = Get-CurrentMode -Display $display
    $modes = @(Get-DisplayModes -Display $display)

    if (-not $modes -or $modes.Count -eq 0) {
        throw "Could not read the resolutions for this monitor."
    }

    $config = Read-Config
    if ($Configure -or $null -eq $config) {
        Configure-ResolutionToggle -Display $display -Modes $modes -CurrentMode $current
        exit 0
    }

    if (Test-RapidRelaunch -Config $config) {
        exit 0
    }

    $isCurrentlyCustom = $current.dmPelsWidth -eq [int]$config.Custom.Width -and $current.dmPelsHeight -eq [int]$config.Custom.Height
    if ($isCurrentlyCustom) {
        $target = $config.Native
        $targetScaling = "Default"
    } else {
        $target = $config.Custom
        $targetScaling = [string]$config.Scaling
    }

    $result = Set-BestDisplayMode -Display $display -Modes $modes -Width ([int]$target.Width) -Height ([int]$target.Height) -Scaling $targetScaling
    Set-ConfigProperty -Config $config -Name "LastSwitchAt" -Value (Get-Date).ToString("o")
    Save-Config $config

    if ($result.ScalingRequested -and (-not $result.ScalingConfirmed) -and (-not $config.ScalingHelpShown)) {
        Set-ConfigProperty -Config $config -Name "ScalingHelpShown" -Value $true
        Save-Config $config
        Show-Message (Get-ScalingHelpText -Scaling $targetScaling) $AppName ([System.Windows.Forms.MessageBoxIcon]::Information)
    } elseif ($result.UsedTemporaryFallback) {
        Show-Message "Windows switched resolutions, but it would not save the change as the active display mode. If it snaps back again, your GPU driver may be forcing the native mode." $AppName ([System.Windows.Forms.MessageBoxIcon]::Information)
    }
} catch {
    if ($DebugErrors) {
        throw
    }

    Show-Message $_.Exception.Message $AppName ([System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
