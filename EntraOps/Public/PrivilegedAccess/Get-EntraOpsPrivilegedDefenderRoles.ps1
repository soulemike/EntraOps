<#
.SYNOPSIS
    Get a list of directory role member assignments in Microsoft Defender.

.DESCRIPTION
    Get a list of RBAC member assignments in Microsoft Defender.

.PARAMETER TenantId
    Tenant ID of the Microsoft Microsoft Defender tenant. Default is the current tenant ID.

.PARAMETER PrincipalTypeFilter
    Filter for principal type. Default is User, Group, ServicePrincipal. Possible values are User, Group, ServicePrincipal.

.PARAMETER ExpandGroupMembers
    Expand group members for transitive role assignments. Default is $true.

.PARAMETER SampleMode
    Use sample data for testing or offline mode. Default is $False.

.EXAMPLE
    Get a list of assignment of Microsoft Defender roles.
    Get-EntraOpsPrivilegedDefenderRoles
#>

function Get-EntraOpsPrivilegedDefenderRoles {
    param (
        [Parameter(Mandatory = $False)]
        [System.String]$TenantId = (Get-EntraOpsAzContextValue -Property TenantId)
        ,
        [Parameter(Mandatory = $False)]
        [ValidateSet("User", "Group", "ServicePrincipal")]
        [Array]$PrincipalTypeFilter = ("User", "Group", "ServicePrincipal")
        ,
        [Parameter(Mandatory = $False)]
        [System.Boolean]$ExpandGroupMembers = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$SampleMode = $False
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$EnableParallelProcessing = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Int32]$ParallelThrottleLimit = 10
        ,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.List[psobject]]$WarningMessages
    )

    # Set Error Action
    $ErrorActionPreference = "Stop"

    #region Get Role Definitions and Role Assignments
    Write-Host "Get Defender Role Management Assignments and Role Definition..."
    if ($SampleMode -eq $True) {
        Write-Warning "Not supported yet!"
    } else {
        $DefenderRoleDefinitions = Invoke-EntraOpsMsGraphQuery -Uri "/beta/roleManagement/defender/roleDefinitions?`$select=id,displayName,description,rolePermissions" -OutputType PSObject
        $DefenderRoleAssignments = Invoke-EntraOpsMsGraphQuery -Uri "/beta/roleManagement/defender/roleAssignments?`$select=id,principalIds,roleDefinitionId,appScopeIds,directoryScopeIds" -OutputType PSObject
    }
    
    # Optimization: Build Role Definition Lookup Hashtable for O(1) access
    Write-Verbose "Building Role Definition Lookup Table..."
    $RoleDefLookup = @{}
    foreach ($RoleDef in $DefenderRoleDefinitions) {
        $RoleDefLookup[$RoleDef.id] = $RoleDef
    }
    #endregion


    #region Get role assignments for all permanent role member
    Write-Host "Get details of Defender Role Assignments foreach individual principal..."
    if (![string]::IsNullOrWhiteSpace($DefenderRoleAssignments.id)) {
        # Fetch Defender custom app scopes for resolving appScopeIds to display names. Defender Unified RBAC
        # supports direct scoping on cloud scope sets (Defender for Cloud, type "CloudSet") and identity scopes
        # (MDI, type "UserGroupId"). The customAppScope.id is the value used as appScopeId in Defender Unified
        # RBAC role assignments.
        # NOTE: MDE device groups are NOT part of URBAC assignment scoping. Device group restrictions are
        # configured separately on the Device Groups page (per-group "User access" with Entra groups) and
        # govern per-device visibility alongside Unified RBAC. They are not exposed as appScopeIds.
        $DefenderAppScopes = @()
        try {
            $DefenderAppScopes = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/beta/roleManagement/defender/customAppScopes" -OutputType PSObject -DisableCache
        } catch {
            Write-Warning "Failed to fetch Defender custom app scopes for scope name resolution. $($_.Exception.Message)"
        }

        function Get-DefenderAppScopeLookupKey {
            param([string]$ScopeId, [string]$ScopeType)

            if ([string]::IsNullOrWhiteSpace($ScopeId)) { return $null }
            $ScopeId = $ScopeId.Trim().Trim('/')
            $ScopeParts = @($ScopeId -split '/')
            $ScopeLeafId = $ScopeParts[-1]
            $EffectiveScopeType = if (-not [string]::IsNullOrWhiteSpace($ScopeType)) { $ScopeType } elseif ($ScopeParts.Count -gt 1) { $ScopeParts[-2] } else { '' }
            return "$EffectiveScopeType/$ScopeLeafId".ToLowerInvariant()
        }

        $AppScopeLookup = @{}
        foreach ($AppScope in $DefenderAppScopes) {
            $LookupKey = Get-DefenderAppScopeLookupKey -ScopeId "$($AppScope.id)" -ScopeType "$($AppScope.type)"
            if (-not [string]::IsNullOrEmpty($LookupKey)) { $AppScopeLookup[$LookupKey] = $AppScope }
        }

        # CloudSet custom app scopes for Defender for Cloud RBAC are backed 1:1 by a Microsoft Security
        # Exposure Management "zone" (the CloudSet id's GUID is the zone id). Some zones (e.g. created
        # directly via Security Exposure Management rather than the classic Defender for Cloud RBAC UI)
        # are not returned by /beta/roleManagement/defender/customAppScopes at all, which is why their
        # appScopeId previously fell through to "Unresolved app scope" with 0 subscriptions. Resolving
        # directly against the zones API (using the guid embedded in the appScopeId/CloudSet id) works
        # even when the customAppScopes lookup misses the CloudSet entirely.
        function Get-CloudSetZoneInfo {
            param([string]$CloudSetAppScopeId)

            $Result = [pscustomobject]@{ DisplayName = $null; SubscriptionScopes = @() }
            $ZoneId = "$CloudSetAppScopeId".Trim().Trim('/') -replace '(?i)^cloudset/', ''
            if ([string]::IsNullOrWhiteSpace($ZoneId)) { return $Result }

            try {
                # -ThrowOnFailure so a real failure (e.g. missing Zone.Read.All) lands in the catch
                # below - without it, Invoke-EntraOpsMsGraphQuery just warns and returns $null, and
                # this function's own more specific warning message below never fires.
                # -SuppressForbiddenWarning avoids reporting the same 403 twice, since the catch
                # already emits a message naming the CloudSet and the missing permission.
                $Zone = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/beta/security/zones/$($ZoneId)?`$expand=environments" -OutputType PSObject -ThrowOnFailure -SuppressForbiddenWarning
                $Result.DisplayName = $Zone.displayName
                $ZoneSubscriptionScopes = [System.Collections.Generic.List[string]]::new()
                foreach ($Environment in @($Zone.environments)) {
                    if ("$($Environment.kind)" -eq 'azureSubscription' -and "$($Environment.id)" -match '(?i)^/subscriptions/([0-9a-f-]{36})/?$') {
                        $ZoneSubscriptionScopes.Add("/subscriptions/$($Matches[1].ToLowerInvariant())") | Out-Null
                    }
                }
                $Result.SubscriptionScopes = @($ZoneSubscriptionScopes | Sort-Object -Unique)
            } catch {
                $ZoneWarningMessage = "Failed to resolve Security Exposure Management zone '$ZoneId' for CloudSet '$CloudSetAppScopeId': $($_.Exception.Message)"
                if ($_.Exception.Data['StatusCode'] -eq 403 -or $_.Exception.Message -match '(?i)forbidden') {
                    $ZoneWarningMessage += " This usually means the 'Zone.Read.All' Microsoft Graph permission is missing - re-run New-EntraOpsWorkloadIdentity and grant admin consent, then repeat the collection."
                }
                if ($null -ne $WarningMessages) {
                    $WarningMessages.Add([PSCustomObject]@{
                            Timestamp = (Get-Date)
                            Type      = 'CloudSetZoneResolutionError'
                            ObjectId  = "$CloudSetAppScopeId"
                            Message   = $ZoneWarningMessage
                        })
                }
                Write-Verbose $ZoneWarningMessage
            }
            return $Result
        }

        function Get-CloudSetSubscriptionScopes {
            param([psobject]$CloudSet)

            $ZoneInfo = Get-CloudSetZoneInfo -CloudSetAppScopeId "$($CloudSet.id)"
            if ($ZoneInfo.SubscriptionScopes.Count -gt 0) { return $ZoneInfo.SubscriptionScopes }

            # Fallback for CloudSets that are not zone-backed (or where the zone lookup failed/returned no
            # subscriptions): recover subscription ids embedded in customAttributes if present.
            $subscriptionScopes = [System.Collections.Generic.List[string]]::new()
            if ($null -ne $CloudSet.customAttributes) {
                function Add-CloudSetSubscriptionScope {
                    param([object]$Value, [string]$PropertyName)

                    if ($null -eq $Value) { return }
                    if ($Value -is [string]) {
                        if ($Value.TrimStart().StartsWith('{') -or $Value.TrimStart().StartsWith('[')) {
                            try {
                                Add-CloudSetSubscriptionScope -Value ($Value | ConvertFrom-Json) -PropertyName $PropertyName
                                return
                            } catch {
                                Write-Verbose "CloudSet custom attribute '$PropertyName' is not valid JSON."
                            }
                        }
                        if ($Value -match '(?i)^/subscriptions/([0-9a-f-]{36})/?$') {
                            $subscriptionScopes.Add("/subscriptions/$($Matches[1].ToLowerInvariant())") | Out-Null
                        } elseif ($PropertyName -match '(?i)subscription' -and $Value -match '(?i)^[0-9a-f-]{36}$') {
                            $subscriptionScopes.Add("/subscriptions/$($Value.ToLowerInvariant())") | Out-Null
                        }
                        return
                    }
                    if ($Value -is [System.Collections.IEnumerable]) {
                        foreach ($Item in $Value) { Add-CloudSetSubscriptionScope -Value $Item -PropertyName $PropertyName }
                        return
                    }
                    foreach ($Property in $Value.PSObject.Properties) {
                        Add-CloudSetSubscriptionScope -Value $Property.Value -PropertyName $Property.Name
                    }
                }

                Add-CloudSetSubscriptionScope -Value $CloudSet.customAttributes -PropertyName 'customAttributes'
            }

            return @($subscriptionScopes | Sort-Object -Unique)
        }

        $DefenderRoleAssignmentPrincipals = ($DefenderRoleAssignments | select-object -ExpandProperty principalIds -Unique)
        Write-Host "Processing $($DefenderRoleAssignmentPrincipals.Count) Defender role principals..."
        $PrincipalCounter = 0
        $DefenderPermanentRbacAssignments = foreach ($Principal in $DefenderRoleAssignmentPrincipals) {
            $PrincipalCounter++
            if (($PrincipalCounter % 10) -eq 0 -or $PrincipalCounter -eq $DefenderRoleAssignmentPrincipals.Count) {
                $PercentComplete = [math]::Round(($PrincipalCounter / $DefenderRoleAssignmentPrincipals.Count) * 100, 0)
                Write-Progress -Activity "Processing Defender Role Principals" -Status "Processing principal $PrincipalCounter of $($DefenderRoleAssignmentPrincipals.Count)" -PercentComplete $PercentComplete
            }

            $RawPrincipalId = "$Principal"
            $PrincipalGuid = [guid]::Empty
            if (-not [guid]::TryParse($RawPrincipalId, [ref]$PrincipalGuid)) {
                $WarningMessage = "Skipping Defender role assignment principal with invalid GUID: $RawPrincipalId"
                if ($null -ne $WarningMessages) {
                    $WarningMessages.Add([PSCustomObject]@{
                            Timestamp = (Get-Date)
                            Type      = "InvalidPrincipalId"
                            ObjectId  = $RawPrincipalId
                            Message   = $WarningMessage
                        })
                }
                Write-Warning $WarningMessage
                continue
            }
            $Principal = $PrincipalGuid.ToString()

            Write-Verbose "Get identity information from permanent member $Principal"
            # Reset to avoid carrying over the ObjectType from a previous iteration when resolution fails
            $ObjectType = $null
            try {
                $PrincipalProfile = Invoke-EntraOpsMsGraphQuery -Method Get -Uri "https://graph.microsoft.com/beta/directoryObjects/$($Principal)" -OutputType PSObject
                $ObjectType = $PrincipalProfile.'@odata.type'.Replace('#microsoft.graph.', '')
            } catch {
                $WarningMessage = "Issue to resolve directory object $Principal! $($_.Exception.Message)"
                if ($null -ne $WarningMessages) {
                    $WarningMessages.Add([PSCustomObject]@{
                            Timestamp = (Get-Date)
                            Type      = "ObjectResolutionError"
                            ObjectId  = $Principal
                            Message   = $WarningMessage
                        })
                }
                Write-Warning $WarningMessage
            }

            $AllPrinicpalDefenderRoleAssignments = Invoke-EntraOpsMsGraphQuery -Uri "/beta/roleManagement/defender/RoleAssignments?`$count=true&`$filter=principalIds/any(a:a+eq+'$Principal')" -ConsistencyLevel "eventual" -OutputType PSObject

            foreach ($DefenderPrincipalRoleAssignment in $AllPrinicpalDefenderRoleAssignments) {

                # Optimization: Use hashtable lookup instead of Where-Object for O(1) access
                $Role = $RoleDefLookup[$DefenderPrincipalRoleAssignment.roleDefinitionId]

                if ($null -eq $Role) {
                    $WarningMessage = "Role definition is empty or does not exist for Role Assignment $($DefenderPrincipalRoleAssignment.id)"
                    if ($null -ne $WarningMessages) {
                        $WarningMessages.Add([PSCustomObject]@{
                                Timestamp = (Get-Date)
                                Type      = "RoleDefinitionError"
                                ObjectId  = $DefenderPrincipalRoleAssignment.id
                                Message   = $WarningMessage
                            })
                    }
                    Write-Warning $WarningMessage
                }

                # Check for scope restriction in appScopeIds:
                # Defender Unified RBAC uses appScopeIds for two different things (verified against live tenant data):
                # - Workload/data source tokens (e.g. "Mde", "Mdo", "Mdi", "Mdc", "SecureScoreExternal") when the
                #   assignment applies to ALL scopes of the selected data sources. These do NOT resolve in
                #   customAppScopes and are effectively tenant-wide for the workload. MDE device group
                #   restrictions are managed on the Device Groups page (per-group user access), NOT here.
                # - Ids of directly scoped assignments: customAppScope objects (type "CloudSet" for Defender for
                #   Cloud, "UserGroupId" for Defender for Identity). Only these are real scope restrictions and
                #   must be used as role scope. An unresolved CloudSet remains a bounded scope; it must never be
                #   folded into the tenant-wide workload token list.
                $ResolvedAppScopes = @()
                $WorkloadWideTokens = @()
                $UnresolvedAppScopes = @()
                $WorkloadScopeTokens = @('Mde', 'Mdo', 'Mdi', 'Mdc', 'SecureScoreExternal')
                foreach ($AppScopeId in @($DefenderPrincipalRoleAssignment.appScopeIds | Where-Object { -not [string]::IsNullOrEmpty($_) -and $_ -ne "/" })) {
                    $AppScopeLookupKey = Get-DefenderAppScopeLookupKey -ScopeId "$AppScopeId"
                    $AppScope = $AppScopeLookup[$AppScopeLookupKey]
                    if ($null -ne $AppScope) {
                        $ResolvedAppScopes += [pscustomobject]@{ AppScopeId = "$AppScopeId"; Scope = $AppScope }
                    } elseif ($WorkloadScopeTokens -contains $AppScopeId) {
                        $WorkloadWideTokens += $AppScopeId
                    } elseif ($AppScopeLookupKey -match '(?i)^cloudset/') {
                        # Not returned by /beta/roleManagement/defender/customAppScopes (e.g. a zone created
                        # directly via Security Exposure Management) -- still resolvable via the zones API
                        # using the guid embedded in the appScopeId itself.
                        $ZoneInfo = Get-CloudSetZoneInfo -CloudSetAppScopeId "$AppScopeId"
                        if ($ZoneInfo.SubscriptionScopes.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($ZoneInfo.DisplayName)) {
                            $SyntheticCloudSet = [pscustomobject]@{ id = "$AppScopeId"; type = 'CloudSet'; displayName = $ZoneInfo.DisplayName; customAttributes = $null }
                            $ResolvedAppScopes += [pscustomobject]@{ AppScopeId = "$AppScopeId"; Scope = $SyntheticCloudSet }
                        } else {
                            $UnresolvedAppScopes += $AppScopeId
                            $WarningMessage = "Defender app scope '$AppScopeId' could not be resolved (not in customAppScopes, and its Security Exposure Management zone lookup returned no data). It will be retained as a bounded scope rather than treated as tenant-wide."
                            if ($null -ne $WarningMessages) {
                                $WarningMessages.Add([PSCustomObject]@{
                                        Timestamp = (Get-Date)
                                        Type      = 'UnresolvedDefenderAppScope'
                                        ObjectId  = $DefenderPrincipalRoleAssignment.id
                                        Message   = $WarningMessage
                                    })
                            }
                            Write-Warning $WarningMessage
                        }
                    } else {
                        $UnresolvedAppScopes += $AppScopeId
                        $WarningMessage = "Defender app scope '$AppScopeId' could not be resolved. It will be retained as a bounded scope rather than treated as tenant-wide."
                        if ($null -ne $WarningMessages) {
                            $WarningMessages.Add([PSCustomObject]@{
                                    Timestamp = (Get-Date)
                                    Type      = 'UnresolvedDefenderAppScope'
                                    ObjectId  = $DefenderPrincipalRoleAssignment.id
                                    Message   = $WarningMessage
                                })
                        }
                        Write-Warning $WarningMessage
                    }
                }

                $RoleAssignmentScopes = @(
                    # Assignment restricted to specific scopes (cloud scope sets, identity/user group scopes)
                    foreach ($ResolvedAppScope in $ResolvedAppScopes) {
                        $AppScope = $ResolvedAppScope.Scope
                        $ScopeName = if (-not [string]::IsNullOrEmpty($AppScope.displayName)) { $AppScope.displayName } else { "$($AppScope.type)-$($ResolvedAppScope.AppScopeId)" }
                        $CloudSetSubscriptionScopes = if ($AppScope.type -eq 'CloudSet') { @(Get-CloudSetSubscriptionScopes -CloudSet $AppScope) } else { @() }
                        [pscustomobject]@{ ScopeId = $ResolvedAppScope.AppScopeId; ScopeName = $ScopeName; AppScopeName = @($WorkloadWideTokens); CloudSetSubscriptionScopes = $CloudSetSubscriptionScopes; ScopeResolutionStatus = 'Resolved' }
                    }
                    foreach ($UnresolvedAppScope in $UnresolvedAppScopes) {
                        [pscustomobject]@{ ScopeId = "$UnresolvedAppScope"; ScopeName = "Unresolved app scope ($UnresolvedAppScope)"; AppScopeName = @($WorkloadWideTokens); CloudSetSubscriptionScopes = @(); ScopeResolutionStatus = 'Unresolved' }
                    }
                    if ($ResolvedAppScopes.Count -eq 0 -and $UnresolvedAppScopes.Count -eq 0 -and $WorkloadWideTokens.Count -gt 0) {
                        # Workload-wide data source selection: tenant-wide scope, data sources kept visible in the
                        # name. Kept as a single combined row (not one row per workload token) since this is one
                        # physical role assignment - splitting it into multiple rows would duplicate it across
                        # reports/exports that count or graph by RoleAssignmentId. AppScopeName instead exposes the
                        # individual workload tokens (e.g. "Mde", "Mdo", "Mdi") for per-workload filtering/reporting
                        # without touching the row count or RoleAssignmentScopeName's classification-relevant value.
                        [pscustomobject]@{ ScopeId = "/"; ScopeName = "Tenant-wide ($($WorkloadWideTokens -join ', '))"; AppScopeName = @($WorkloadWideTokens); CloudSetSubscriptionScopes = @(); ScopeResolutionStatus = 'WorkloadWide' }
                    } elseif ($ResolvedAppScopes.Count -eq 0 -and $UnresolvedAppScopes.Count -eq 0) {
                        # No app scopes: directory scope applies (empty value means tenant-wide,
                        # the role is assigned to all devices or all users without specific directoryScopeId)
                        $DirectoryScopeIds = @($DefenderPrincipalRoleAssignment.directoryScopeIds | Where-Object { -not [string]::IsNullOrEmpty($_) })
                        if ($DirectoryScopeIds.Count -eq 0) { $DirectoryScopeIds = @("/") }
                        foreach ($DirectoryScopeId in $DirectoryScopeIds) {
                            $ScopeName = if ($DirectoryScopeId -eq "/") { "Tenant-wide" } else { $DirectoryScopeId }
                            [pscustomobject]@{ ScopeId = "$DirectoryScopeId"; ScopeName = $ScopeName; AppScopeName = $null; CloudSetSubscriptionScopes = @(); ScopeResolutionStatus = 'DirectoryScope' }
                        }
                    }
                )

                foreach ($RoleAssignmentScope in $RoleAssignmentScopes) {
                    [pscustomobject]@{
                        RoleAssignmentId                      = $DefenderPrincipalRoleAssignment.Id
                        RoleAssignmentScopeId                 = $RoleAssignmentScope.ScopeId
                        RoleAssignmentScopeName               = $RoleAssignmentScope.ScopeName
                        AppScopeName                          = $RoleAssignmentScope.AppScopeName
                        CloudSetSubscriptionScopes            = $RoleAssignmentScope.CloudSetSubscriptionScopes
                        ScopeResolutionStatus                 = $RoleAssignmentScope.ScopeResolutionStatus
                        RoleAssignmentType                    = "Direct"
                        RoleAssignmentSubType                 = ""
                        PIMManagedRole                        = $False
                        PIMAssignmentType                     = "Permanent"
                        RoleDefinitionName                    = $Role.displayName
                        RoleDefinitionId                      = $Role.id
                        RoleType                              = if ($Role.isBuiltIn -eq $True) { "Built-In" } else { "Custom" }
                        RoleIsPrivileged                      = $Role.isPrivileged
                        ObjectId                              = $Principal
                        ObjectTenantId                        = $TenantId
                        ObjectType                            = $ObjectType
                        TransitiveByObjectId                  = ""
                        TransitiveByObjectDisplayName         = ""
                        TransitiveByNestingObjectIds          = $null
                        TransitiveByNestingObjectDisplayNames = $null
                    }
                }
            }
        }
        Write-Progress -Activity "Processing Defender Role Principals" -Completed
    } else {
        Write-Warning "No Defender Role Assignments found!"
        $DefenderPermanentRbacAssignments = $null
    }

    #endregion

    # Summarize results with direct permanent (excl. activated roles) and eligible role assignments
    $AllDefenderRbacAssignments = @()
    $AllDefenderRbacAssignments += $DefenderPermanentRbacAssignments

    #region Collect transitive assignments by group members of Role-Assignable Groups or Security Groups
    if ($ExpandGroupMembers -eq $True) {    
        Write-Verbose "Expanding groups for direct or transitive Entra Microsoft Defender XDR role assignments"
        $GroupsWithRbacAssignment = $AllDefenderRbacAssignments | where-object { $_.ObjectType -eq "group" } | Select-Object -Unique ObjectId, ObjectDisplayName
        $AllTransitiveMembers = @()

        foreach ($GroupWithRbacAssignment in $GroupsWithRbacAssignment) {
            $TransitiveMembers = Get-EntraOpsPrivilegedTransitiveGroupMember -GroupObjectId $($GroupWithRbacAssignment.ObjectId) -WarningMessages $WarningMessages
            $GroupObjectDisplayName = (Invoke-EntraOpsMsGraphQuery -Method Get -Uri "https://graph.microsoft.com/beta/groups/$($GroupWithRbacAssignment.ObjectId)" -OutputType PSObject).displayName
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
                $AllTransitiveMembers += $Member
            }
        }

        $DefenderTransitiveRbacAssignments = [System.Collections.Generic.List[object]]::new()
        foreach ($RbacAssignmentByGroup in ($AllDefenderRbacAssignments | where-object { $_.ObjectType -eq "group" }) ) {

            $RbacAssignmentByNestedGroupMembers = $AllTransitiveMembers | Where-Object { $_.GroupObjectId -eq $RbacAssignmentByGroup.ObjectId }

            if ($RbacAssignmentByNestedGroupMembers.Count -gt 0) {
                $RbacAssignmentByNestedGroupMembers | foreach-object {
                    $TransitiveAssignment = [pscustomobject]@{
                        RoleAssignmentId                      = $RbacAssignmentByGroup.RoleAssignmentId
                        RoleAssignmentScopeId                 = $RbacAssignmentByGroup.RoleAssignmentScopeId
                        RoleAssignmentScopeName               = $RbacAssignmentByGroup.RoleAssignmentScopeName
                        AppScopeName                          = $RbacAssignmentByGroup.AppScopeName
                        RoleAssignmentType                    = "Transitive"
                        RoleAssignmentSubType                 = $_.RoleAssignmentSubType
                        PIMManagedRole                        = $RbacAssignmentByGroup.PIMManagedRole
                        PIMAssignmentType                     = $RbacAssignmentByGroup.PIMAssignmentType
                        RoleDefinitionName                    = $RbacAssignmentByGroup.RoleDefinitionName
                        RoleDefinitionId                      = $RbacAssignmentByGroup.RoleDefinitionId
                        RoleType                              = $RbacAssignmentByGroup.RoleType
                        RoleIsPrivileged                      = $RbacAssignmentByGroup.RoleIsPrivileged
                        ObjectId                              = $_.Id
                        ObjectType                            = $_.'@odata.type'.Replace("#microsoft.graph.", "").ToLower()
                        TransitiveByObjectId                  = $RbacAssignmentByGroup.ObjectId
                        TransitiveByObjectDisplayName         = $_.GroupObjectDisplayName
                        TransitiveByNestingObjectIds          = $_.NestingObjectIds
                        TransitiveByNestingObjectDisplayNames = $_.NestingObjectDisplayNames
                    }
                    $DefenderTransitiveRbacAssignments.Add($TransitiveAssignment) | Out-Null
                }
            } else {
                if ($null -ne $WarningMessages) {
                    $WarningMessages.Add([PSCustomObject]@{
                            Type    = "Empty Group"
                            Message = "Empty group $($RbacAssignmentByGroup.ObjectId)"
                            Target  = $RbacAssignmentByGroup.ObjectId
                        })
                }
            }
        }
    }
    #endregion

    #region Filtering export if needed
    $AllDefenderRbacAssignments += $DefenderTransitiveRbacAssignments
    $AllDefenderRbacAssignments = $AllDefenderRbacAssignments | where-object { $_.ObjectType -in $PrincipalTypeFilter }
    $AllDefenderRbacAssignments = $AllDefenderRbacAssignments | select-object -Unique *
    $AllDefenderRbacAssignments | Sort-Object RoleAssignmentId, RoleAssignmentScopeName, RoleAssignmentScopeId, RoleAssignmentType, ObjectId
    #endregion
}