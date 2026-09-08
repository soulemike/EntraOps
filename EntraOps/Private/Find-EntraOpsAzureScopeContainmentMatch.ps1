function Find-EntraOpsAzureScopeContainmentMatch {
    <#
    .SYNOPSIS
        Returns the first bucketed Tier scope that hierarchically overlaps an ARM scope.
    .DESCRIPTION
        Single shared containment convention for classifying an ARM scope against the Tier0/Tier1
        scope buckets resolved by Get-EntraOpsClassificationAzureResourceScope, used by both
        Resolve-EntraOpsAzureScopeReasoningTier (EAM output) and
        Get-EntraOpsIdGovScopeClassification (ScopeReasoning_IdentityGovernance.json) so the two
        outputs cannot contradict each other for the same scope.

        A scope matches a bucketed scope when it
        - equals it,
        - contains it beneath itself (roles at the scope reach every resource below it), or
        - lies beneath it. The buckets hold the critical resource paths and every ARM ancestor above
          them without distinguishing the two, so a scope below a bucketed path may be part of the
          critical resource itself and is matched conservatively (over-classify rather than risk
          missing a real Tier0/Tier1 exposure).
    .PARAMETER Scope
        Normalized ARM scope path (lowercase, no trailing slash).
    .PARAMETER BucketedScopes
        Normalized bucketed Tier scope paths (lowercase, no trailing slash, "/" already filtered out).
    .OUTPUTS
        [string] The first matching bucketed scope, or $null when none overlaps.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$BucketedScopes = @()
    )

    foreach ($BucketedScope in $BucketedScopes) {
        if ([string]::IsNullOrEmpty($BucketedScope)) { continue }
        if ($Scope -eq $BucketedScope -or
            $BucketedScope.StartsWith("$Scope/") -or
            $Scope.StartsWith("$BucketedScope/")) {
            return $BucketedScope
        }
    }
    return $null
}
