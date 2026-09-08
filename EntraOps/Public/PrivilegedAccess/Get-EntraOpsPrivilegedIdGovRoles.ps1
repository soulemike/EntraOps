<#
.SYNOPSIS
    Get a list of delegated administrator roles in Microsoft Entra Identity Governance.

.DESCRIPTION
    Get a list of delegated administrator roles in Microsoft Entra Identity Governance.

.PARAMETER TenantId
    Tenant ID of the Microsoft Entra ID tenant. Default is the current tenant ID.

.PARAMETER PrincipalTypeFilter
    Filter for principal type. Default is User, Group, ServicePrincipal. Possible values are User, Group, ServicePrincipal.

.PARAMETER ExpandGroupMembers
    Expand group members for transitive role assignments. Default is $true.

.PARAMETER SampleMode
    Use sample data for testing or offline mode. Default is $False.

.PARAMETER ExcludeInvalidOrDeletedScopes
    Exclude role assignments whose RoleAssignmentScopeName could not be resolved (shown as
    "Invalid or deleted object", e.g. a deleted access package catalog) from the output.
    Default is $true.

.EXAMPLE
    Get a list of delegated administrator assignment in Identity Governance access packages and catalogs.
    Get-EntraOpsPrivilegedIdGovRoles
#>

function Get-EntraOpsPrivilegedIdGovRoles {
    param (
        [Parameter(Mandatory = $False)]
        [System.String]$TenantId
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
        [Parameter(Mandatory = $False)]
        [System.Boolean]$ExcludeInvalidOrDeletedScopes = $true
        ,
        [Parameter(Mandatory = $False)]
        [System.Collections.Generic.List[psobject]]$WarningMessages
    )

    # Set Error Action
    $ErrorActionPreference = "Stop"

    $ElmRbacAssignments = @()

    if ($SampleMode -eq $True) {
        Write-Warning "Not supported yet!"
    } else {
        $ElmRoleDefinitions = Invoke-EntraOpsMsGraphQuery -Uri "/beta/roleManagement/entitlementManagement/roleDefinitions?`$select=id,displayName,description"
        $ElmRoleAssignments = Invoke-EntraOpsMsGraphQuery -Uri "/beta/roleManagement/entitlementManagement/roleAssignments?`$select=id,principalId,roleDefinitionId,appScopeId"
    }

    $ElmRoleAssignmentPrincipals = ($ElmRoleAssignments | select-object principalId -Unique).principalId
    Write-Host "Processing $($ElmRoleAssignmentPrincipals.Count) Identity Governance role principals..."

    # Optimization: every principal's role assignments are already present in $ElmRoleAssignments
    # (fetched once above) - group them in memory instead of re-querying Graph per principal with an
    # advanced query ($count=true&$filter=principalId eq ..., ConsistencyLevel eventual). That
    # per-principal call returned data already in hand, and its cost scales with the tenant's total
    # Entitlement Management role assignment count, not just this principal's assignments - so it gets
    # slower over time purely as the tenant's Identity Governance footprint grows, independent of how
    # many principals/assignments are actually relevant here.
    $ElmRoleAssignmentsByPrincipal = $ElmRoleAssignments | Group-Object -Property principalId -AsHashTable -AsString

    # Optimization: resolve every principal's directory object type with a single batched call instead
    # of one /beta/directoryObjects/$Principal GET per principal.
    $PrincipalTypeById = @{}
    if ($ElmRoleAssignmentPrincipals.Count -gt 0) {
        $ResolutionBatchSize = 100
        for ($i = 0; $i -lt $ElmRoleAssignmentPrincipals.Count; $i += $ResolutionBatchSize) {
            $Batch = @($ElmRoleAssignmentPrincipals[$i..([Math]::Min($i + $ResolutionBatchSize - 1, $ElmRoleAssignmentPrincipals.Count - 1))])
            $Body = @{ ids = $Batch; types = @('user', 'group', 'servicePrincipal') } | ConvertTo-Json
            try {
                $ResolvedPrincipals = Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/beta/directoryObjects/getByIds" -Body $Body -OutputType PSObject
                foreach ($ResolvedPrincipal in $ResolvedPrincipals) {
                    $PrincipalTypeById[$ResolvedPrincipal.id] = $ResolvedPrincipal.'@odata.type'.Replace('#microsoft.graph.', '')
                }
            } catch {
                Write-Verbose "Batched principal type resolution failed for this batch, falling back to per-principal lookups: $($_.Exception.Message)"
            }
        }
    }

    # Optimization: cache catalog display name lookups by CatalogId - the same catalog is commonly
    # referenced by role assignments across multiple principals. Pre-populated with ONE list call
    # instead of an individual GET per referenced catalog: role assignments regularly reference
    # deleted catalogs, and each of those previously cost a full (404) round-trip.
    $CatalogDisplayNameCache = @{}
    $AllCatalogsFetched = $false
    try {
        $AllCatalogs = Invoke-EntraOpsMsGraphQuery -Uri "/beta/identityGovernance/entitlementManagement/accessPackageCatalogs?`$select=id,displayName" -OutputType PSObject -ThrowOnFailure
        foreach ($Catalog in @($AllCatalogs)) {
            if ($null -ne $Catalog.id) { $CatalogDisplayNameCache[$Catalog.id] = $Catalog.displayName }
        }
        $AllCatalogsFetched = $true
    } catch {
        Write-Verbose "Bulk catalog list fetch failed, falling back to per-catalog lookups: $($_.Exception.Message)"
    }

    $PrincipalCounter = 0
    $ElmRbacAssignments = foreach ($Principal in $ElmRoleAssignmentPrincipals) {
        $PrincipalCounter++
        if (($PrincipalCounter % 10) -eq 0 -or $PrincipalCounter -eq $ElmRoleAssignmentPrincipals.Count) {
            $PercentComplete = [math]::Round(($PrincipalCounter / $ElmRoleAssignmentPrincipals.Count) * 100, 0)
            Write-Progress -Activity "Processing IdGov Role Principals" -Status "Processing principal $PrincipalCounter of $($ElmRoleAssignmentPrincipals.Count)" -PercentComplete $PercentComplete
        }
        Write-Verbose "Get identity information from permanent member $Principal"
        # Reset to avoid carrying over the ObjectType from a previous iteration when resolution fails
        $ObjectType = $null
        if ($PrincipalTypeById.ContainsKey($Principal)) {
            $ObjectType = $PrincipalTypeById[$Principal]
        } else {
            # Fallback for principals the batched resolution missed (e.g. deleted, or a type outside
            # user/group/servicePrincipal)
            try {
                $PrincipalProfile = Invoke-EntraOpsMsGraphQuery -Method Get -Uri "https://graph.microsoft.com/beta/directoryObjects/$($Principal)" -OutputType PSObject
                $ObjectType = $PrincipalProfile.'@odata.type'.Replace('#microsoft.graph.', '')
            } catch {
                $WarningMessage = "Issue to resolve directory object $Principal! $($_.Exception.Message)"
                if ($null -ne $WarningMessages) {
                    $WarningMessages.Add([pscustomobject]@{
                            Timestamp = (Get-Date)
                            Type      = "ObjectResolutionError"
                            ObjectId  = $Principal
                            Message   = $WarningMessage
                        })
                }
                Write-Warning $WarningMessage
            }
        }

        # Optimization: filter the already-fetched bulk role assignments in memory (see
        # $ElmRoleAssignmentsByPrincipal above) instead of re-querying Graph per principal.
        $AllPrinicpalElmRoleAssignments = $ElmRoleAssignmentsByPrincipal["$Principal"]
        foreach ($ElmPrincipalRoleAssignment in $AllPrinicpalElmRoleAssignments) {
            $Role = ($ElmRoleDefinitions | where-object { $_.id -eq $ElmPrincipalRoleAssignment.roleDefinitionId })

            try {
                if ($ElmPrincipalRoleAssignment.appScopeId -eq "/") {
                    $AccessPackageDisplayName = "Directory"
                } else {
                    $CatalogId = $($ElmPrincipalRoleAssignment.appScopeId).Replace("/AccessPackageCatalog/", "")
                    if ($CatalogDisplayNameCache.ContainsKey($CatalogId)) {
                        $AccessPackageDisplayName = $CatalogDisplayNameCache[$CatalogId]
                    } elseif ($AllCatalogsFetched) {
                        # Authoritative full catalog list was fetched - a missing id means the
                        # catalog no longer exists, no per-catalog probe needed.
                        $AccessPackageDisplayName = "Invalid or deleted object"
                        if ($null -ne $WarningMessages) {
                            $WarningMessages.Add([pscustomobject]@{
                                    Timestamp = (Get-Date)
                                    Type      = "CatalogResolution"
                                    ObjectId  = $CatalogId
                                    Message   = "Access Package Catalog $CatalogId not found (likely deleted)."
                                })
                        }
                        $CatalogDisplayNameCache[$CatalogId] = $AccessPackageDisplayName
                    } else {
                        $CatalogObj = Invoke-EntraOpsMsGraphQuery -Uri "/beta/identityGovernance/entitlementManagement/accessPackageCatalogs/$($CatalogId)" -OutputType PSObject -WarningAction SilentlyContinue
                        if ($null -ne $CatalogObj) {
                            $AccessPackageDisplayName = $CatalogObj.displayName
                        } else {
                            $AccessPackageDisplayName = "Invalid or deleted object"
                            if ($null -ne $WarningMessages) {
                                $WarningMessages.Add([pscustomobject]@{
                                        Timestamp = (Get-Date)
                                        Type      = "CatalogResolution"
                                        ObjectId  = $CatalogId
                                        Message   = "Access Package Catalog $CatalogId not found (likely deleted)."
                                    })
                            }
                        }
                        $CatalogDisplayNameCache[$CatalogId] = $AccessPackageDisplayName
                    }
                }
            } catch {
                $AccessPackageDisplayName = "Invalid or deleted object"
            }

            [pscustomobject]@{
                RoleAssignmentId              = $ElmPrincipalRoleAssignment.Id
                RoleAssignmentScopeId         = $ElmPrincipalRoleAssignment.appScopeId
                RoleAssignmentScopeName       = $AccessPackageDisplayName
                RoleAssignmentType            = "Direct"
                RoleAssignmentSubType         = ""
                PIMManagedRole                = $False
                PIMAssignmentType             = "Permanent"
                RoleDefinitionName            = $Role.displayName
                RoleDefinitionId              = $ElmPrincipalRoleAssignment.roleDefinitionId
                RoleType                      = "BuiltInRole"
                RoleIsPrivileged              = $Role.isPrivileged
                ObjectId                      = $Principal
                ObjectTenantId                = $TenantId
                ObjectType                    = $ObjectType.toLower()
                TransitiveByObjectId          = ""
                TransitiveByObjectDisplayName = ""
                TransitiveByNestingObjectIds          = $null
                TransitiveByNestingObjectDisplayNames = $null
            }
        }
    }
    # List all eligible roleAssignment

    #region Collect transitive assignments by group members of Role-Assignable Groups
    if ($ExpandGroupMembers -eq $True) {    
        Write-Verbose "Expanding groups for direct or transitive ELM role assignments"
        $GroupsWithRbacAssignment = $ElmRbacAssignments | where-object { $_.ObjectType -eq "group" }
        $AllTransitiveMembers = @()

        foreach ($GroupWithRbacAssignment in $GroupsWithRbacAssignment) {
            $GroupObjectDisplayName = (Invoke-EntraOpsMsGraphQuery -Method Get -Uri "https://graph.microsoft.com/beta/groups/$($GroupWithRbacAssignment.ObjectId)" -OutputType PSObject).displayName
            $TransitiveMembers = Get-EntraOpsPrivilegedTransitiveGroupMember -GroupObjectId $($GroupWithRbacAssignment.ObjectId) -WarningMessages $WarningMessages
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

        $ElmRbacTransitiveAssignments = [System.Collections.Generic.List[object]]::new()
        foreach ($RbacAssignmentByGroup in ($GroupsWithRbacAssignment | where-object { $_.ObjectType -eq "group" }) ) {

            $RbacAssignmentByNestedGroupMembers = $AllTransitiveMembers | Where-Object { $_.GroupObjectId -eq $RbacAssignmentByGroup.ObjectId }

            if ($RbacAssignmentByNestedGroupMembers.Count -gt 0) {
                $RbacAssignmentByNestedGroupMembers | foreach-object {
                    $TransitiveAssignment = [pscustomobject]@{
                        RoleAssignmentId              = $RbacAssignmentByGroup.RoleAssignmentId
                        RoleAssignmentScopeId         = $RbacAssignmentByGroup.RoleAssignmentScopeId
                        RoleAssignmentScopeName       = $RbacAssignmentByGroup.RoleAssignmentScopeName
                        RoleAssignmentType            = "Transitive"
                        RoleAssignmentSubType         = $_.RoleAssignmentSubType
                        PIMManagedRole                = $RbacAssignmentByGroup.PIMManagedRole
                        PIMAssignmentType             = $RbacAssignmentByGroup.PIMAssignmentType
                        RoleDefinitionName            = $RbacAssignmentByGroup.RoleDefinitionName
                        RoleDefinitionId              = $RbacAssignmentByGroup.RoleDefinitionId
                        RoleType                      = $RbacAssignmentByGroup.RoleType
                        RoleIsPrivileged              = $RbacAssignmentByGroup.RoleIsPrivileged
                        ObjectId                      = $_.Id
                        ObjectType                    = $_.'@odata.type'.Replace('#microsoft.graph.', '').toLower()
                        TransitiveByObjectId          = $RbacAssignmentByGroup.ObjectId
                        TransitiveByObjectDisplayName = $_.GroupObjectDisplayName
                        TransitiveByNestingObjectIds          = $_.NestingObjectIds
                        TransitiveByNestingObjectDisplayNames = $_.NestingObjectDisplayNames
                    }
                    $ElmRbacTransitiveAssignments.Add($TransitiveAssignment) | Out-Null
                }
            } else {
                if ($null -ne $WarningMessages) {
                    $WarningMessages.Add([pscustomobject]@{
                            Timestamp = (Get-Date)
                            Type      = "EmptyGroup"
                            ObjectId  = $RbacAssignmentByGroup.ObjectId
                            Message   = "Group has no members or members could not be resolved."
                        })
                }
            }
        }
    }
    #endregion

    $AllElmRbacAssignments = @()
    $AllElmRbacAssignments += $ElmRbacAssignments
    $AllElmRbacAssignments += $ElmRbacTransitiveAssignments
    $AllElmRbacAssignments = $AllElmRbacAssignments | where-object { $_.ObjectType -in $PrincipalTypeFilter }
    if ($ExcludeInvalidOrDeletedScopes -eq $true) {
        $AllElmRbacAssignments = $AllElmRbacAssignments | where-object { $_.RoleAssignmentScopeName -ne "Invalid or deleted object" }
    }
    $AllElmRbacAssignments = $AllElmRbacAssignments | select-object -Unique *
    $AllElmRbacAssignments | Sort-Object RoleAssignmentId, RoleAssignmentType, ObjectId
}