function Test-EntraOpsClassificationActionMatch {
    <#
    .SYNOPSIS
        Tests whether a role action matches a classification action definition (wildcard-aware).
    .DESCRIPTION
        Shared helper for the Get-EntraOpsPrivilegedEAM* matchers to compare a role definition
        action from Microsoft Graph against classification actions (RoleDefinitionActions or
        ExcludedRoleDefinitionActions). Exact, case-insensitive comparison is the fast path;
        when a classification action contains a wildcard character (*, ?, [ ]) it is matched
        with -like instead, mirroring the Azure matcher's classification-side wildcard semantics.
        Matching is one-directional (classification pattern against literal role action) because
        Graph role actions - unlike Azure RBAC actions - never contain wildcards themselves.
    .PARAMETER ClassificationActions
        One or more classification action strings (scalar or array; $null/empty entries are ignored).
    .PARAMETER Action
        The role definition action to test.
    .OUTPUTS
        [bool] $true if the action matches any classification action, otherwise $false.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$ClassificationActions,

        # AllowEmptyString: role definitions can carry empty/null action entries (malformed custom
        # roles, stale caches). The replaced inline -Contains comparison treated those as simply
        # non-matching - a mandatory-string binding error here would terminate the whole EAM export.
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Action
    )

    if ([string]::IsNullOrEmpty($Action)) { return $false }

    foreach ($ClassAction in @($ClassificationActions)) {
        if ([string]::IsNullOrEmpty($ClassAction)) { continue }
        if ($ClassAction -eq $Action) { return $true }                                       # fast path (exact, case-insensitive)
        if ($ClassAction -match '[*?\[\]]' -and $Action -like $ClassAction) { return $true } # wildcard classification action
    }
    return $false
}
