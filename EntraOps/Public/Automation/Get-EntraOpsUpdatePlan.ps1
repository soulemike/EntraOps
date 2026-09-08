function Get-EntraOpsUpdatePlan {
<#
.SYNOPSIS
    Determines whether a resolved update candidate needs to be validated and/or applied.

.DESCRIPTION
    Compares the immutable candidate identity and managed target set with the manifest written by the
    last successful Update-EntraOps run. A missing, malformed, or mismatched manifest is treated as an
    update so OnChange validation fails safe. ValidationFrequency controls whether validation runs for
    changes only, every invocation, or never. Use -Force for an explicit validation and reapplication
    of an unchanged candidate regardless of the configured frequency.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$SourceCommit,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$TargetUpdateFolders,

    [Parameter(Mandatory = $false)]
    [string]$ManifestPath = './.EntraOpsUpdateManifest.json',

    [Parameter(Mandatory = $false)]
    [ValidateSet('OnChange', 'Always', 'Never')]
    [string]$ValidationFrequency = 'OnChange',

    [Parameter(Mandatory = $false)]
    [bool]$RunBrowserTests = $true,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$Decision = [ordered]@{
    UpdateRequired     = $true
    ValidationRequired = $true
    RunBrowserTests    = $RunBrowserTests
    Reason             = ''
}

if ($Force) {
    $Decision.Reason = 'Validation and reapplication were explicitly forced.'
    return [pscustomobject]$Decision
}

$Manifest = $null
$ChangeReason = ''
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    $ChangeReason = 'No previous update manifest exists.'
} else {
    try {
        $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $ChangeReason = "The previous update manifest is unreadable: $($_.Exception.Message)"
    }
}

if ($null -ne $Manifest) {
    $CandidateTargets = @($TargetUpdateFolders | ForEach-Object { $_.Trim().Replace('\', '/') } | Sort-Object -Unique)
    $AppliedTargets = @($Manifest.TargetUpdateFolders | ForEach-Object { ([string]$_).Trim().Replace('\', '/') } | Sort-Object -Unique)
    $TargetsMatch = ($CandidateTargets -join "`n") -ceq ($AppliedTargets -join "`n")

    if ([string]$Manifest.Repository -ne $Repository) {
        $ChangeReason = "The update repository changed from '$($Manifest.Repository)' to '$Repository'."
    } elseif ([string]$Manifest.SourceCommit -ne $SourceCommit) {
        $ChangeReason = "A different source commit was resolved ($SourceCommit)."
    } elseif (-not $TargetsMatch) {
        $ChangeReason = 'The configured update target set changed.'
    }
}

$CandidateChanged = -not [string]::IsNullOrWhiteSpace($ChangeReason)
$FullyValidated = $null -ne $Manifest -and $Manifest.ValidatedBeforeApply -eq $true -and
    (-not $RunBrowserTests -or $Manifest.BrowserTestsRun -eq $true)

switch ($ValidationFrequency) {
    'Always' {
        $Decision.UpdateRequired = $CandidateChanged
        $Decision.ValidationRequired = $true
        $Decision.Reason = if ($CandidateChanged) { $ChangeReason } else { 'Validation is configured to run every time.' }
    }
    'Never' {
        $Decision.UpdateRequired = $CandidateChanged
        $Decision.ValidationRequired = $false
        $Decision.Reason = if ($CandidateChanged) { "$ChangeReason Candidate validation is disabled." } else { 'The candidate is unchanged and validation is disabled.' }
    }
    'OnChange' {
        if ($CandidateChanged) {
            $Decision.Reason = $ChangeReason
        } elseif (-not $FullyValidated) {
            # Reapply after validation so the manifest records that this exact candidate satisfied the
            # currently configured validation depth, avoiding repeated OnChange validation.
            $Decision.Reason = if ($Manifest.ValidatedBeforeApply -ne $true) {
                'The matching candidate was previously applied without candidate validation.'
            } else {
                'The matching candidate was previously applied without browser validation.'
            }
        } else {
            $Decision.UpdateRequired = $false
            $Decision.ValidationRequired = $false
            $Decision.Reason = "Candidate $Repository@$SourceCommit is already applied and validated for the configured targets."
        }
    }
}

if ($TargetUpdateFolders -contains './.github/workflows' -and $Decision.UpdateRequired -and -not $Decision.ValidationRequired) {
    $Decision.ValidationRequired = $true
    $Decision.Reason = "$($Decision.Reason) Candidate validation is mandatory when workflow templates are updated."
}

return [pscustomobject]$Decision
}
