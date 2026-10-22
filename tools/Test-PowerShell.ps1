$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0
Import-Module Pester -RequiredVersion 5.7.1

$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' }
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        throw "$($file.FullName): $($parseErrors -join '; ')"
    }
}

# Keep existing, reviewed findings visible while rejecting new warnings/errors.
$baseline = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'analyzer-baseline.psd1')
$findings = @(Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -Severity Error,Warning)
$findings | Format-Table ScriptName, Line, Severity, RuleName, Message -Wrap
$unexpected = @($findings | Where-Object { "$($_.ScriptName):$($_.Line):$($_.RuleName)" -notin $baseline.Reviewed })
if ($unexpected.Count -gt 0) {
    throw "PSScriptAnalyzer reported $($unexpected.Count) unreviewed finding(s)."
}

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $repoRoot 'tests'
$config.Run.PassThru = $true
$config.TestRegistry.Enabled = $false
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0 -or $result.PassedCount -eq 0) {
    throw "Pester failed: $($result.FailedCount) failed, $($result.PassedCount) passed."
}
