<#
.SYNOPSIS
    Resolve the EAM tier of an ARM scope (subscription, resource group, resource) against the
    Tier0/Tier1 scope buckets persisted in ScopeReasoning_Azure.json.

.DESCRIPTION
    Used to classify Azure resources that have been onboarded to Identity Governance access package
    catalogs or access packages: an ARM scope is ControlPlane/ManagementPlane when it hierarchically
    overlaps a bucketed Tier0/Tier1 scope path (equals it, contains one beneath it, or lies beneath
    one) - see Find-EntraOpsAzureScopeContainmentMatch for the shared containment convention.
    Scopes without any Tier0/Tier1 classified resource are UserAccess.

.PARAMETER ArmScopeId
    ARM scope path to resolve (e.g. /subscriptions/<id> or a resource group/resource path).

.PARAMETER AzureScopeReasoning
    Parsed payload of ScopeReasoning_Azure.json (Tier0Scope/Tier1Scope), written by
    Update-EntraOpsClassificationControlPlaneScope. Pass $null when the file is not available -
    the function then returns $null so callers can fall back to an Unclassified/conservative result.

.EXAMPLE
    Resolve-EntraOpsAzureScopeReasoningTier -ArmScopeId "/subscriptions/xxxx" -AzureScopeReasoning $AzureScopeReasoning

.NOTES
    Memoized: callers resolve thousands of ARM scopes against the same AzureScopeReasoning payload
    (per role assignment / catalog resource / CloudSet subscription), and many of those scopes
    repeat. Bucket normalization runs once per payload instance and results are cached per
    normalized scope. The cache is keyed on the payload object's reference identity, so passing a
    different (e.g. re-read) payload starts a fresh cache - content equality is deliberately not
    inspected. Returned objects are shared between callers; treat them as read-only.
#>

function Resolve-EntraOpsAzureScopeReasoningTier {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ArmScopeId
        ,
        [Parameter(Mandatory = $false)]
        [psobject]$AzureScopeReasoning
    )

    if ($null -eq $AzureScopeReasoning) {
        return $null
    }

    $NormalizedScope = "$ArmScopeId".ToLower().TrimEnd('/')
    if ([string]::IsNullOrEmpty($NormalizedScope)) {
        return $null
    }

    # (A) Normalize the Tier0/Tier1 buckets once per payload instance instead of on every call.
    # A payload swap (reference change) drops the whole cache, so stale buckets or results can
    # never leak across payloads.
    if ($null -eq $script:AzureScopeReasoningTierCache -or
        -not [object]::ReferenceEquals($script:AzureScopeReasoningTierCache.Payload, $AzureScopeReasoning)) {
        $script:AzureScopeReasoningTierCache = @{
            Payload = $AzureScopeReasoning
            # "/" (directory root in Tier0Scope) must not force every ARM scope to Tier0
            Tier0   = @($AzureScopeReasoning.Tier0Scope | Where-Object { $_ -and $_ -ne "/" } | ForEach-Object { "$_".ToLower().TrimEnd('/') })
            Tier1   = @($AzureScopeReasoning.Tier1Scope | Where-Object { $_ -and $_ -ne "/" } | ForEach-Object { "$_".ToLower().TrimEnd('/') })
            Results = @{}
        }
    }
    $Cache = $script:AzureScopeReasoningTierCache

    # (B) Same scope, same payload -> same result object.
    if ($Cache.Results.ContainsKey($NormalizedScope)) {
        return $Cache.Results[$NormalizedScope]
    }

    $Result = $null
    $Tier0Match = Find-EntraOpsAzureScopeContainmentMatch -Scope $NormalizedScope -BucketedScopes $Cache.Tier0
    if ($null -ne $Tier0Match) {
        $Result = [PSCustomObject]@{
            AdminTierLevel     = "0"
            AdminTierLevelName = "ControlPlane"
            MatchedScope       = $Tier0Match
        }
    }

    if ($null -eq $Result) {
        $Tier1Match = Find-EntraOpsAzureScopeContainmentMatch -Scope $NormalizedScope -BucketedScopes $Cache.Tier1
        if ($null -ne $Tier1Match) {
            $Result = [PSCustomObject]@{
                AdminTierLevel     = "1"
                AdminTierLevelName = "ManagementPlane"
                MatchedScope       = $Tier1Match
            }
        }
    }

    if ($null -eq $Result) {
        $Result = [PSCustomObject]@{
            AdminTierLevel     = "2"
            AdminTierLevelName = "UserAccess"
            MatchedScope       = $null
        }
    }

    $Cache.Results[$NormalizedScope] = $Result
    return $Result
}
