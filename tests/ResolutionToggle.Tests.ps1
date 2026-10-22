BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repoRoot 'Toggle-Resolution.ps1'), [ref]$tokens, [ref]$parseErrors)
    # Load only pure/config helpers. Never execute the entry point, Add-Type or display APIs.
    foreach ($name in @('Parse-Resolution', 'Format-Resolution', 'Find-BestMode', 'Get-SuggestedStretchResolution', 'Test-ConfigShape', 'Test-RapidRelaunch', 'Save-Config', 'Read-Config', 'Write-Log')) {
        $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        if ($null -eq $function) { throw "Missing helper: $name" }
        . ([scriptblock]::Create($function.Extent.Text))
    }
}

Describe 'Resolution selection' {
    It 'accepts supported separators and surrounding whitespace' -TestCases @(
        @{ Text = '1920x1080' }, @{ Text = ' 1920 X 1080 ' },
        @{ Text = '1920,1080' }, @{ Text = '1920*1080' }, @{ Text = '1920 1080' }
    ) {
        param($Text)
        $resolution = Parse-Resolution $Text
        $resolution.Width | Should -Be 1920
        $resolution.Height | Should -Be 1080
    }
    It 'rejects invalid resolutions' -TestCases @(
        @{ Text = '' }, @{ Text = '-1920x1080' }, @{ Text = '1920x0' },
        @{ Text = '1920x1080@144' }, @{ Text = '1920x1080extra' }
    ) {
        param($Text)
        Parse-Resolution $Text | Should -BeNullOrEmpty
    }
    It 'prefers refresh rate, then color depth, without choosing a different resolution' {
        $modes = @(
            [pscustomobject]@{ Width=1920; Height=1080; Frequency=60; BitsPerPel=32; Index=0 }
            [pscustomobject]@{ Width=1280; Height=720; Frequency=240; BitsPerPel=32; Index=1 }
            [pscustomobject]@{ Width=1920; Height=1080; Frequency=144; BitsPerPel=24; Index=2 }
            [pscustomobject]@{ Width=1920; Height=1080; Frequency=144; BitsPerPel=32; Index=3 }
        )
        (Find-BestMode -Modes $modes -Width 1920 -Height 1080).Index | Should -Be 3
        Find-BestMode -Modes $modes -Width 2560 -Height 1440 | Should -BeNullOrEmpty
    }
    It 'suggests a 4:3 width while preserving current height' {
        Get-SuggestedStretchResolution ([pscustomobject]@{ dmPelsHeight=1080 }) | Should -Be '1440x1080'
    }
}

Describe 'Configuration handling' {
    BeforeEach {
        $script:ConfigPath = Join-Path $TestDrive 'settings.json'
        $script:LogPath = Join-Path $TestDrive 'ResolutionToggle.log'
        $script:config = [pscustomobject]@{
            Native = [pscustomobject]@{ Width=1920; Height=1080 }
            Custom = [pscustomobject]@{ Width=1440; Height=1080 }
        }
    }
    It 'validates both positive resolution pairs' {
        Test-ConfigShape $config | Should -BeTrue
        $config.Custom.Width = 0
        Test-ConfigShape $config | Should -BeFalse
        Test-ConfigShape $null | Should -BeFalse
    }
    It 'creates and atomically replaces settings without leaving temporary files' {
        Save-Config $config
        (Read-Config).Native.Width | Should -Be 1920
        $config.Custom.Width = 1280
        Save-Config $config
        (Read-Config).Custom.Width | Should -Be 1280
        @(Get-ChildItem $TestDrive | Where-Object { $_.Name -like 'settings.json.*' }).Count | Should -Be 0
    }
    It 'treats missing settings as unconfigured' {
        Mock Test-Path { $false }
        Read-Config | Should -BeNullOrEmpty
    }
    It 'blocks a rapid relaunch and accepts an older or malformed timestamp' {
        Test-RapidRelaunch ([pscustomobject]@{ LastSwitchAt=(Get-Date).AddSeconds(-2).ToString('o') }) | Should -BeTrue
        Test-RapidRelaunch ([pscustomobject]@{ LastSwitchAt=(Get-Date).AddMinutes(-1).ToString('o') }) | Should -BeFalse
        Test-RapidRelaunch ([pscustomobject]@{ LastSwitchAt='invalid' }) | Should -BeFalse
        Test-RapidRelaunch ([pscustomobject]@{}) | Should -BeFalse
    }
}

Describe 'Self-extracting installer package' {
    BeforeAll {
        $buildRoot = Join-Path $TestDrive 'package-source'
        New-Item $buildRoot -ItemType Directory | Out-Null
        $payloadFiles = @('Install.cmd', 'Install-ResolutionToggle.ps1', 'Toggle-Resolution.ps1', 'Uninstall-ResolutionToggle.ps1', 'Uninstall.cmd', 'ToggleResolution.ico', 'README.md', 'LICENSE')
        foreach ($file in @($payloadFiles) + 'Build-SelfExtractingInstaller.ps1') {
            Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination $buildRoot
        }
        # Compile/package only. Never launch the EXE or installation scripts.
        & (Join-Path $buildRoot 'Build-SelfExtractingInstaller.ps1') -Version '9.8.7-test' | Out-Null
        $installer = Join-Path $buildRoot 'dist/resolution-toggle-v9.8.7-test.exe'
        $bytes = [System.IO.File]::ReadAllBytes($installer)
        $marker = [Text.Encoding]::ASCII.GetBytes('RT_PAYLOAD_V1')
        $lengthOffset = $bytes.Length - $marker.Length - 8
        $payloadLength = [BitConverter]::ToInt64($bytes, $lengthOffset)
        $script:payloadOffset = $lengthOffset - $payloadLength
    }
    It 'writes a PE bootstrapper with a valid payload footer' {
        [Text.Encoding]::ASCII.GetString($bytes, 0, 2) | Should -Be 'MZ'
        [Text.Encoding]::ASCII.GetString($bytes, $bytes.Length - $marker.Length, $marker.Length) | Should -Be 'RT_PAYLOAD_V1'
        $payloadLength | Should -BeGreaterThan 0
        $payloadOffset | Should -BeGreaterThan 0
    }
    It 'embeds exactly the expected files with unchanged contents' {
        Add-Type -AssemblyName System.IO.Compression
        $stream = [System.IO.MemoryStream]::new($bytes, [int]$payloadOffset, [int]$payloadLength)
        $zip = [System.IO.Compression.ZipArchive]::new($stream)
        try {
            @($zip.Entries).Count | Should -Be $payloadFiles.Count
            foreach ($entry in $zip.Entries) {
                $entry.FullName | Should -BeIn $payloadFiles
                $entryStream = $entry.Open()
                $copy = [System.IO.MemoryStream]::new()
                try {
                    $entryStream.CopyTo($copy)
                    [Convert]::ToBase64String($copy.ToArray()) | Should -Be ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $repoRoot $entry.FullName))))
                } finally { $entryStream.Dispose(); $copy.Dispose() }
            }
        } finally { $zip.Dispose(); $stream.Dispose() }
    }
    It 'fails before packaging when a required file is missing' {
        Remove-Item -LiteralPath (Join-Path $buildRoot 'Toggle-Resolution.ps1')
        { & (Join-Path $buildRoot 'Build-SelfExtractingInstaller.ps1') -Version 'missing-file' } | Should -Throw '*Required file missing: Toggle-Resolution.ps1*'
    }
}
