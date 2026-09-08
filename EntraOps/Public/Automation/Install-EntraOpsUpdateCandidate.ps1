function Install-EntraOpsUpdateCandidate {
    <#
    .SYNOPSIS
        Applies a prepared EntraOps update candidate and removes its checkout.

    .DESCRIPTION
        Converts the validation result produced by a separate pipeline stage into the corresponding
        Update-EntraOps parameters. The prepared candidate is removed after application so its nested
        .git directory cannot be included in a later publication step. This command contains no
        CI-provider logic and can be used by GitHub Actions, GitLab CI, Azure Pipelines, or locally.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigFile = './EntraOpsConfig.json',

        [Parameter(Mandatory = $false)]
        [string]$CandidatePath = './TmpUpdate',

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{40}$')]
        [string]$SourceCommit,

        [Parameter(Mandatory = $true)]
        [bool]$ValidationRequired,

        [Parameter(Mandatory = $false)]
        [bool]$BrowserTestsValidated
    )

    $ErrorActionPreference = 'Stop'
    $UpdateParameters = @{ ConfigFile = $ConfigFile; PreparedCandidatePath = $CandidatePath }
    if ($ValidationRequired) {
        $UpdateParameters.ValidatedSourceCommit = $SourceCommit
        if ($BrowserTestsValidated) { $UpdateParameters.BrowserTestsValidated = $true }
    } else {
        $UpdateParameters.SkipCandidateValidation = $true
    }

    try {
        Update-EntraOps @UpdateParameters
    } finally {
        Disconnect-EntraOps | Out-Null
    }
    if (Test-Path -LiteralPath $CandidatePath) {
        Remove-Item -LiteralPath $CandidatePath -Recurse -Force
    }
}
