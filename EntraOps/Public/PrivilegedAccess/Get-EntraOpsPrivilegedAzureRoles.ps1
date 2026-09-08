<#
.SYNOPSIS
    Get a list of Azure RBAC role assignments (Azure Resource Manager) including Azure PIM.

.DESCRIPTION
    Get a list of Azure RBAC role assignments across the Azure Resource Manager (ARM) hierarchy.
    By default the collection starts at the ARM tenant root scope ("/") so that role assignments
    made directly at the tenant level are included, then expands to all descendant management
    groups and subscriptions to cover the entire tenant.

    The cmdlet uses the optimized ARM query wrapper (Invoke-EntraOpsAzQuery) to batch requests across
    all scopes and supports the same privileged-access concepts as the other EntraOps Roles cmdlets:
    - Azure PIM (eligible, activated and time-bounded active assignments)
    - Custom roles (RoleType BuiltInRole / CustomRole)
    - Constrained delegations (role assignment ABAC conditions returned in RoleAssignmentCondition /
      RoleAssignmentConditionVersion, or delegated managed identity)
    - Nested groups and PIM for Groups (transitive expansion of group assignments)

.PARAMETER TenantId
    Tenant ID of the Microsoft Entra ID tenant. Default is the current tenant ID.

.PARAMETER Scope
    ARM scope to collect role assignments from (e.g. a management group, subscription, resource group
    or resource). Default is "/" (ARM tenant root scope), which captures tenant-level role assignments
    and, when ExpandDescendantScopes is $true, all management groups and subscriptions beneath the
    Tenant Root Group.

.PARAMETER ExpandDescendantScopes
    When the scope is a management group, expand to all descendant management groups and subscriptions
    to cover the entire sub-tree (tenant-wide by default). Default is $true.

.PARAMETER ControlPlaneScopeFilter
    Optional array of ARM scope patterns (e.g. Control Plane RoleAssignmentScopeName hierarchies from
    Classification_Azure.json) used to restrict the collected scopes. After the scope sub-tree is resolved,
    only scopes that equal, are an ancestor of, or are a descendant of any of the provided patterns are
    queried. Wildcard patterns ("/" and "/*") are ignored because they would not constrain the scan.
    Default is an empty array (no filtering; full sub-tree is scanned).

.PARAMETER PrincipalTypeFilter
    Filter for principal type. Default is User, Group, ServicePrincipal, ForeignGroup, AgentUser and
    AgentServicePrincipal. ForeignGroup and agent types are normalized by the downstream object resolver.

.PARAMETER ExpandGroupMembers
    Expand group members for transitive role assignments (covers nested groups and PIM for Groups).
    Default is $true.

.PARAMETER SampleMode
    Use sample data for testing or offline mode. Default is $False.

.EXAMPLE
    Get all Azure RBAC role assignments across the entire tenant (Tenant Root Group and below).
    Get-EntraOpsPrivilegedAzureRoles

.EXAMPLE
    Get Azure RBAC role assignments of a single subscription only.
    Get-EntraOpsPrivilegedAzureRoles -Scope "/subscriptions/00000000-0000-0000-0000-000000000000" -ExpandDescendantScopes $false

.EXAMPLE
    Get Azure RBAC role assignments of a management group and all its descendant scopes.
    Get-EntraOpsPrivilegedAzureRoles -Scope "/providers/Microsoft.Management/managementGroups/Contoso-Platform"
#>

