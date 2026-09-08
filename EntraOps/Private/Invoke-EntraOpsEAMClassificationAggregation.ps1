<#
.SYNOPSIS
    Aggregates classifications per unique object and builds standardized EAM output objects.

.DESCRIPTION
    Shared helper that replaces the duplicated classification aggregation logic found in every
    EAM cmdlet's final stage. Handles both parallel and sequential processing paths, builds
    unique classification sets per object, applies "Unclassified" fallback, and constructs
    the standardized output PSCustomObject via New-EntraOpsEAMOutputObject.

    Principals whose object details could not be resolved ($null entry in ObjectDetailsCache) are
    NOT dropped: they are emitted fail-closed as ControlPlane placeholders with a Classification
    marker entry (TaggedBy = "UnresolvedObject"), so downstream Administrative Unit / Conditional
    Access group reconciliation never removes a potentially privileged principal from its
    protection group just because a Graph lookup failed or was throttled.

    This function eliminates ~150 lines of duplicated code per EAM cmdlet.

.PARAMETER UniqueObjects
    Array of unique objects with ObjectId and ObjectType properties.

.PARAMETER ObjectDetailsCache
    Hashtable mapping ObjectId → resolved object details from Get-EntraOpsPrivilegedEntraObject.

.PARAMETER RbacClassificationsByObject
    Hashtable mapping ObjectId → classified role assignments (from Group-Object ObjectId -AsHashTable).

.PARAMETER RoleSystem
    The RBAC system name (e.g., "EntraID", "Defender", "DeviceManagement", "IdentityGovernance", "ResourceApps").

.PARAMETER EnableParallelProcessing
    Enable parallel processing. Default is $true.

.PARAMETER ParallelThrottleLimit
    Maximum number of parallel threads. Default is 10.

.PARAMETER WarningMessages
    Reference to the List[psobject] for collecting warnings.

.OUTPUTS
    Array of standardized EAM output objects.
#>

