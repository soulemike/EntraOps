function Build-EntraOpsClassificationActionMatcher {
    <#
    .SYNOPSIS
        Precomputes a fast action matcher for one classification entry.
    .DESCRIPTION
        Companion to Test-EntraOpsClassificationActionMatch (which remains the reference
        implementation): the classification action arrays are split ONCE into a case-insensitive
        HashSet of exact actions plus the (usually tiny) list of wildcard patterns, so hot loops
        can test each role action with a set lookup and an inline -like fallback instead of two
        helper invocations (param binding + array coercion + a regex probe) per
        action x classification pair.

        Matching semantics are identical to Test-EntraOpsClassificationActionMatch:
        null/empty classification entries are ignored, comparison is case-insensitive, and only
        classification-side wildcards exist. An empty role action never matches (callers skip it).

        Intentionally plain data (HashSet + string lists on a PSCustomObject) - no
        Add-Member ScriptMethod / [scriptblock]::Create, keeping the module compatible with the
        Constrained Language Mode goals tracked in PawCompatible.md.
    .PARAMETER RoleDefinitionActions
        Classification actions that qualify a role action as matched.
    .PARAMETER ExcludedRoleDefinitionActions
        Classification actions that disqualify an otherwise matched role action.
    .OUTPUTS
        [pscustomobject] with AllowedExact/AllowedWildcards/ExcludedExact/ExcludedWildcards.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$RoleDefinitionActions,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$ExcludedRoleDefinitionActions
    )

    $AllowedExact = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $AllowedWildcards = [System.Collections.Generic.List[string]]::new()
    foreach ($ClassAction in @($RoleDefinitionActions)) {
        if ([string]::IsNullOrEmpty($ClassAction)) { continue }
        if ("$ClassAction" -match '[*?\[\]]') { $AllowedWildcards.Add("$ClassAction") } else { [void]$AllowedExact.Add("$ClassAction") }
    }

    $ExcludedExact = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ExcludedWildcards = [System.Collections.Generic.List[string]]::new()
    foreach ($ClassAction in @($ExcludedRoleDefinitionActions)) {
        if ([string]::IsNullOrEmpty($ClassAction)) { continue }
        if ("$ClassAction" -match '[*?\[\]]') { $ExcludedWildcards.Add("$ClassAction") } else { [void]$ExcludedExact.Add("$ClassAction") }
    }

    [pscustomobject]@{
        AllowedExact      = $AllowedExact
        AllowedWildcards  = $AllowedWildcards
        ExcludedExact     = $ExcludedExact
        ExcludedWildcards = $ExcludedWildcards
    }
}