function Get-EntraOpsPrivilegedAzureRoles {
    param (
        [Parameter(Mandatory = $False)]
        [System.String]$TenantId = (Get-EntraOpsAzContextValue -Property TenantId)
        ,
        [Parameter(Mandatory = $False)]
        [System.String]$Scope
        ,
        [Parameter(Mandatory = $False)]
        [System.Boolean]$ExpandDescendantScopes = $true
        ,
        [Parameter(Mandatory = $False)]
        [Array]$ControlPlaneScopeFilter = @()
        ,
        [Parameter(Mandatory = $False)]
        [ValidateSet("User", "Group", "ServicePrincipal", "ForeignGroup", "AgentUser", "AgentServicePrincipal")]
        [Array]$PrincipalTypeFilter = ("User", "Group", "ServicePrincipal", "ForeignGroup", "AgentUser", "AgentServicePrincipal")
        ,
        [Parameter(Mandatory = $False)]
        [System.Boolean]$ExpandGroupMembers = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$SampleMode = $False
        ,
        [Parameter(Mandatory = $False)]
        [System.Collections.Generic.List[psobject]]$WarningMessages
    )

    # Set Error Action
    $ErrorActionPreference = "Stop"

    # Default to the ARM tenant root scope so tenant-level role assignments are included
    if ([string]::IsNullOrEmpty($Scope)) {
        $Scope = "/"
    }

    # ARM API versions
    $PimApiVersion = "2020-10-01"
    $RbacApiVersion = "2022-04-01"
    $MgmtApiVersion = "2020-05-01"

    $AzureRbacAssignments = @()

    if ($SampleMode -eq $True) {
        Write-Warning "Not supported yet!"
        return
    }

    #region Resolve the list of scopes to query (entire sub-tree for management groups)
    Write-Host "Get Azure RBAC role assignments starting at scope '$Scope'..."
    $Scopes = [System.Collections.Generic.List[string]]::new()
    $Scopes.Add($Scope)

    # When the scope is "/", expand descendants from the Tenant Root Group MG so all management
    # groups and subscriptions are covered in addition to the tenant-level "/" scope itself.
    if ($ExpandDescendantScopes -eq $True -and $Scope -eq "/") {
        $ManagementGroupName = $TenantId
    } elseif ($ExpandDescendantScopes -eq $True -and $Scope -like "*/providers/Microsoft.Management/managementGroups/*") {
        $ManagementGroupName = ($Scope -split '/managementGroups/')[-1]
    } else {
        $ManagementGroupName = $null
    }

    if ($ExpandDescendantScopes -eq $True -and $null -ne $ManagementGroupName) {
        try {
            $Descendants = Invoke-EntraOpsAzQuery -Uri "/providers/Microsoft.Management/managementGroups/$($ManagementGroupName)/descendants" -ApiVersion $MgmtApiVersion
            foreach ($Descendant in $Descendants) {
                if ($Descendant.type -eq "Microsoft.Management/managementGroups") {
                    $Scopes.Add("/providers/Microsoft.Management/managementGroups/$($Descendant.name)")
                } elseif ($Descendant.type -like "*subscriptions") {
                    $Scopes.Add("/subscriptions/$($Descendant.name)")
                }
            }
        } catch {
            $WarningMessage = "Could not expand descendant scopes of management group $($ManagementGroupName): $($_.Exception.Message)"
            if ($null -ne $WarningMessages) {
                $WarningMessages.Add([pscustomobject]@{ Timestamp = (Get-Date); Type = "ScopeExpansion"; ObjectId = $ManagementGroupName; Message = $WarningMessage })
            }
            Write-Warning $WarningMessage
        }
        # Ensure the Tenant Root MG itself is also in the list when starting from "/"
        if ($Scope -eq "/") {
            $Scopes.Add("/providers/Microsoft.Management/managementGroups/$ManagementGroupName")
        }
    }
    # Case-insensitive dedup: ARM returns management group and subscription ids with inconsistent
    # casing, and Select-Object -Unique compares case-sensitively - the same scope could otherwise be
    # queried twice, duplicating every role definition and assignment request made against it.
    $Scopes = @(
        $Scopes |
            Group-Object -Property { "$_".ToLowerInvariant() } |
            ForEach-Object { $_.Group[0] }
    )

    # Restrict scan to Control Plane hierarchies when a scope filter is provided.
    # A scope is kept when it equals, is an ancestor of, or is a descendant of any
    # Control Plane RoleAssignmentScopeName pattern (matching the ARM hierarchy).
    $ScopeFilterPatterns = @($ControlPlaneScopeFilter | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "/" -and $_ -ne "/*" } | Select-Object -Unique)
    if ($ScopeFilterPatterns.Count -gt 0) {
        $UnfilteredScopeCount = @($Scopes).Count
        $Scopes = @($Scopes | Where-Object {
                # Management groups are always retained. Ancestor matching below is string-prefix based, and a
                # management group scope (/providers/Microsoft.Management/managementGroups/<name>) is never a
                # string prefix of /subscriptions/<id>. Filtering them out means the ancestor MG is never
                # queried, so an assignment that is "Direct" only at that MG survives solely as an "Inherited"
                # instance at the subscription - which is skipped below - and disappears entirely. Management
                # groups number in the tens, so retaining all of them is cheap.
                if ($_ -like "/providers/Microsoft.Management/managementGroups/*") { return $true }
                $ScopeItem = $_.TrimEnd('/')
                $Keep = $false
                foreach ($Pattern in $ScopeFilterPatterns) {
                    $PatternTrimmed = $Pattern.TrimEnd('/')
                    if ($ScopeItem -ieq $PatternTrimmed -or $ScopeItem -like $Pattern -or $PatternTrimmed -like "$ScopeItem/*" -or $ScopeItem -like "$PatternTrimmed/*") {
                        $Keep = $true
                        break
                    }
                }
                $Keep
            })
        Write-Host "Control Plane scope filter applied: $(@($Scopes).Count) of $UnfilteredScopeCount scope(s) retained."
        if (@($Scopes).Count -eq 0) {
            $WarningMessage = "Control Plane scope filter matched no scopes; no Azure RBAC assignments will be collected."
            if ($null -ne $WarningMessages) {
                $WarningMessages.Add([pscustomobject]@{ Timestamp = (Get-Date); Type = "ScopeFilter"; ObjectId = ""; Message = $WarningMessage })
            }
            Write-Warning $WarningMessage
        }
    }

    Write-Host "Collecting Azure RBAC assignments across $($Scopes.Count) scope(s)..."
    #endregion

    #region Get role definitions to determine custom roles and privileged classification
    # Fetch built-ins once at the starting scope, then only custom roles at every collected scope.
    # Custom-role visibility depends on assignable scopes, so those queries cannot be collapsed safely.
    $RoleDefinitionRequests = [System.Collections.Generic.List[string]]::new()
    if ($Scopes.Count -gt 0) {
        $RoleDefinitionRequests.Add("$($Scopes[0].TrimEnd('/'))/providers/Microsoft.Authorization/roleDefinitions?api-version=$($RbacApiVersion)")
    }
    foreach ($ScopeItem in $Scopes) {
        $RoleDefinitionRequests.Add("$($ScopeItem.TrimEnd('/'))/providers/Microsoft.Authorization/roleDefinitions?api-version=$($RbacApiVersion)&`$filter=type%20eq%20%27CustomRole%27")
    }
    $RoleDefinitions = Invoke-EntraOpsAzQuery -BatchRequest $RoleDefinitionRequests

    # Build a lookup keyed by role definition GUID (stable across scope prefixes) with name, type and privileged flag
    $PrivilegedActions = @('*', 'Microsoft.Authorization/*', 'Microsoft.Authorization/roleAssignments/write', 'Microsoft.Authorization/roleDefinitions/write', 'Microsoft.Authorization/elevateAccess/action')
    $RoleDefinitionLookup = @{}
    foreach ($RoleDefinition in $RoleDefinitions) {
        $RoleDefinitionGuid = ($RoleDefinition.name)
        if ([string]::IsNullOrEmpty($RoleDefinitionGuid) -or $RoleDefinitionLookup.ContainsKey($RoleDefinitionGuid)) { continue }

        $IsPrivileged = $false
        foreach ($Permission in @($RoleDefinition.properties.permissions)) {
            foreach ($Action in (@($Permission.actions) + @($Permission.dataActions))) {
                if ($Action -in $PrivilegedActions -or $Action -like 'Microsoft.Authorization/role*/write') {
                    $IsPrivileged = $true
                    break
                }
            }
            if ($IsPrivileged) { break }
        }

        $RoleDefinitionLookup[$RoleDefinitionGuid] = [pscustomobject]@{
            RoleDefinitionName = $RoleDefinition.properties.roleName
            RoleType           = if ($RoleDefinition.properties.type -eq "CustomRole") { "CustomRole" } else { "BuiltInRole" }
            IsPrivileged       = $IsPrivileged
        }
    }
    #endregion

    #region Get active/permanent (roleAssignmentScheduleInstances) and eligible (roleEligibilityScheduleInstances) assignments
    # Both endpoints return expandedProperties (principal, roleDefinition, scope) which avoids extra lookups.
    # The ARM tenant root ("/") does not support PIM schedule instance endpoints; exclude it here and
    # handle it separately below via the plain roleAssignments endpoint.
    $PimScopes = @($Scopes | Where-Object { $_ -ne "/" })
    $AssignmentRequests = foreach ($ScopeItem in $PimScopes) {
        "$($ScopeItem.TrimEnd('/'))/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=$($PimApiVersion)"
        "$($ScopeItem.TrimEnd('/'))/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=$($PimApiVersion)"
    }
    $AllInstances = Invoke-EntraOpsAzQuery -BatchRequest $AssignmentRequests

    # Collect plain (always-permanent) role assignments at the tenant root "/" scope.
    $RootScopeRoleAssignments = @()
    if ($Scopes -contains "/") {
        try {
            $RootScopeRoleAssignments = @(Invoke-EntraOpsAzQuery -Uri "/providers/Microsoft.Authorization/roleAssignments?api-version=$($RbacApiVersion)&`$filter=atScope()")
        } catch {
            $WarningMessage = "Could not retrieve role assignments at tenant root scope '/': $($_.Exception.Message)"
            if ($null -ne $WarningMessages) {
                $WarningMessages.Add([pscustomobject]@{ Timestamp = (Get-Date); Type = "ScopeQuery"; ObjectId = "/"; Message = $WarningMessage })
            }
            Write-Warning $WarningMessage
        }
    }

    # Keep only directly assigned instances (memberType "Direct"); PIM-expanded group members (memberType
    # "Group") are resolved by our own transitive expansion below. Dedupe by instance id (the same
    # inherited assignment can be returned from multiple child scope queries).
    $SeenAssignmentIds = @{}
    $AzureRbacAssignments = foreach ($Instance in $AllInstances) {
        if ($null -eq $Instance.properties) { continue }
        if ($Instance.properties.memberType -eq "Group" -or $Instance.properties.memberType -eq "Inherited") { continue }
        if ($SeenAssignmentIds.ContainsKey($Instance.id)) { continue }
        $SeenAssignmentIds[$Instance.id] = $true

        $InstanceProperties = $Instance.properties
        $IsEligible = $Instance.type -like "*RoleEligibilityScheduleInstances"

        # Determine PIM assignment type and whether the role is PIM managed
        if ($IsEligible) {
            $PIMAssignmentType = "Eligible"
            $PIMManagedRole = $True
        } elseif ($InstanceProperties.assignmentType -eq "Activated") {
            $PIMAssignmentType = "Activated"
            $PIMManagedRole = $True
        } elseif ($null -ne $InstanceProperties.endDateTime -or $null -ne $InstanceProperties.linkedRoleEligibilityScheduleInstanceId) {
            $PIMAssignmentType = "TimeBounded"
            $PIMManagedRole = $True
        } else {
            $PIMAssignmentType = "Permanent"
            $PIMManagedRole = $False
        }

        # Resolve role definition details (lookup by GUID, fallback to expandedProperties)
        $RoleDefinitionGuid = ($InstanceProperties.roleDefinitionId -split '/')[-1]
        $RoleDefinitionInfo = $RoleDefinitionLookup[$RoleDefinitionGuid]
        if ($null -ne $RoleDefinitionInfo) {
            $RoleDefinitionName = $RoleDefinitionInfo.RoleDefinitionName
            $RoleType = $RoleDefinitionInfo.RoleType
            $RoleIsPrivileged = $RoleDefinitionInfo.IsPrivileged
        } else {
            $RoleDefinitionName = $InstanceProperties.expandedProperties.roleDefinition.displayName
            $RoleType = if ($InstanceProperties.expandedProperties.roleDefinition.type -eq "CustomRole") { "CustomRole" } else { "BuiltInRole" }
            $RoleIsPrivileged = $false
        }

        # Constrained delegation: role assignment conditions (ABAC) or delegated managed identity
        $RoleAssignmentSubType = ""
        $RoleAssignmentCondition = $InstanceProperties.condition
        $RoleAssignmentConditionVersion = $InstanceProperties.conditionVersion
        if (-not [string]::IsNullOrEmpty($RoleAssignmentCondition)) {
            $RoleAssignmentSubType = "Constrained delegation"
        } elseif (-not [string]::IsNullOrEmpty($InstanceProperties.delegatedManagedIdentityResourceId)) {
            $RoleAssignmentSubType = "Delegated Managed Identity"
        }

        $ScopeId = $InstanceProperties.scope
        $ScopeName = if (-not [string]::IsNullOrEmpty($InstanceProperties.expandedProperties.scope.displayName)) {
            $InstanceProperties.expandedProperties.scope.displayName
        } else {
            $ScopeId
        }

        [pscustomobject]@{
            RoleAssignmentId                      = $Instance.name
            RoleAssignmentScopeId                 = $ScopeId
            RoleAssignmentScopeName               = $ScopeName
            RoleAssignmentType                    = "Direct"
            RoleAssignmentSubType                 = $RoleAssignmentSubType
            RoleAssignmentCondition               = $RoleAssignmentCondition
            RoleAssignmentConditionVersion        = $RoleAssignmentConditionVersion
            PIMManagedRole                        = $PIMManagedRole
            PIMAssignmentType                     = $PIMAssignmentType
            RoleDefinitionName                    = $RoleDefinitionName
            RoleDefinitionId                      = $RoleDefinitionGuid
            RoleType                              = $RoleType
            RoleIsPrivileged                      = $RoleIsPrivileged
            ObjectId                              = $InstanceProperties.principalId
            ObjectTenantId                        = $TenantId
            ObjectType                            = ($InstanceProperties.principalType ?? "unknown").toLower()
            TransitiveByObjectId                  = ""
            TransitiveByObjectDisplayName         = ""
            TransitiveByNestingObjectIds          = $null
            TransitiveByNestingObjectDisplayNames = $null
        }
    }

    # Append permanent role assignments from the ARM tenant root "/" scope.
    # The plain roleAssignments API returns a different shape (no expandedProperties / schedule fields).
    foreach ($RootAssignment in $RootScopeRoleAssignments) {
        if ($null -eq $RootAssignment.properties) { continue }
        if ($SeenAssignmentIds.ContainsKey($RootAssignment.id)) { continue }
        $SeenAssignmentIds[$RootAssignment.id] = $true

        $RootProps = $RootAssignment.properties
        $RoleDefinitionGuid = ($RootProps.roleDefinitionId -split '/')[-1]
        $RoleDefinitionInfo = $RoleDefinitionLookup[$RoleDefinitionGuid]
        if ($null -ne $RoleDefinitionInfo) {
            $RoleDefinitionName = $RoleDefinitionInfo.RoleDefinitionName
            $RoleType = $RoleDefinitionInfo.RoleType
            $RoleIsPrivileged = $RoleDefinitionInfo.IsPrivileged
        } else {
            $RoleDefinitionName = $RoleDefinitionGuid
            $RoleType = "BuiltInRole"
            $RoleIsPrivileged = $false
        }

        $RoleAssignmentSubType = ""
        $RoleAssignmentCondition = $RootProps.condition
        $RoleAssignmentConditionVersion = $RootProps.conditionVersion
        if (-not [string]::IsNullOrEmpty($RoleAssignmentCondition)) {
            $RoleAssignmentSubType = "Constrained delegation"
        } elseif (-not [string]::IsNullOrEmpty($RootProps.delegatedManagedIdentityResourceId)) {
            $RoleAssignmentSubType = "Delegated Managed Identity"
        }

        $AzureRbacAssignments += [pscustomobject]@{
            RoleAssignmentId                      = $RootAssignment.name
            RoleAssignmentScopeId                 = "/"
            RoleAssignmentScopeName               = "/"
            RoleAssignmentType                    = "Direct"
            RoleAssignmentSubType                 = $RoleAssignmentSubType
            RoleAssignmentCondition               = $RoleAssignmentCondition
            RoleAssignmentConditionVersion        = $RoleAssignmentConditionVersion
            PIMManagedRole                        = $False
            PIMAssignmentType                     = "Permanent"
            RoleDefinitionName                    = $RoleDefinitionName
            RoleDefinitionId                      = $RoleDefinitionGuid
            RoleType                              = $RoleType
            RoleIsPrivileged                      = $RoleIsPrivileged
            ObjectId                              = $RootProps.principalId
            ObjectTenantId                        = $TenantId
            ObjectType                            = ($RootProps.principalType ?? "unknown").toLower()
            TransitiveByObjectId                  = ""
            TransitiveByObjectDisplayName         = ""
            TransitiveByNestingObjectIds          = $null
            TransitiveByNestingObjectDisplayNames = $null
        }
    }
    #endregion

    #region Collect transitive assignments by group members (nested groups and PIM for Groups)
    $AzureRbacTransitiveAssignments = [System.Collections.Generic.List[object]]::new()
    if ($ExpandGroupMembers -eq $True) {
        Write-Verbose "Expanding groups for direct or transitive Azure RBAC role assignments"
        $GroupsWithRbacAssignment = $AzureRbacAssignments | Where-Object { $_.ObjectType -eq "group" }
        $AllTransitiveMembers = [System.Collections.Generic.List[object]]::new()

        foreach ($GroupWithRbacAssignment in ($GroupsWithRbacAssignment | Sort-Object ObjectId -Unique)) {
            try {
                $GroupObjectDisplayName = (Invoke-EntraOpsMsGraphQuery -Method Get -Uri "https://graph.microsoft.com/beta/groups/$($GroupWithRbacAssignment.ObjectId)" -OutputType PSObject).displayName
                $TransitiveMembers = Get-EntraOpsPrivilegedTransitiveGroupMember -GroupObjectId $($GroupWithRbacAssignment.ObjectId) -TenantId $TenantId -WarningMessages $WarningMessages
            } catch {
                $WarningMessage = "Could not expand group $($GroupWithRbacAssignment.ObjectId): $($_.Exception.Message)"
                if ($null -ne $WarningMessages) {
                    $WarningMessages.Add([pscustomobject]@{ Timestamp = (Get-Date); Type = "GroupExpansion"; ObjectId = $GroupWithRbacAssignment.ObjectId; Message = $WarningMessage })
                }
                Write-Warning $WarningMessage
                continue
            }

            foreach ($TransitiveMember in $TransitiveMembers) {
                $Member = [pscustomobject]@{
                    displayName               = $TransitiveMember.displayName
                    id                        = $TransitiveMember.id
                    '@odata.type'             = $TransitiveMember.'@odata.type'
                    RoleAssignmentSubType     = $TransitiveMember.RoleAssignmentSubType
                    GroupObjectDisplayName    = $GroupObjectDisplayName
                    GroupObjectId             = $GroupWithRbacAssignment.ObjectId
                    NestingObjectIds          = $TransitiveMember.NestingObjectIds
                    NestingObjectDisplayNames = $TransitiveMember.NestingObjectDisplayNames
                }
                $AllTransitiveMembers.Add($Member)
            }
        }

        # Index transitive members by their assigning group for O(1) lookups instead of
        # re-scanning the full member list for every group assignment.
        $TransitiveMembersByGroup = @{}
        foreach ($TransitiveMemberEntry in $AllTransitiveMembers) {
            if (-not $TransitiveMembersByGroup.ContainsKey($TransitiveMemberEntry.GroupObjectId)) {
                $TransitiveMembersByGroup[$TransitiveMemberEntry.GroupObjectId] = [System.Collections.Generic.List[object]]::new()
            }
            $TransitiveMembersByGroup[$TransitiveMemberEntry.GroupObjectId].Add($TransitiveMemberEntry)
        }

        foreach ($RbacAssignmentByGroup in $GroupsWithRbacAssignment) {
            $RbacAssignmentByNestedGroupMembers = $TransitiveMembersByGroup[$RbacAssignmentByGroup.ObjectId]

            if ($null -ne $RbacAssignmentByNestedGroupMembers -and $RbacAssignmentByNestedGroupMembers.Count -gt 0) {
                $RbacAssignmentByNestedGroupMembers | ForEach-Object {
                    $TransitiveAssignment = [pscustomobject]@{
                        RoleAssignmentId                      = $RbacAssignmentByGroup.RoleAssignmentId
                        RoleAssignmentScopeId                 = $RbacAssignmentByGroup.RoleAssignmentScopeId
                        RoleAssignmentScopeName               = $RbacAssignmentByGroup.RoleAssignmentScopeName
                        RoleAssignmentType                    = "Transitive"
                        RoleAssignmentSubType                 = $_.RoleAssignmentSubType
                        RoleAssignmentCondition               = $RbacAssignmentByGroup.RoleAssignmentCondition
                        RoleAssignmentConditionVersion        = $RbacAssignmentByGroup.RoleAssignmentConditionVersion
                        PIMManagedRole                        = $RbacAssignmentByGroup.PIMManagedRole
                        PIMAssignmentType                     = $RbacAssignmentByGroup.PIMAssignmentType
                        RoleDefinitionName                    = $RbacAssignmentByGroup.RoleDefinitionName
                        RoleDefinitionId                      = $RbacAssignmentByGroup.RoleDefinitionId
                        RoleType                              = $RbacAssignmentByGroup.RoleType
                        RoleIsPrivileged                      = $RbacAssignmentByGroup.RoleIsPrivileged
                        ObjectId                              = $_.id
                        ObjectTenantId                        = $TenantId
                        ObjectType                            = $_.'@odata.type'.Replace('#microsoft.graph.', '').toLower()
                        TransitiveByObjectId                  = $RbacAssignmentByGroup.ObjectId
                        TransitiveByObjectDisplayName         = $_.GroupObjectDisplayName
                        TransitiveByNestingObjectIds          = $_.NestingObjectIds
                        TransitiveByNestingObjectDisplayNames = $_.NestingObjectDisplayNames
                    }
                    $AzureRbacTransitiveAssignments.Add($TransitiveAssignment) | Out-Null
                }
            } else {
                if ($null -ne $WarningMessages) {
                    $WarningMessages.Add([pscustomobject]@{ Timestamp = (Get-Date); Type = "EmptyGroup"; ObjectId = $RbacAssignmentByGroup.ObjectId; Message = "Group has no members or members could not be resolved." })
                }
            }
        }
    }
    #endregion

    $AllAzureRbacAssignments = @()
    $AllAzureRbacAssignments += $AzureRbacAssignments
    $AllAzureRbacAssignments += $AzureRbacTransitiveAssignments
    $AllAzureRbacAssignments = $AllAzureRbacAssignments | Where-Object { $_.ObjectType -in $PrincipalTypeFilter }

    # Efficient deduplication using composite key (assignment, principal, assignment type)
    $DeduplicationHash = @{}
    $UniqueAssignments = foreach ($Assignment in $AllAzureRbacAssignments) {
        $Key = "$($Assignment.RoleAssignmentId)|$($Assignment.ObjectId)|$($Assignment.RoleAssignmentType)"
        if (-not $DeduplicationHash.ContainsKey($Key)) {
            $DeduplicationHash[$Key] = $true
            $Assignment
        }
    }

    $UniqueAssignments | Sort-Object RoleAssignmentId, RoleAssignmentType, ObjectId
}
