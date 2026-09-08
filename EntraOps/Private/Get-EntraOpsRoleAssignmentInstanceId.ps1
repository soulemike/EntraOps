function Get-EntraOpsRoleAssignmentInstanceId {
    <#
    .SYNOPSIS
        Returns a stable identifier for one normalized Privileged EAM assignment row.
    .DESCRIPTION
        RoleAssignmentId is the upstream Microsoft Graph or ARM assignment/grant identifier and
        is intentionally preserved. Some sources expand a single upstream assignment into several
        rows (for example an OAuth2 grant with several delegated scopes), so it is not unique in
        the normalized EAM schema. This helper derives a deterministic row identity from the
        immutable assignment context used to distinguish those expansions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RoleSystem,

        [Parameter(Mandatory = $true)]
        [PSObject]$RoleAssignment
    )

    # ObjectId is intentionally excluded: a shared (e.g. group-transitive) assignment must keep
    # one identity across all principals it reaches, matching how RoleAssignmentId behaved.
    $parts = @(
        $RoleSystem,
        $RoleAssignment.RoleAssignmentId,
        $RoleAssignment.RoleDefinitionId,
        $RoleAssignment.RoleDefinitionName,
        $RoleAssignment.RoleAssignmentScopeId,
        $RoleAssignment.RoleAssignmentSubType
    ) | ForEach-Object {
        if ($null -eq $_) { '' } else { "$_".Trim().ToLowerInvariant() }
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($parts -join [char]0x1F)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return 'EO_RA_' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
}