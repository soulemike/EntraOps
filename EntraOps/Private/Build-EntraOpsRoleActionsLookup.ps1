function Build-EntraOpsRoleActionsLookup {
    <#
    .SYNOPSIS
        Builds a lookup hashtable for Entra ID role definitions keyed by id, templateId and unambiguous displayName.
    .DESCRIPTION
        Helper for Get-EntraOpsPrivilegedEAMEntraId to resolve role definitions to their actions.
        Role assignments are normalized to the role's templateId (see Get-EntraOpsPrivilegedEntraIdRoles),
        which equals id for built-in roles but can differ for custom roles created with an explicit
        templateId. Every available identifier is therefore indexed independently; an unambiguous
        displayName remains as a last-resort fallback for cached or sample data that predates the
        templateId selection.
    .PARAMETER RoleDefinitions
        Role definition objects (from Graph, cache or sample data) with Id, TemplateId, DisplayName
        and RolePermissions properties.
    .OUTPUTS
        [hashtable] Role definition lookup keyed by id, templateId and unambiguous displayName.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$RoleDefinitions
    )

    $RoleActionsLookup = @{}
    $DisplayNameCounts = @{}

    foreach ($RoleAction in @($RoleDefinitions)) {
        if ($null -eq $RoleAction) { continue }
        if (-not [string]::IsNullOrEmpty($RoleAction.Id)) {
            $RoleActionsLookup["$($RoleAction.Id)"] = $RoleAction
        }
        if (-not [string]::IsNullOrEmpty($RoleAction.TemplateId)) {
            $RoleActionsLookup["$($RoleAction.TemplateId)"] = $RoleAction
        }
        if (-not [string]::IsNullOrEmpty($RoleAction.DisplayName)) {
            $DisplayName = "$($RoleAction.DisplayName)"
            $DisplayNameCounts[$DisplayName] = 1 + [int]$DisplayNameCounts[$DisplayName]
        }
    }

    foreach ($RoleAction in @($RoleDefinitions)) {
        if ($null -eq $RoleAction -or [string]::IsNullOrEmpty($RoleAction.DisplayName)) { continue }

        $DisplayName = "$($RoleAction.DisplayName)"
        if ($DisplayNameCounts[$DisplayName] -eq 1 -and -not $RoleActionsLookup.ContainsKey($DisplayName)) {
            $RoleActionsLookup[$DisplayName] = $RoleAction
        }
    }
    return $RoleActionsLookup
}