function Invoke-EntraOpsEAMClassificationAggregation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Array]$UniqueObjects,

        [Parameter(Mandatory = $true)]
        [hashtable]$ObjectDetailsCache,

        [Parameter(Mandatory = $true)]
        [hashtable]$RbacClassificationsByObject,

        [Parameter(Mandatory = $true)]
        [string]$RoleSystem,

        [Parameter(Mandatory = $false)]
        [bool]$EnableParallelProcessing = $true,

        [Parameter(Mandatory = $false)]
        [int]$ParallelThrottleLimit = 10,

        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.List[psobject]]$WarningMessages
    )

    # Determine if parallel processing is viable (PowerShell 7+ guaranteed by module prerequisite)
    $HasSufficientObjects = $UniqueObjects.Count -ge 50
    $UseParallelForClassification = $EnableParallelProcessing -and $HasSufficientObjects

    # Fail-closed placeholder SCHEMA, defined once and shared by the parallel and sequential paths
    # so the two can never drift apart. Shared as plain data (read-only template + marker) rather
    # than a scriptblock: invoking a $using: scriptblock concurrently across parallel runspaces is
    # not thread-safe, and [scriptblock]::Create is avoided for the Constrained Language Mode goals
    # tracked in PawCompatible.md. Each path clones the template and fills in the three
    # object-specific fields (ObjectTenantId, ObjectType, ObjectDisplayName).
    $UnresolvedObjectDetailsTemplate = [ordered]@{
        'ObjectTenantId'                = $null
        'ObjectType'                    = 'unresolved'
        'ObjectSubType'                 = 'Unresolved'
        'ObjectDisplayName'             = $null
        'ObjectSignInName'              = $null
        'AdminTierLevel'                = '0'
        'AdminTierLevelName'            = 'ControlPlane'
        'OnPremSynchronized'            = $null
        'AssignedAdministrativeUnits'   = $null
        'RestrictedManagementByRAG'     = $null
        'RestrictedManagementByAadRole' = $null
        'RestrictedManagementByRMAU'    = $null
        'Sponsors'                      = $null
        'Owners'                        = $null
        'OwnedObjects'                  = $null
        'OwnedDevices'                  = $null
        'IdentityParent'                = $null
        'AssociatedWorkAccount'         = $null
        'AssociatedPawDevice'           = $null
    }
    $UnresolvedMarkerClassification = [PSCustomObject]@{
        'AdminTierLevel'     = "0"
        'AdminTierLevelName' = "ControlPlane"
        'Service'            = "Unresolved"
        'TaggedBy'           = "UnresolvedObject"
    }

    if ($UseParallelForClassification) {
        $SyncObjectDetailsCache = [System.Collections.Hashtable]::Synchronized($ObjectDetailsCache)
        $SyncRbacByObject = [System.Collections.Hashtable]::Synchronized($RbacClassificationsByObject)

        $ClassificationThrottleLimit = [Math]::Min($ParallelThrottleLimit * 2, 100)
        Write-Host "Using parallel classification processing with $ClassificationThrottleLimit threads for $($UniqueObjects.Count) objects..." -ForegroundColor Yellow

        $ClassifiedObjects = $UniqueObjects | ForEach-Object -ThrottleLimit $ClassificationThrottleLimit -Parallel {
            $obj = $_
            $ObjectId = $obj.ObjectId

            if ($null -ne $ObjectId) {
                $SharedDetailsCache = $using:SyncObjectDetailsCache
                $SharedRbacByObject = $using:SyncRbacByObject
                $LocalRoleSystem = $using:RoleSystem

                $ObjectDetails = $SharedDetailsCache[$ObjectId]

                # Fail-closed: never drop a principal whose object details could not be resolved
                # (failed/throttled Graph call, $null cache entry). A vanished ControlPlane principal
                # would otherwise be removed from its protection group by the Administrative Unit /
                # Conditional Access group reconciliation. Emit a placeholder pinned to ControlPlane
                # instead, built inline from the identity fields known from the assignment data
                # (cannot call module functions from parallel runspace).
                $IsUnresolvedObject = ($null -eq $ObjectDetails)
                if ($IsUnresolvedObject) {
                    # Shared schema template (see its definition in function scope) - clone and
                    # fill the object-specific fields.
                    $DetailsTemplate = $using:UnresolvedObjectDetailsTemplate
                    $Details = [ordered]@{}
                    foreach ($TemplateKey in $DetailsTemplate.Keys) { $Details[$TemplateKey] = $DetailsTemplate[$TemplateKey] }
                    $Details['ObjectTenantId'] = $obj.ObjectTenantId
                    $KnownObjectType = "$($obj.ObjectType)"
                    if (-not [string]::IsNullOrWhiteSpace($KnownObjectType)) { $Details['ObjectType'] = $KnownObjectType }
                    $Details['ObjectDisplayName'] = $ObjectId
                    $ObjectDetails = [PSCustomObject]$Details
                }

                $RbacClassifiedAssignments = $SharedRbacByObject[$ObjectId]

                # Aggregate unique classifications using hashtable
                $UniqueClassificationsHash = @{}
                foreach ($Assignment in $RbacClassifiedAssignments) {
                    if ($null -ne $Assignment.Classification) {
                        foreach ($ClassItem in $Assignment.Classification) {
                            $key = "$($ClassItem.AdminTierLevel)|$($ClassItem.AdminTierLevelName)|$($ClassItem.Service)"
                            if (-not $UniqueClassificationsHash.ContainsKey($key)) {
                                $UniqueClassificationsHash[$key] = $ClassItem
                            }
                        }
                    }
                }

                $Classification = @($UniqueClassificationsHash.Values | Select-Object -Unique -ExcludeProperty TaggedBy, TaggedByObjectIds, TaggedByObjectDisplayNames, TaggedByRoleSystem | Sort-Object AdminTierLevel, AdminTierLevelName, Service)
                if ($Classification.Count -eq 0) {
                    $Classification = @([PSCustomObject]@{
                        'AdminTierLevel'     = "Unclassified"
                        'AdminTierLevelName' = "Unclassified"
                        'Service'            = "Unclassified"
                    })
                }

                if ($IsUnresolvedObject) {
                    # Marker entry flags the fail-closed placeholder in the export and also serves as
                    # the structured warning marker folded into $WarningMessages after the parallel
                    # block. Keep any classifications derived from the assignments themselves, but
                    # drop the generic "Unclassified" fallback in favor of the explicit marker.
                    $Classification = @(($using:UnresolvedMarkerClassification).PSObject.Copy()) + @($Classification | Where-Object { $_.AdminTierLevelName -ne "Unclassified" })
                }

                # Build output object inline (cannot call module functions from parallel runspace)
                [PSCustomObject]@{
                    'ObjectId'                      = $ObjectId
                    'ObjectTenantId'                = $ObjectDetails.ObjectTenantId
                    'ObjectType'                    = ($ObjectDetails.ObjectType ?? 'unknown').ToLower()
                    'ObjectSubType'                 = $ObjectDetails.ObjectSubType
                    'ObjectDisplayName'             = $ObjectDetails.ObjectDisplayName
                    'ObjectUserPrincipalName'       = $ObjectDetails.ObjectSignInName
                    'ObjectAdminTierLevel'          = $ObjectDetails.AdminTierLevel
                    'ObjectAdminTierLevelName'      = $ObjectDetails.AdminTierLevelName
                    'OnPremSynchronized'            = $ObjectDetails.OnPremSynchronized
                    'AssignedAdministrativeUnits'   = $ObjectDetails.AssignedAdministrativeUnits
                    'RestrictedManagementByRAG'     = $ObjectDetails.RestrictedManagementByRAG
                    'RestrictedManagementByAadRole' = $ObjectDetails.RestrictedManagementByAadRole
                    'RestrictedManagementByRMAU'    = $ObjectDetails.RestrictedManagementByRMAU
                    'RoleSystem'                    = $LocalRoleSystem
                    'Classification'                = $Classification
                    'RoleAssignments'               = @($RbacClassifiedAssignments | Sort-Object { ($_.Classification | Sort-Object AdminTierLevel | Select-Object -First 1).AdminTierLevel }, RoleDefinitionName, RoleAssignmentScopeId)
                    'Sponsors'                      = $ObjectDetails.Sponsors
                    'Owners'                        = $ObjectDetails.Owners
                    'OwnedObjects'                  = $ObjectDetails.OwnedObjects
                    'OwnedDevices'                  = $ObjectDetails.OwnedDevices
                    'IdentityParent'                = $ObjectDetails.IdentityParent
                    'AssociatedWorkAccount'         = $ObjectDetails.AssociatedWorkAccount
                    'AssociatedPawDevice'           = $ObjectDetails.AssociatedPawDevice
                }
            }
        }

        # Fold unresolved-object markers from the parallel results into the warning collection:
        # parallel runspaces cannot append to $WarningMessages directly, so each placeholder carries
        # its marker (Classification TaggedBy = "UnresolvedObject") and is surfaced here.
        $UnresolvedClassifiedObjects = @($ClassifiedObjects | Where-Object { @($_.Classification).TaggedBy -contains "UnresolvedObject" })
        foreach ($UnresolvedObject in $UnresolvedClassifiedObjects) {
            $UnresolvedWarning = "Object $($UnresolvedObject.ObjectId) could not be resolved - emitted as fail-closed ControlPlane placeholder (TaggedBy=UnresolvedObject)"
            if ($null -ne $WarningMessages) {
                $WarningMessages.Add([PSCustomObject]@{
                    Type    = "UnresolvedObject"
                    Message = $UnresolvedWarning
                    Target  = $UnresolvedObject.ObjectId
                })
            }
            Write-Warning $UnresolvedWarning
        }

        if ($ClassifiedObjects.Count -ne $UniqueObjects.Count -and $null -ne $WarningMessages) {
            $WarningMessages.Add([PSCustomObject]@{Type = "Stage-Classification-Parallel"; Message = "Parallel classification returned fewer objects than expected. Expected: $($UniqueObjects.Count), Actual: $($ClassifiedObjects.Count)" })
            Write-Warning "Parallel classification returned fewer objects than expected. Expected: $($UniqueObjects.Count), Actual: $($ClassifiedObjects.Count)"
        }
    } else {
        if ($EnableParallelProcessing) {
            Write-Host "Using sequential classification processing (dataset too small: $($UniqueObjects.Count) objects)" -ForegroundColor Yellow
        } else {
            Write-Host "Using sequential classification processing (parallel disabled)..." -ForegroundColor Yellow
        }

        $ClassifiedObjects = $UniqueObjects | ForEach-Object {
            if ($null -ne $_.ObjectId) {
                $ObjectId = $_.ObjectId
                if ($VerbosePreference -ne 'SilentlyContinue') {
                    Write-Verbose -Message "Processing classifications for $($ObjectId)..."
                }

                # Object types
                $ObjectDetails = $ObjectDetailsCache[$ObjectId]

                # Fail-closed: never drop a principal whose object details could not be resolved
                # (failed/throttled Graph call, $null cache entry). A vanished ControlPlane principal
                # would otherwise be removed from its protection group by the Administrative Unit /
                # Conditional Access group reconciliation. Emit a placeholder pinned to ControlPlane
                # instead, built from the identity fields known from the assignment data.
                $IsUnresolvedObject = ($null -eq $ObjectDetails)
                if ($IsUnresolvedObject) {
                    $UnresolvedWarning = "Object $ObjectId could not be resolved - emitted as fail-closed ControlPlane placeholder (TaggedBy=UnresolvedObject)"
                    if ($null -ne $WarningMessages) {
                        $WarningMessages.Add([PSCustomObject]@{
                            Type    = "UnresolvedObject"
                            Message = $UnresolvedWarning
                            Target  = $ObjectId
                        })
                    }
                    Write-Warning $UnresolvedWarning

                    # Shared schema template (see its definition in function scope) - clone and
                    # fill the object-specific fields.
                    $Details = [ordered]@{}
                    foreach ($TemplateKey in $UnresolvedObjectDetailsTemplate.Keys) { $Details[$TemplateKey] = $UnresolvedObjectDetailsTemplate[$TemplateKey] }
                    $Details['ObjectTenantId'] = $_.ObjectTenantId
                    $KnownObjectType = "$($_.ObjectType)"
                    if (-not [string]::IsNullOrWhiteSpace($KnownObjectType)) { $Details['ObjectType'] = $KnownObjectType }
                    $Details['ObjectDisplayName'] = $ObjectId
                    $ObjectDetails = [PSCustomObject]$Details
                }

                # RBAC Assignments
                $RbacClassifiedAssignments = $RbacClassificationsByObject[$ObjectId]

                # Classification - use hashtable for unique aggregation
                $UniqueClassificationsHash = @{}
                foreach ($Assignment in $RbacClassifiedAssignments) {
                    if ($null -ne $Assignment.Classification) {
                        foreach ($ClassItem in $Assignment.Classification) {
                            $key = "$($ClassItem.AdminTierLevel)|$($ClassItem.AdminTierLevelName)|$($ClassItem.Service)"
                            if (-not $UniqueClassificationsHash.ContainsKey($key)) {
                                $UniqueClassificationsHash[$key] = $ClassItem
                            }
                        }
                    }
                }

                $Classification = @($UniqueClassificationsHash.Values | Select-Object -Unique -ExcludeProperty TaggedBy, TaggedByObjectIds, TaggedByObjectDisplayNames, TaggedByRoleSystem | Sort-Object AdminTierLevel, AdminTierLevelName, Service)
                if ($Classification.Count -eq 0) {
                    $Classification = @([PSCustomObject]@{
                        'AdminTierLevel'     = "Unclassified"
                        'AdminTierLevelName' = "Unclassified"
                        'Service'            = "Unclassified"
                    })
                }

                if ($IsUnresolvedObject) {
                    # Marker entry flags the fail-closed placeholder in the export. Keep any
                    # classifications derived from the assignments themselves, but drop the generic
                    # "Unclassified" fallback in favor of the explicit marker.
                    $Classification = @($UnresolvedMarkerClassification.PSObject.Copy()) + @($Classification | Where-Object { $_.AdminTierLevelName -ne "Unclassified" })
                }

                New-EntraOpsEAMOutputObject `
                    -ObjectId $ObjectId `
                    -ObjectDetails $ObjectDetails `
                    -Classification $Classification `
                    -RoleAssignments @($RbacClassifiedAssignments) `
                    -RoleSystem $RoleSystem
            }
        }
    }

    return $ClassifiedObjects
}
