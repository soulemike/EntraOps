function Import-EntraOpsClassificationOverwrites {
    <#
    .SYNOPSIS
        Loads classification overwrite definitions from the tenant-specific classification folder and Templates.
    .DESCRIPTION
        Shared helper that loads the separated overwrite files and returns normalized overwrite
        definitions for a specific RBAC system:

        - Classification_RoleActionOverwrites.json:     Down- or upgrade the tier level of individual
                                                        role definition actions (e.g.,
                                                        "microsoft.directory/bitlockerKeys/key/read" on scope "/*").
                                                        An optional ActionType ("Action" or "DataAction", defaults
                                                        to "Action") declares which plane the actions belong to for
                                                        RBAC systems that distinguish control/management plane
                                                        Actions from data plane DataActions (currently Azure).
                                                        This file is ONLY read from the tenant-specific folder
                                                        ($FolderClassification/$TenantNameContext) alongside the
                                                        other customized classification files. A file in the
                                                        Templates folder is intentionally ignored.
                                                        Role action overwrites are applied at classification file
                                                        generation time by Update-EntraOpsClassificationControlPlaneScope
                                                        (via Invoke-EntraOpsClassificationActionOverwrite) and are
                                                        baked into the tenant-specific Classification_*.json files.
                                                        The Get-EntraOpsPrivilegedEAM* cmdlets do not apply them at runtime.
        - Classification_RoleDefinitionOverwrites.json: Down- or upgrade the tier level of a role
                                definition, identified by RoleDefinitionId and/or
                                RoleDefinitionName (replaces previously hard-coded
                                handling such as ControlPlaneRolesWithoutRoleActions).
                                A named Service replaces or adds only that service;
                                an empty or "*" Service replaces all classifications.
                                                        A tenant-specific file in $FolderClassification/$TenantNameContext
                                                        is preferred; otherwise the file in
                                                        $FolderClassification/Templates is used as fallback.
        - Classification_ApiPermissionOverwrites.json:  Down- or upgrade the tier level of an individual API
                                                        permission (application or delegated), identified by
                                                        PermissionValue and, optionally, TargetAppId/PermissionType.
                                                        Schema is aligned with Classification_ApiPermissions.json
                                                        entries (PermissionValue/PermissionType/TargetAppId/Category)
                                                        instead of the RoleDefinitionActions/scope-pattern shape used
                                                        by Classification_RoleActionOverwrites.json. This file is ONLY
                                                        read from the tenant-specific folder (no Templates fallback),
                                                        same as Classification_RoleActionOverwrites.json. Only
                                                        applicable to RbacSystem "ResourceApps" and applied at
                                                        classification file generation time by
                                                        Update-EntraOpsClassificationControlPlaneScope (baked into the
                                                        tenant-specific Classification_ApiPermissions.json via
                                                        Invoke-EntraOpsClassificationActionOverwrite, reusing the same
                                                        nested-schema mechanism as the other RBAC systems).

        All files contain a JSON array of overwrite entries. For role definition overwrites, Service scopes
        the overwrite to that classification service; use an empty or "*" Service to replace the entire role.
        For other overwrite types, Service (Category for API permission overwrites) is used as the service
        of the overwritten entry.

        RbacSystem "ResourceApps" (API permissions) is no longer supported in
        Classification_RoleActionOverwrites.json - such entries are skipped with a warning. Use
        Classification_ApiPermissionOverwrites.json instead.

        Every overwrite entry must contain a Justification to document why the classification
        has been changed. Entries without a Justification are skipped with a warning.
    .PARAMETER RbacSystem
        RBAC system to filter overwrite entries for (e.g., "EntraID", "DeviceManagement", "Defender", "IdentityGovernance", "ResourceApps").
    .PARAMETER FolderClassification
        Base folder for classification files. Defaults to $DefaultFolderClassification.
    .OUTPUTS
        [PSCustomObject] with three array properties: RoleActionOverwrites, RoleDefinitionOverwrites and ApiPermissionOverwrites.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RbacSystem,

        [Parameter(Mandatory = $false)]
        [string]$FolderClassification = $DefaultFolderClassification
    )

    $RoleActionOverwrites = [System.Collections.Generic.List[object]]::new()
    $RoleDefinitionOverwrites = [System.Collections.Generic.List[object]]::new()
    $ApiPermissionOverwrites = [System.Collections.Generic.List[object]]::new()

    # Translation between the PermissionType values used on Classification_ApiPermissionOverwrites.json entries
    # (matching Classification_ApiPermissions.json / AppRoleAssignment.RoleType semantics: "Application"/"Delegated")
    # and the ResourceScope values used internally by Invoke-EntraOpsClassificationActionOverwrite ("Application"/"Delegation").
    $PermissionTypeToResourceScope = @{
        'Application' = 'Application'
        'Delegated'   = 'Delegation'
    }

    # Mapping to derive tag value from tier level name if not explicitly defined
    $TierLevelTagValueMap = @{
        'ControlPlane'    = '0'
        'ManagementPlane' = '1'
        'WorkloadPlane'   = '1'   # Tier1 sub-plane (cf. Tier1-WorkloadPlane groups / ObjectAdminTierLevel "1" in PrivilegedEAM exports)
        'UserAccess'      = '2'
    }

    $OverwriteFileMap = [System.Collections.Generic.List[object]]::new()

    # Tenant-specific classification folder (only available after Connect-EntraOps has set $TenantNameContext)
    $TenantFolder = if (-not [string]::IsNullOrEmpty($TenantNameContext)) {
        Join-Path -Path $FolderClassification -ChildPath $TenantNameContext
    } else { $null }

    # Role action overwrites: ONLY read from the tenant-specific folder, no Templates fallback
    if ($null -ne $TenantFolder) {
        $RoleActionFilePath = Join-Path -Path $TenantFolder -ChildPath 'Classification_RoleActionOverwrites.json'
        if (Test-Path -Path $RoleActionFilePath) {
            Write-Verbose "Using tenant-specific role action overwrites file: $RoleActionFilePath"
            $OverwriteFileMap.Add([PSCustomObject]@{ Type = 'RoleAction'; Path = $RoleActionFilePath })
        } else {
            Write-Verbose "No tenant-specific role action overwrites file found at $RoleActionFilePath"
        }

        # API permission overwrites (ResourceApps only): ONLY read from the tenant-specific folder, no Templates
        # fallback - same convention as role action overwrites.
        $ApiPermissionFilePath = Join-Path -Path $TenantFolder -ChildPath 'Classification_ApiPermissionOverwrites.json'
        if (Test-Path -Path $ApiPermissionFilePath) {
            Write-Verbose "Using tenant-specific API permission overwrites file: $ApiPermissionFilePath"
            $OverwriteFileMap.Add([PSCustomObject]@{ Type = 'ApiPermission'; Path = $ApiPermissionFilePath })
        } else {
            Write-Verbose "No tenant-specific API permission overwrites file found at $ApiPermissionFilePath"
        }
    } else {
        Write-Verbose "No tenant context available, skipping tenant-specific role action and API permission overwrites"
    }

    # Role definition overwrites: tenant-specific file preferred, Templates as fallback
    $RoleDefinitionFilePath = $null
    if ($null -ne $TenantFolder) {
        $TenantRoleDefinitionFilePath = Join-Path -Path $TenantFolder -ChildPath 'Classification_RoleDefinitionOverwrites.json'
        if (Test-Path -Path $TenantRoleDefinitionFilePath) {
            Write-Verbose "Using tenant-specific role definition overwrites file: $TenantRoleDefinitionFilePath"
            $RoleDefinitionFilePath = $TenantRoleDefinitionFilePath
        }
    }
    if ($null -eq $RoleDefinitionFilePath) {
        $TemplateRoleDefinitionFilePath = Join-Path -Path $FolderClassification -ChildPath 'Templates/Classification_RoleDefinitionOverwrites.json'
        if (Test-Path -Path $TemplateRoleDefinitionFilePath) {
            Write-Verbose "Using template role definition overwrites file: $TemplateRoleDefinitionFilePath"
            $RoleDefinitionFilePath = $TemplateRoleDefinitionFilePath
        } else {
            Write-Verbose "No role definition overwrites file found in tenant-specific folder or Templates"
        }
    }
    if ($null -ne $RoleDefinitionFilePath) {
        $OverwriteFileMap.Add([PSCustomObject]@{ Type = 'RoleDefinition'; Path = $RoleDefinitionFilePath })
    }

    if ($OverwriteFileMap.Count -eq 0) {
        return [PSCustomObject]@{
            RoleActionOverwrites     = @()
            RoleDefinitionOverwrites = @()
            ApiPermissionOverwrites  = @()
        }
    }

    foreach ($OverwriteFileEntry in $OverwriteFileMap) {
        if (-not (Test-Path -Path $OverwriteFileEntry.Path)) {
            Write-Verbose "Classification overwrite file not found: $($OverwriteFileEntry.Path)"
            continue
        }
        $OverwriteFile = Get-Item -Path $OverwriteFileEntry.Path
        try {
            $OverwriteJson = @(Get-Content -Path $OverwriteFile.FullName -Raw | ConvertFrom-Json -Depth 10)
        } catch {
            Write-Warning "Failed to parse classification overwrite file $($OverwriteFile.FullName): $_"
            continue
        }

        # Resolve tier level for an overwrite entry, returns $null if invalid
        $ResolveTierLevel = {
            param($Entry, $EntryDescription)

            if ([string]::IsNullOrEmpty($Entry.EAMTierLevelName)) {
                Write-Warning "Skipping classification overwrite ($EntryDescription) in $($OverwriteFile.Name): EAMTierLevelName is missing."
                return $null
            }

            $TagValue = $Entry.EAMTierLevelTagValue
            if ([string]::IsNullOrEmpty($TagValue)) {
                if ($TierLevelTagValueMap.ContainsKey($Entry.EAMTierLevelName)) {
                    $TagValue = $TierLevelTagValueMap[$Entry.EAMTierLevelName]
                } else {
                    Write-Warning "Skipping classification overwrite ($EntryDescription) in $($OverwriteFile.Name): Unknown EAMTierLevelName '$($Entry.EAMTierLevelName)' and no EAMTierLevelTagValue defined."
                    return $null
                }
            }
            return "$TagValue"
        }

        #region Role action overwrites
        $RoleActionEntries = if ($OverwriteFileEntry.Type -eq 'RoleAction') { @($OverwriteJson) } else { @() }
        foreach ($Entry in $RoleActionEntries) {
            if ($null -eq $Entry) { continue }
            if ("$($Entry.RbacSystem)" -ne $RbacSystem) { continue }

            # RbacSystem "ResourceApps" (API permissions) is no longer supported here - use
            # Classification_ApiPermissionOverwrites.json instead (schema aligned with Classification_ApiPermissions.json).
            if ($Entry.RbacSystem -eq 'ResourceApps') {
                Write-Warning "Skipping ResourceApps entry in $($OverwriteFile.Name): API permission overwrites are no longer supported in Classification_RoleActionOverwrites.json. Move it to Classification_ApiPermissionOverwrites.json."
                continue
            }

            $Actions = @($Entry.RoleDefinitionActions | Where-Object { -not [string]::IsNullOrEmpty($_) })
            if ($Actions.Count -eq 0) {
                Write-Warning "Skipping role action classification overwrite in $($OverwriteFile.Name): RoleDefinitionActions is missing or empty."
                continue
            }

            if ([string]::IsNullOrEmpty($Entry.Justification)) {
                Write-Warning "Skipping role action classification overwrite for '$($Actions -join ', ')' in $($OverwriteFile.Name): Justification is required to document the classification change."
                continue
            }

            $TagValue = & $ResolveTierLevel $Entry "role actions: $($Actions -join ', ')"
            if ($null -eq $TagValue) { continue }

            $Scopes = @($Entry.RoleAssignmentScopeName | Where-Object { -not [string]::IsNullOrEmpty($_) })
            if ($Scopes.Count -eq 0) { $Scopes = @("/*") }

            # Plane of the overwritten actions (Action = control/management plane, DataAction = data plane).
            # Defaults to "Action" when omitted, matching the same default used on TierLevelDefinition entries.
            $ActionType = if ("$($Entry.ActionType)" -eq 'DataAction') { 'DataAction' } else { 'Action' }

            $RoleActionOverwrites.Add([PSCustomObject]@{
                    'RbacSystem'              = $RbacSystem
                    'RoleDefinitionActions'   = $Actions
                    'ActionType'              = $ActionType
                    'RoleAssignmentScopeName' = $Scopes
                    'ResourceAppId'           = $null
                    'ResourceScope'           = $null
                    'EAMTierLevelName'        = $Entry.EAMTierLevelName
                    'EAMTierLevelTagValue'    = $TagValue
                    'Service'                 = $Entry.Service
                    'Justification'           = $Entry.Justification
                    'SourceFile'              = $OverwriteFile.Name
                }) | Out-Null
        }
        #endregion

        #region API permission overwrites (ResourceApps only)
        $ApiPermissionEntries = if ($OverwriteFileEntry.Type -eq 'ApiPermission') { @($OverwriteJson) } else { @() }
        foreach ($Entry in $ApiPermissionEntries) {
            if ($null -eq $Entry) { continue }
            if ("$RbacSystem" -ne 'ResourceApps') { continue }

            $PermissionValue = "$($Entry.PermissionValue)"
            if ([string]::IsNullOrEmpty($PermissionValue)) {
                Write-Warning "Skipping API permission classification overwrite in $($OverwriteFile.Name): PermissionValue is missing."
                continue
            }

            if ([string]::IsNullOrEmpty($Entry.Justification)) {
                Write-Warning "Skipping API permission classification overwrite for '$PermissionValue' in $($OverwriteFile.Name): Justification is required to document the classification change."
                continue
            }

            $TagValue = & $ResolveTierLevel $Entry "API permission: $PermissionValue"
            if ($null -eq $TagValue) { continue }

            $PermissionType = "$($Entry.PermissionType)"
            $ResourceScope = if (-not [string]::IsNullOrEmpty($PermissionType) -and $PermissionType -ne 'All' -and $PermissionTypeToResourceScope.ContainsKey($PermissionType)) {
                $PermissionTypeToResourceScope[$PermissionType]
            } elseif (-not [string]::IsNullOrEmpty($PermissionType) -and $PermissionType -ne 'All') {
                Write-Warning "API permission classification overwrite for '$PermissionValue' in $($OverwriteFile.Name): Unknown PermissionType '$PermissionType', expected 'Application', 'Delegated' or 'All'. Treating as 'All'."
                $null
            } else {
                $null
            }

            $ApiPermissionOverwrites.Add([PSCustomObject]@{
                    'RbacSystem'              = 'ResourceApps'
                    'RoleDefinitionActions'   = @($PermissionValue)
                    'RoleAssignmentScopeName' = @("/")
                    'ResourceAppId'           = if (-not [string]::IsNullOrEmpty($Entry.TargetAppId)) { "$($Entry.TargetAppId)" } else { $null }
                    'ResourceScope'           = $ResourceScope
                    'EAMTierLevelName'        = $Entry.EAMTierLevelName
                    'EAMTierLevelTagValue'    = $TagValue
                    'Service'                 = $Entry.Category
                    'Justification'           = $Entry.Justification
                    'SourceFile'              = $OverwriteFile.Name
                }) | Out-Null
        }
        #endregion

        #region Role definition overwrites
        $RoleDefinitionEntries = if ($OverwriteFileEntry.Type -eq 'RoleDefinition') { @($OverwriteJson) } else { @() }
        foreach ($Entry in $RoleDefinitionEntries) {
            if ($null -eq $Entry) { continue }
            if ("$($Entry.RbacSystem)" -ne $RbacSystem) { continue }

            if ([string]::IsNullOrEmpty($Entry.RoleDefinitionId) -and [string]::IsNullOrEmpty($Entry.RoleDefinitionName)) {
                Write-Warning "Skipping role definition classification overwrite in $($OverwriteFile.Name): RoleDefinitionId or RoleDefinitionName is required."
                continue
            }

            $RoleIdentifier = if (-not [string]::IsNullOrEmpty($Entry.RoleDefinitionName)) { $Entry.RoleDefinitionName } else { $Entry.RoleDefinitionId }
            if ([string]::IsNullOrEmpty($Entry.Justification)) {
                Write-Warning "Skipping role definition classification overwrite for '$RoleIdentifier' in $($OverwriteFile.Name): Justification is required to document the classification change."
                continue
            }

            $TagValue = & $ResolveTierLevel $Entry "role definition: $RoleIdentifier"
            if ($null -eq $TagValue) { continue }

            $Scopes = @($Entry.RoleAssignmentScopeName | Where-Object { -not [string]::IsNullOrEmpty($_) })

            $RoleDefinitionOverwrites.Add([PSCustomObject]@{
                    'RbacSystem'              = $RbacSystem
                    'RoleDefinitionId'        = $Entry.RoleDefinitionId
                    'RoleDefinitionName'      = $Entry.RoleDefinitionName
                    'RoleAssignmentScopeName' = if ($Scopes.Count -gt 0) { $Scopes } else { $null }
                    'EAMTierLevelName'        = $Entry.EAMTierLevelName
                    'EAMTierLevelTagValue'    = $TagValue
                    'Service'                 = $Entry.Service
                    'Justification'           = $Entry.Justification
                    'SourceFile'              = $OverwriteFile.Name
                }) | Out-Null
        }
        #endregion
    }

    if ($RoleActionOverwrites.Count -gt 0 -or $RoleDefinitionOverwrites.Count -gt 0 -or $ApiPermissionOverwrites.Count -gt 0) {
        Write-Verbose "Loaded $($RoleActionOverwrites.Count) role action, $($RoleDefinitionOverwrites.Count) role definition and $($ApiPermissionOverwrites.Count) API permission classification overwrite(s) for $RbacSystem from $(@($OverwriteFileMap.Path) -join ', ')"
    }

    return [PSCustomObject]@{
        RoleActionOverwrites     = @($RoleActionOverwrites)
        RoleDefinitionOverwrites = @($RoleDefinitionOverwrites)
        ApiPermissionOverwrites  = @($ApiPermissionOverwrites)
    }
}
