[CmdletBinding()]
param(
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$DistDir = Join-Path $RepoRoot "dist"
$OutputName = "resolution-toggle-v$Version.exe"
$OutputPath = Join-Path $DistDir $OutputName
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ResolutionToggleSfx-" + [guid]::NewGuid().ToString("N"))
$SourceRoot = Join-Path $BuildRoot "src"
$ArchivePath = Join-Path $BuildRoot "payload.7z"
$ConfigPath = Join-Path $BuildRoot "sfx-config.txt"

$Files = @(
    "Install.cmd",
    "Install-ResolutionToggle.ps1",
    "Toggle-Resolution.ps1",
    "Uninstall-ResolutionToggle.ps1",
    "Uninstall.cmd",
    "ToggleResolution.ico",
    "README.md",
    "LICENSE"
)

foreach ($file in $Files) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file missing: $file"
    }
}

$SevenZip = (Get-Command 7z.exe -ErrorAction Stop).Source
$SevenZipDir = Split-Path -Parent $SevenZip
$SfxModule = Join-Path $SevenZipDir "7z.sfx"
if (-not (Test-Path -LiteralPath $SfxModule -PathType Leaf)) {
    throw "7-Zip SFX module not found: $SfxModule"
}

function Add-FileBytes {
    param(
        [System.IO.Stream]$Output,
        [string]$Path
    )

    $inputStream = [System.IO.File]::OpenRead($Path)
    try {
        $inputStream.CopyTo($Output)
    } finally {
        $inputStream.Dispose()
    }
}

try {
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    New-Item -ItemType Directory -Force -Path $SourceRoot | Out-Null

    foreach ($file in $Files) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination $SourceRoot -Force
    }

$config = @"
;!@Install@!UTF-8!
Title="Resolution Toggle"
GUIMode="2"
RunProgram="Install.cmd"
;!@InstallEnd@!
"@
    Set-Content -Path $ConfigPath -Value $config -Encoding UTF8

    Push-Location $SourceRoot
    try {
        & $SevenZip a -t7z -mx=9 $ArchivePath @Files | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }

    $outputStream = [System.IO.File]::Create($OutputPath)
    try {
        Add-FileBytes -Output $outputStream -Path $SfxModule
        Add-FileBytes -Output $outputStream -Path $ConfigPath
        Add-FileBytes -Output $outputStream -Path $ArchivePath
    } finally {
        $outputStream.Dispose()
    }

    Get-Item -LiteralPath $OutputPath
} finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
