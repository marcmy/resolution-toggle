@{
    # Exact locations from the existing scripts, reviewed with PSScriptAnalyzer 1.25.0.
    # Naming and internal helper warnings do not require changing the public script behavior.
    Reviewed = @(
        'Build-SelfExtractingInstaller.ps1:209:PSUseSingularNouns'
        'Install-ResolutionToggle.ps1:47:PSUseShouldProcessForStateChangingFunctions'
        # Best-effort logging, corrupt-config cleanup, GPU detection and mutex cleanup.
        'Toggle-Resolution.ps1:113:PSAvoidUsingEmptyCatchBlock'
        'Toggle-Resolution.ps1:303:PSAvoidUsingEmptyCatchBlock'
        'Toggle-Resolution.ps1:373:PSAvoidUsingEmptyCatchBlock'
        'Toggle-Resolution.ps1:709:PSAvoidUsingEmptyCatchBlock'
        'Toggle-Resolution.ps1:497:PSReviewUnusedParameter'
        # In-memory helpers; the display-changing entry point is interactive.
        'Toggle-Resolution.ps1:137:PSUseShouldProcessForStateChangingFunctions'
        'Toggle-Resolution.ps1:334:PSUseShouldProcessForStateChangingFunctions'
        'Toggle-Resolution.ps1:570:PSUseShouldProcessForStateChangingFunctions'
        'Toggle-Resolution.ps1:220:PSUseApprovedVerbs'
        'Toggle-Resolution.ps1:495:PSUseApprovedVerbs'
        'Toggle-Resolution.ps1:107:PSAvoidOverwritingBuiltInCmdlets'
        'Toggle-Resolution.ps1:154:PSUseSingularNouns'
    )
}
