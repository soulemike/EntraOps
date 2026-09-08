function Invoke-EntraOpsClassificationRoleOverwrite {
    <#
    .SYNOPSIS
        Applies role definition classification overwrites to classified RBAC assignments.
    .DESCRIPTION
        Shared helper that down- or upgrades the tier level of entire role definitions on
        classified RBAC assignments. Assignments are matched by RoleDefinitionId or
        RoleDefinitionName. A named Service replaces only the classification for that service
        (or adds it when absent). An empty or "*" Service replaces the assignment's entire
        classification with a single overwritten entry tagged with "RoleDefinitionOverwrites".

        Optionally, the overwrite can be limited to specific role assignment scopes by defining
        RoleAssignmentScopeName in the overwrite entry.
    .PARAMETER RbacClassifications
        Array of classified RBAC assignments (each with RoleDefinitionId and Classification property).
    .PARAMETER RoleDefinitionOverwrites
        Normalized role definition overwrite definitions from Import-EntraOpsClassificationOverwrites.
    .PARAMETER RoleSystem
        The RBAC system name used for TaggedByRoleSystem (e.g., "EntraID", "DeviceManagement").
    .OUTPUTS
        [array] RBAC assignments with overwritten classifications applied.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$RbacClassifications,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$RoleDefinitionOverwrites,

        [Parameter(Mandatory = $true)]
        [string]$RoleSystem
    )

    if ($null -eq $RoleDefinitionOverwrites -or $RoleDefinitionOverwrites.Count -eq 0) {
        return $RbacClassifications
    }

    # Build lookups for fast matching by RoleDefinitionId and RoleDefinitionName.
    # Multiple overwrite entries per role definition are legal (e.g. one entry per named Service),
    # so every key stores a list of overwrites — a single-entry lookup would silently drop all but
    # the last-loaded entry.
    $OverwritesById = @{}
    $OverwritesByName = @{}
    foreach ($Overwrite in $RoleDefinitionOverwrites) {
        if (-not [string]::IsNullOrEmpty($Overwrite.RoleDefinitionId)) {
            $IdKey = "$($Overwrite.RoleDefinitionId)".ToLowerInvariant()
            if (-not $OverwritesById.ContainsKey($IdKey)) {
                $OverwritesById[$IdKey] = [System.Collections.Generic.List[object]]::new()
            }
            $OverwritesById[$IdKey].Add($Overwrite)
        }
        if (-not [string]::IsNullOrEmpty($Overwrite.RoleDefinitionName)) {
            $NameKey = "$($Overwrite.RoleDefinitionName)".ToLowerInvariant()
            if (-not $OverwritesByName.ContainsKey($NameKey)) {
                $OverwritesByName[$NameKey] = [System.Collections.Generic.List[object]]::new()
            }
            $OverwritesByName[$NameKey].Add($Overwrite)
        }
    }

    $AppliedOverwrites = [System.Collections.Generic.List[object]]::new()

    foreach ($Assignment in $RbacClassifications) {
        $MatchedOverwrites = $null

        $AssignmentRoleId = $Assignment.PSObject.Properties['RoleDefinitionId']?.Value
        if (-not [string]::IsNullOrEmpty($AssignmentRoleId) -and $OverwritesById.ContainsKey("$AssignmentRoleId".ToLowerInvariant())) {
            $MatchedOverwrites = $OverwritesById["$AssignmentRoleId".ToLowerInvariant()]
        }

        if ($null -eq $MatchedOverwrites) {
            $AssignmentRoleName = $Assignment.PSObject.Properties['RoleDefinitionName']?.Value
            if ([string]::IsNullOrEmpty($AssignmentRoleName)) {
                $AssignmentRoleName = $Assignment.PSObject.Properties['RoleName']?.Value
            }
            if (-not [string]::IsNullOrEmpty($AssignmentRoleName) -and $OverwritesByName.ContainsKey("$AssignmentRoleName".ToLowerInvariant())) {
                $MatchedOverwrites = $OverwritesByName["$AssignmentRoleName".ToLowerInvariant()]
            }
        }

        if ($null -eq $MatchedOverwrites -or $MatchedOverwrites.Count -eq 0) { continue }

        # Optional scope filter: only overwrite assignments on matching scopes (checked per overwrite entry)
        $ApplicableOverwrites = [System.Collections.Generic.List[object]]::new()
        foreach ($Overwrite in $MatchedOverwrites) {
            if ($null -ne $Overwrite.RoleAssignmentScopeName -and $Overwrite.RoleAssignmentScopeName.Count -gt 0) {
                $AssignmentScope = $Assignment.PSObject.Properties['RoleAssignmentScopeId']?.Value
                $ScopeMatch = $false
                foreach ($OverwriteScope in $Overwrite.RoleAssignmentScopeName) {
                    if ("$AssignmentScope" -like $OverwriteScope) {
                        $ScopeMatch = $true
                        break
                    }
                }
                if (-not $ScopeMatch) { continue }
            }
            $ApplicableOverwrites.Add($Overwrite)
        }

        if ($ApplicableOverwrites.Count -eq 0) { continue }

        # Precedence: named-Service overwrites are applied first (each replaces or adds only the
        # classification entry of its own service). A replaces-all overwrite (empty or '*' Service)
        # is applied last, so it wins and replaces the assignment's entire classification — including
        # any named-Service overwrites applied just before — with a single overwritten entry.
        $OrderedOverwrites = @($ApplicableOverwrites | Where-Object { -not ([string]::IsNullOrEmpty($_.Service) -or $_.Service -eq '*') })
        $OrderedOverwrites += @($ApplicableOverwrites | Where-Object { [string]::IsNullOrEmpty($_.Service) -or $_.Service -eq '*' })

        foreach ($Overwrite in $OrderedOverwrites) {
            $ReplacesAllServices = [string]::IsNullOrEmpty($Overwrite.Service) -or $Overwrite.Service -eq '*'

            # Keep original service as fallback for a whole-role overwrite without a named service.
            $Service = $Overwrite.Service
            if ($ReplacesAllServices) {
                $ExistingService = @($Assignment.Classification | Where-Object { $null -ne $_ } | Select-Object -ExpandProperty Service -ErrorAction SilentlyContinue | Select-Object -First 1)
                $Service = if ($ExistingService.Count -gt 0) { $ExistingService[0] } else { "Custom Classification" }
            }

            $MatchedActions = @()
            if (-not $ReplacesAllServices) {
                $MatchedActions = @($Assignment.Classification |
                    Where-Object { $null -ne $_ -and $_.Service -ieq $Service } |
                    ForEach-Object { @($_.MatchedActions) } |
                    Where-Object { -not [string]::IsNullOrEmpty($_) } |
                    Select-Object -Unique)
            }

            $OverwriteClassification = @([PSCustomObject]@{
                    'AdminTierLevel'             = $Overwrite.EAMTierLevelTagValue
                    'AdminTierLevelName'         = $Overwrite.EAMTierLevelName
                    'Service'                    = $Service
                    'MatchedActions'             = if ($MatchedActions.Count -gt 0) { , @($MatchedActions) } else { $null }
                    'ScopedObjects'              = $null
                    'TaggedBy'                   = "RoleDefinitionOverwrites"
                    'TaggedByObjectIds'          = $null
                    'TaggedByObjectDisplayNames' = $null
                    'TaggedByRoleSystem'         = $RoleSystem
                })

            if ($ReplacesAllServices) {
                $UpdatedClassification = $OverwriteClassification
            } else {
                $UpdatedClassification = @($Assignment.Classification | Where-Object { $null -ne $_ -and $_.Service -ine $Service }) + $OverwriteClassification
            }

            $Assignment | Add-Member -NotePropertyName "Classification" -NotePropertyValue $UpdatedClassification -Force
            $AppliedOverwrites.Add([PSCustomObject]@{
                    Tier       = $Overwrite.EAMTierLevelName
                    SourceFile = $Overwrite.SourceFile
                }) | Out-Null
        }
    }

    if ($AppliedOverwrites.Count -gt 0) {
        Write-Host "  Role definition overwrites applied:" -ForegroundColor Yellow
        $AppliedOverwrites | Group-Object Tier, SourceFile | Sort-Object Name | ForEach-Object {
            $Example = $_.Group[0]
            Write-Host "    $($Example.Tier): $($_.Count) role definition assignment overwrite(s) from $($Example.SourceFile)" -ForegroundColor Yellow
        }
    }

    return $RbacClassifications
}