#Requires -Version 7.4
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = './EntraOpsConfig.json',

    [Parameter(Mandatory = $false)]
    [string]$DestinationPath = './TmpUpdate',

    [Parameter(Mandatory = $false)]
    [string]$ArchivePath = './EntraOps-update-candidate.tar',

    [Parameter(Mandatory = $true)]
    [ValidateSet('OnChange', 'Always', 'Never')]
    [string]$ValidationFrequency,

    [Parameter(Mandatory = $true)]
    [bool]$RunBrowserTests,

    [Parameter(Mandatory = $true)]
    [ValidateSet('PullRequest', 'DirectPush')]
    [string]$PublicationMode,

    [Parameter(Mandatory = $false)]
    [string]$ValidationRequiredOverride,

    [Parameter(Mandatory = $false)]
    [string]$RunBrowserTestsOverride,

    [Parameter(Mandatory = $false)]
    [string]$PublicationModeOverride,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    # False when the EntraOpsUpdateAppClientId repository variable is empty. Workflow templates can
    # then never be published, so the run fails here instead of after a full candidate validation.
    [Parameter(Mandatory = $false)]
    [bool]$WorkflowPublisherConfigured = $true,

    [Parameter(Mandatory = $false)]
    [string]$GitHubOutputPath = $env:GITHUB_OUTPUT
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../EntraOps/EntraOps.psd1') -Force
$Candidate = Get-EntraOpsUpdateCandidate -ConfigFile $ConfigFile -DestinationPath $DestinationPath -ArchivePath $ArchivePath

$EffectiveRunBrowserTests = $RunBrowserTests
if ($env:GITHUB_EVENT_NAME -eq 'workflow_dispatch' -and $RunBrowserTestsOverride -in @('true', 'false')) {
    $EffectiveRunBrowserTests = [System.Convert]::ToBoolean($RunBrowserTestsOverride)
}
$EffectivePublicationMode = $PublicationMode
if ($env:GITHUB_EVENT_NAME -eq 'workflow_dispatch') {
    if ($PublicationModeOverride -eq 'pull-request') { $EffectivePublicationMode = 'PullRequest' }
    elseif ($PublicationModeOverride -eq 'direct-push') { $EffectivePublicationMode = 'DirectPush' }
}

$Decision = Get-EntraOpsUpdatePlan -Repository $Candidate.Repository -SourceCommit $Candidate.SourceCommit `
    -TargetUpdateFolders $Candidate.TargetUpdateFolders -ValidationFrequency $ValidationFrequency `
    -RunBrowserTests:$EffectiveRunBrowserTests -Force:$Force
if ($env:GITHUB_EVENT_NAME -eq 'workflow_dispatch' -and $ValidationRequiredOverride -in @('true', 'false')) {
    $Decision.ValidationRequired = [System.Convert]::ToBoolean($ValidationRequiredOverride)
}
if ($Candidate.TargetUpdateFolders -contains './.github/workflows' -and $Decision.UpdateRequired -and -not $Decision.ValidationRequired) {
    throw "Candidate validation cannot be disabled when './.github/workflows' is updated."
}
if ($Candidate.TargetUpdateFolders -contains './.github/workflows' -and $Decision.UpdateRequired -and -not $WorkflowPublisherConfigured) {
    $Message = "'./.github/workflows' is an update target, but the repository variable EntraOpsUpdateAppClientId is not set. Workflow definitions can only be published by the opt-in GitHub App (variable EntraOpsUpdateAppClientId and secret EntraOpsUpdateAppPrivateKey with Contents, Workflows, Pull requests, and Commit statuses write permissions). Configure the App or remove './.github/workflows' from AutomatedEntraOpsUpdate.TargetUpdateFolders. See docs/core.html 'Enable workflow definitions in automated updates'."
    Write-Host "::error title=EntraOps update publisher not configured::$Message"
    throw $Message
}

if (-not [string]::IsNullOrWhiteSpace($GitHubOutputPath)) {
    $Outputs = [ordered]@{
        source_sha          = $Candidate.SourceCommit
        candidate_digest    = $Candidate.ArchiveSha256
        update_required     = $Decision.UpdateRequired.ToString().ToLowerInvariant()
        validation_required = $Decision.ValidationRequired.ToString().ToLowerInvariant()
        run_browser_tests   = $Decision.RunBrowserTests.ToString().ToLowerInvariant()
        publication_mode    = $EffectivePublicationMode
    }
    foreach ($Output in $Outputs.GetEnumerator()) {
        "$($Output.Key)=$($Output.Value)" | Out-File -LiteralPath $GitHubOutputPath -Encoding utf8 -Append
    }
}
Write-Host "Resolved $($Candidate.Repository)@$($Candidate.SourceCommit). $($Decision.Reason) No candidate code was executed."
[pscustomobject]@{ Candidate = $Candidate; Decision = $Decision; PublicationMode = $EffectivePublicationMode }
