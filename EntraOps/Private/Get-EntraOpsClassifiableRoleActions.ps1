function Get-EntraOpsClassifiableRoleActions {
    <#
    .SYNOPSIS
        Returns Entra ID role actions that may contribute to role classification.
    .DESCRIPTION
        Flattens allowedResourceActions from unifiedRolePermission objects while always excluding
        permission blocks whose condition is '$SubjectIsOwner'. Owner-scoped actions only apply to
        resources owned by the assignee and must not be treated as tenant-wide role capabilities.
    .PARAMETER RolePermissions
        The rolePermissions collection from a Microsoft Graph unifiedRoleDefinition.
    .OUTPUTS
        Role action strings from non-owner-scoped permission blocks.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$RolePermissions
    )

    foreach ($RolePermission in @($RolePermissions)) {
        if ($null -eq $RolePermission) { continue }

        $Condition = "$($RolePermission.condition)".Trim()
        if ($Condition -eq '$SubjectIsOwner') { continue }

        foreach ($Action in @($RolePermission.allowedResourceActions)) {
            if (-not [string]::IsNullOrEmpty($Action)) { $Action }
        }
    }
}
