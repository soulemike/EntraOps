<#
.SYNOPSIS
    Creates the necessary authorization structure for a new service

.DESCRIPTION
    Creates the foundation for handling authorization of a new service
    in alignment with the Microsoft Enterprise Access Model.

.PARAMETER ServiceName
    The Name of the Service

.PARAMETER ServiceMembers
    The UserId (i.e., UPN) of the Service members
    Will default to the identity logged on to Graph

.PARAMETER ServiceOwner
    The UserId (i.e., UPN) of the Service owner
    Will default to the identity logged on to Graph

.PARAMETER OwnerIsNotMember
    Set this flag to not include the Service owner as a member of the service

.PARAMETER ProhibitDirectElevation
    Set this flag to skip configuration of Entra Priviliged Identity Management

.PARAMETER EnablePIMOwnerAssignment
    When set, creates PIM for Groups eligible-owner assignments for the service owner
    in addition to the default eligible-member assignments for the Members group.
    Disabled by default — use this switch to opt in.

.PARAMETER SkipAzureResourceGroup
    Set this flag to skip configuration of Azure Resource Group

.PARAMETER AzureRegion
    Set this to the preferred Azure Region for the Resource Group

.PARAMETER SkipControlPlaneDelegation
    Skip creation of a new ControlPlane-Admins group and its Catalog Owner / Azure UAA delegation.
    Applied automatically when ControlPlaneDelegationGroupId is provided.

.PARAMETER SkipManagementPlaneDelegation
    Skip creation of a new ManagementPlane-Admins group and its delegation.
    Applied automatically when ManagementPlaneDelegationGroupId is provided.

.PARAMETER ControlPlaneDelegationGroupId
    Object ID of an existing Entra group to use as ControlPlane-Admins instead of creating a new one.
    When set, SkipControlPlaneDelegation is enforced automatically and the provided group is used for
    the Catalog Owner role assignment and the PIM-eligible Azure User Access Administrator role on the
    resource group.

.PARAMETER ManagementPlaneDelegationGroupId
    Object ID of an existing Entra group to use as ManagementPlane-Admins instead of creating a new one.
    When set, SkipManagementPlaneDelegation is enforced automatically and the provided group is used for
    the AP Assignment Manager catalog role, access package approval policies, and the PIM-eligible Azure
    Contributor role on the resource group.

.PARAMETER AdministratorGroupId
    Object ID of an existing Entra group to use as CatalogPlane-Members instead of creating a new one.
    When set, the CatalogPlane-Members role is removed from group creation and the provided group is
    injected as a synthetic entry. This group controls who can request elevated access packages and
    who reviews expiring assignments.
    Falls back to EntraOpsConfig.ServiceEM.AdministratorGroupId when not provided via landing zones.

.PARAMETER ServiceRoles
    Define the functional roles of the Service as an object with the columns
    accessLevel,name,groupType. Where accessLevel is the EAM plane classification (e.g., WorkloadPlane,
    ManagementPlane, ControlPlane, CatalogPlane) (an unset value is the default group), name is the functional
    purpose (e.g., Admins, Members, Users), and groupType is the Entra group type (e.g., Unified) (an unset
    value will default to a security group). The default value will create one unified members group, three
    security members groups (CatalogPlane, ManagementPlane, WorkloadPlane), one security user WorkloadPlane
    group, and four security admin groups (WorkloadPlane, ControlPlane, ManagementPlane, and one member role).

.PARAMETER logPrefix
    Defines the text to prepend for any verbose messages

.EXAMPLE
    New-EntraOpsServiceBootstrap -ServiceName "MyService" -AzureRegion "westeurope"

    Creates the full authorization structure for "MyService" with all default EAM groups, an Entra ID
    Entitlement Management catalog and access packages, PIM policies, and an Azure resource group in
    West Europe. The currently signed-in user becomes both owner and member.

.EXAMPLE
    New-EntraOpsServiceBootstrap -ServiceName "MyService" -AzureRegion "westeurope" `
        -ServiceOwner "owner@contoso.com" -ServiceMembers @("alice@contoso.com","bob@contoso.com")

    Creates the authorization structure for "MyService" with an explicit owner and two members.
    The owner is also added as a member unless -OwnerIsNotMember is specified.

.EXAMPLE
    New-EntraOpsServiceBootstrap -ServiceName "MyService" -SkipAzureResourceGroup `
        -ProhibitDirectElevation

    Creates all Entra ID groups, catalog, and access packages without an Azure resource group and
    without configuring PIM eligible assignments.

.EXAMPLE
    New-EntraOpsServiceBootstrap -ServiceName "MyService" -AzureRegion "northeurope" `
        -ControlPlaneDelegationGroupId "00000000-0000-0000-0000-000000000001" `
        -ManagementPlaneDelegationGroupId "00000000-0000-0000-0000-000000000002"

    Creates the authorization structure reusing existing Entra groups as ControlPlane-Admins and
    ManagementPlane-Admins delegates instead of creating new ones. SkipControlPlaneDelegation and
    SkipManagementPlaneDelegation are enforced automatically.

.EXAMPLE
    $CustomRoles = @"
accessLevel,name,groupType
,Members,Unified
WorkloadPlane,Members,
WorkloadPlane,Admins,
ManagementPlane,Admins,
"@ | ConvertFrom-Csv

    New-EntraOpsServiceBootstrap -ServiceName "MyService" -AzureRegion "westeurope" `
        -ServiceRoles $CustomRoles

    Creates the authorization structure with a reduced set of custom EAM roles instead of the
    default set. Useful for services that do not require CatalogPlane or ControlPlane groups.

#>
function New-EntraOpsServiceBootstrap {
    [OutputType([System.String])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [string[]]$ServiceMembers,

        [string]$GroupPrefix = "SG",
        [string]$GroupNamingDelimiter = "-",

        [string]$ServiceOwner,

        [switch]$OwnerIsNotMember,  

        [switch]$ProhibitDirectElevation,

        [switch]$EnablePIMOwnerAssignment,

        [switch]$SkipAzureResourceGroup,

        [switch]$SkipControlPlaneDelegation,

        [switch]$SkipManagementPlaneDelegation,

        [string]$ControlPlaneDelegationGroupId = "",

        [string]$ManagementPlaneDelegationGroupId = "",

        [string]$AdministratorGroupId = "",

        [string]$AzureRegion,

        [psobject[]]$ServiceRoles,

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {

        if (-not $SkipAzureResourceGroup -and [string]::IsNullOrWhiteSpace($AzureRegion)) {
            throw "Parameter -AzureRegion is required unless -SkipAzureResourceGroup is specified."
        }

        #todo update all variables to just use this hashtable
        $report = @{}

        #todo move regions to cmdlets
        #region ServiceOwner
        try {
            Write-Verbose "$logPrefix Service Owner Graph API Lookup"
            if (-not $PSBoundParameters.ContainsKey("ServiceOwner")) {
                Write-Verbose "$logPrefix ServiceOwner not specified, looking up $((Get-MgContext).Account)"
                $graphOwner = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/users/$((Get-MgContext).Account)" -OutputType PSObject
                $owner = "https://graph.microsoft.com/v1.0/users/$($graphOwner.Id)"
            } else {
                Write-Verbose "$logPrefix ServiceOwner set, looking up $ServiceOwner"
                # Handle both user and service principal URLs
                if ($ServiceOwner -match '^https://graph\.microsoft\.com/v1\.0/servicePrincipals/') {
                    # Service principal URL provided
                    $spId = $ServiceOwner -replace '^https://graph\.microsoft\.com/v1\.0/servicePrincipals/', ''
                    $graphOwner = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/servicePrincipals/$spId" -OutputType PSObject
                    $owner = "https://graph.microsoft.com/v1.0/servicePrincipals/$($graphOwner.Id)"
                } elseif ($ServiceOwner -match '^https://graph\.microsoft\.com/v1\.0/users/') {
                    # User URL provided
                    $userId = $ServiceOwner -replace '^https://graph\.microsoft\.com/v1\.0/users/', ''
                    $graphOwner = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/users/$userId" -OutputType PSObject
                    $owner = "https://graph.microsoft.com/v1.0/users/$($graphOwner.Id)"
                } else {
                    # Assume it's a UPN or user ID
                    $graphOwner = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/users/$ServiceOwner" -OutputType PSObject
                    $owner = "https://graph.microsoft.com/v1.0/users/$($graphOwner.Id)"
                }
            }
            Write-Verbose "$logPrefix Setting owner as $owner"
        } catch {
            Write-Verbose "$logPrefix Failed to process Service Owner"
            Write-Error $_
        }
        #endregion

        #region ServiceMembers
        try {
            Write-Verbose "$logPrefix Service Members Graph API Lookup"
            $graphMembers = @()
            if (-not $PSBoundParameters.ContainsKey("ServiceMembers")) {
                $graphMembers = @(
                    $(Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/users/$((Get-MgContext).Account)" -OutputType PSObject)
                )
            } else {
                foreach ($serviceMember in $ServiceMembers) {
                    $graphMembers += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/users/$serviceMember" -OutputType PSObject
                }
            }
            if ($graphOwner.Id -notin $graphMembers.Id -and -not $OwnerIsNotMember) {
                $graphMembers += $graphOwner
            }
        } catch {
            Write-Verbose "$logPrefix Failed to process Service Members"
            Write-Error $_
        }
        #endregion

        #region ServiceRoles
        Write-Verbose "$logPrefix Service Roles validation"
        if (-not $PSBoundParameters.ContainsKey("ServiceRoles")) {
            $ServiceRoles = @"
accessLevel,name,groupType
,Members,Unified
CatalogPlane,Members,
ManagementPlane,Members,
WorkloadPlane,Members,
WorkloadPlane,Users,
WorkloadPlane,Admins,
ControlPlane,Admins,
ManagementPlane,Admins,
"@| ConvertFrom-Csv
        } else {
            if (($ServiceRoles | Measure-Object).Count -lt 1) {
                throw "`$ServiceRoles was supplied, but did not have any objects defined"
            }

            foreach ($ServiceRole in $ServiceRoles) {
                if (@("Users", "Admins", "Members") -inotcontains $ServiceRole.name) {
                    throw "$($ServiceRole.name) is not in accepted values of 'Users', 'Admins', or 'Members'"
                }
                if (@("WorkloadPlane", "ControlPlane", "ManagementPlane", "CatalogPlane", "") -inotcontains $ServiceRole.accessLevel) {
                    throw "$($ServiceRole.accessLevel) is not in accepted values of 'WorkloadPlane', 'ControlPlane', 'ManagementPlane', 'CatalogPlane', or ''"
                }
                if (@("Unified", "Security", "") -inotcontains $ServiceRole.groupType) {
                    throw "$($ServiceRole.groupType) is not in accepted values of 'Unified' or ''"
                }
                if ($ServiceRole.name -ieq "Users" -and $ServiceRole.accessLevel -ine "WorkloadPlane") {
                    throw "Users should only be for WorkloadPlane access"
                }
            }
        }
        #endregion

        #region Delegation
        # Auto-apply skip flags when delegation Group IDs are provided so that no new groups are created
        # for those planes; the external groups will be injected into $ServiceGroups after group creation.
        if (-not [string]::IsNullOrWhiteSpace($ControlPlaneDelegationGroupId)) {
            Write-Verbose "$logPrefix ControlPlaneDelegationGroupId provided — enforcing SkipControlPlaneDelegation"
            $SkipControlPlaneDelegation = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($ManagementPlaneDelegationGroupId)) {
            Write-Verbose "$logPrefix ManagementPlaneDelegationGroupId provided — enforcing SkipManagementPlaneDelegation"
            $SkipManagementPlaneDelegation = $true
        }

        $SkipAdministratorGroupCreation = $false
        if (-not [string]::IsNullOrWhiteSpace($AdministratorGroupId)) {
            Write-Verbose "$logPrefix AdministratorGroupId provided — skipping CatalogPlane-Members creation"
            $SkipAdministratorGroupCreation = $true
        }
        #endregion
    }

    process {

        Write-Verbose "$logPrefix Removing Control Plane Delegation roles if specified"
        if ($SkipControlPlaneDelegation) {
            $filteredRoles = @()
            foreach ($role in $ServiceRoles) {
                if (-not ($role.name -eq "Admins" -and $role.accessLevel -eq "ControlPlane")) {
                    $filteredRoles += $role
                }
            }
            $ServiceRoles = $filteredRoles
        }

        Write-Verbose "$logPrefix Removing Management Plane Admin roles if delegated"
        if ($SkipManagementPlaneDelegation) {
            $filteredRoles = @()
            foreach ($role in $ServiceRoles) {
                if (-not ($role.name -eq "Admins" -and $role.accessLevel -eq "ManagementPlane")) {
                    $filteredRoles += $role
                }
            }
            $ServiceRoles = $filteredRoles
        }

        Write-Verbose "$logPrefix Removing CatalogPlane-Members role if AdministratorGroupId is provided"
        if ($SkipAdministratorGroupCreation) {
            $filteredRoles = @()
            foreach ($role in $ServiceRoles) {
                if (-not ($role.name -eq "Members" -and $role.accessLevel -eq "CatalogPlane")) {
                    $filteredRoles += $role
                }
            }
            $ServiceRoles = $filteredRoles
        }

        Write-Verbose "$logPrefix Processing Roles to Groups"
        $ServiceEntraGroupOptions = @{
            ServiceName             = $ServiceName
            ServiceOwner            = $owner
            ServiceRoles            = $ServiceRoles
            GroupPrefix             = $GroupPrefix
            GroupNamingDelimiter    = $GroupNamingDelimiter
            ProhibitDirectElevation = $ProhibitDirectElevation
        }
        # Cast to [object[]] so PSCustomObject synthetic delegated entries can be appended
        # with +=. New-EntraOpsServiceEntraGroup returns typed MicrosoftGraphGroup objects;
        # PowerShell cannot use += to append a PSCustomObject to a typed array.
        [object[]]$ServiceGroups = New-EntraOpsServiceEntraGroup @ServiceEntraGroupOptions

        # Inject delegated groups as synthetic entries whose DisplayName matches the existing downstream
        # filter patterns (*-ControlPlane-Admins, *-ManagementPlane-Admins). IsDelegated = $true prevents
        # PIM policy and assignment functions from modifying groups owned by another service.
        if (-not [string]::IsNullOrWhiteSpace($ControlPlaneDelegationGroupId)) {
            Write-Verbose "$logPrefix Injecting delegated ControlPlane-Admins group (ID: $ControlPlaneDelegationGroupId)"
            try {
                $delegatedCtrlGroup = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/groups/$ControlPlaneDelegationGroupId" -OutputType PSObject
                $ServiceGroups += [PSCustomObject]@{
                    Id          = $delegatedCtrlGroup.Id
                    DisplayName = "$GroupPrefix$GroupNamingDelimiter$ServiceName$($GroupNamingDelimiter)ControlPlane$($GroupNamingDelimiter)Admins"
                    IsDelegated = $true
                }
                Write-Verbose "$logPrefix Delegated ControlPlane-Admins: $($delegatedCtrlGroup.DisplayName) ($($delegatedCtrlGroup.Id))"
            } catch {
                Write-Verbose "$logPrefix Failed to look up delegated ControlPlane-Admins group"
                Write-Error $_
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($ManagementPlaneDelegationGroupId)) {
            Write-Verbose "$logPrefix Injecting delegated ManagementPlane-Admins group (ID: $ManagementPlaneDelegationGroupId)"
            try {
                $delegatedMgmtGroup = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/groups/$ManagementPlaneDelegationGroupId" -OutputType PSObject
                $ServiceGroups += [PSCustomObject]@{
                    Id          = $delegatedMgmtGroup.Id
                    DisplayName = "$GroupPrefix$GroupNamingDelimiter$ServiceName$($GroupNamingDelimiter)ManagementPlane$($GroupNamingDelimiter)Admins"
                    IsDelegated = $true
                }
                Write-Verbose "$logPrefix Delegated ManagementPlane-Admins: $($delegatedMgmtGroup.DisplayName) ($($delegatedMgmtGroup.Id))"
            } catch {
                Write-Verbose "$logPrefix Failed to look up delegated ManagementPlane-Admins group"
                Write-Error $_
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($AdministratorGroupId)) {
            Write-Verbose "$logPrefix Injecting delegated CatalogPlane-Members group (ID: $AdministratorGroupId)"
            try {
                $delegatedAdminGroup = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/groups/$AdministratorGroupId" -OutputType PSObject
                $ServiceGroups += [PSCustomObject]@{
                    Id          = $delegatedAdminGroup.Id
                    DisplayName = "$GroupPrefix$GroupNamingDelimiter$ServiceName$($GroupNamingDelimiter)CatalogPlane$($GroupNamingDelimiter)Members"
                    IsDelegated = $true
                }
                Write-Verbose "$logPrefix Delegated CatalogPlane-Members: $($delegatedAdminGroup.DisplayName) ($($delegatedAdminGroup.Id))"
            } catch {
                Write-Verbose "$logPrefix Failed to look up delegated CatalogPlane-Members group"
                Write-Error $_
            }
        }

        $report.Groups = $ServiceGroups
        Write-Verbose "$logPrefix Service Groups IDs: $($report.Groups.Id|ConvertTo-Json -Compress)"

        # Owned (non-delegated) groups are the ones actually created by this landing zone.
        # Delegated groups are injected for downstream filter patterns but must not be added to
        # the catalog or assigned to access packages as resources.
        $ownedGroups = @($ServiceGroups | Where-Object { -not $_.IsDelegated })

        Write-Verbose "$logPrefix Processing Catalog"
        $ServiceEMCatalogOptions = @{
            ServiceName = $ServiceName
        }
        $ServiceEMCatalog = New-EntraOpsServiceEMCatalog @ServiceEMCatalogOptions
        $report.Catalog = $ServiceEMCatalog
        Write-Verbose "$logPrefix Service Catalog ID: $($report.Catalog.Id)"

        Write-Verbose "$logPrefix Processing Catalog Resources"
        $ServiceEMCatalogResourceOptions = @{
            ServiceGroups    = $ownedGroups
            ServiceCatalogId = $ServiceEMCatalog.Id
        }
        $ServiceEMCatalogResources = New-EntraOpsServiceEMCatalogResource @ServiceEMCatalogResourceOptions
        $report.CatalogResources = $ServiceEMCatalogResources
        Write-Verbose "$logPrefix Service Catalog Resource IDs: $($report.CatalogResources.Id|ConvertTo-Json -Compress)"

        Write-Verbose "$logPrefix Processing Catalog Role Assignments"
        $ServiceEMCatalogResourceRolesOptions = @{
            ServiceCatalogId           = $ServiceEMCatalog.Id
            # Pass all groups (including delegated) so delegated ControlPlane/ManagementPlane groups
            # can be matched by their synthetic DisplayName for catalog role assignment.
            ServiceGroups              = $ServiceGroups
            # When a delegation group ID is provided, SkipControlPlaneDelegation was auto-set to suppress
            # group creation but the Owner catalog role must still be assigned to the delegated group.
            SkipControlPlaneDelegation = ($SkipControlPlaneDelegation -and [string]::IsNullOrWhiteSpace($ControlPlaneDelegationGroupId))
        }
        $ServiceEMCatalogResourceRoles = New-EntraOpsServiceEMCatalogResourceRole @ServiceEMCatalogResourceRolesOptions
        $report.CatalogResourceRoles = $ServiceEMCatalogResourceRoles
        Write-Verbose "$logPrefix Service Catalog Resource Role IDs: $($report.CatalogResourceRoles.Id|ConvertTo-Json -Compress)"

        Write-Verbose "$logPrefix Processing Access Packages"
        $ServiceEMAccessPackagesOptions = @{
            ServiceName      = $ServiceName
            ServiceCatalogId = $ServiceEMCatalog.Id
            ServiceRoles     = $ServiceRoles
        }
        $ServiceEMAccessPackages = New-EntraOpsServiceEMAccessPackage @ServiceEMAccessPackagesOptions
        # Guard: when all roles are Unified or delegated (e.g. Sub scope in Centralized model),
        # no access packages are created. PowerShell returns $null for an empty typed array from a
        # function, so normalise to an empty array here and skip all package-dependent steps.
        if (-not $ServiceEMAccessPackages) { $ServiceEMAccessPackages = @() }
        $report.AccessPackages = $ServiceEMAccessPackages
        Write-Verbose "$logPrefix Service Access Package IDs: $($report.AccessPackages.Id|ConvertTo-Json -Compress)"

        if (($ServiceEMAccessPackages | Measure-Object).Count -gt 0) {
            Write-Verbose "$logPrefix Processing assignment of Entra Groups to Access Packages"
            $ServiceEMAccessPackageResourceAssignmentOptions = @{
                ServicePackages         = $ServiceEMAccessPackages
                # Only pass owned groups — delegated groups are not catalog resources and would break matching
                ServiceGroups           = $ownedGroups
                ServiceCatalogResources = $ServiceEMCatalogResources
                ServiceCatalogId        = $ServiceEMCatalog.Id
                ServiceName             = $ServiceName
                GroupPrefix             = $GroupPrefix
                GroupNamingDelimiter    = $GroupNamingDelimiter
            }
            $ServiceEMAccessPackageAssignments = New-EntraOpsServiceEMAccessPackageResourceAssignment @ServiceEMAccessPackageResourceAssignmentOptions
            $report.AccessPackageAssignments = $ServiceEMAccessPackageAssignments
            Write-Verbose "$logPrefix Service Access Package Assignment IDs: $($report.AccessPackageAssignments.Id|ConvertTo-Json -Compress)"

            Write-Verbose "$logPrefix Processing access package policy assignment"
            $ServiceEMAssignmentPolicyOptions = @{
                ServiceCatalogId = $ServiceEMCatalog.Id
                ServicePackages  = $ServiceEMAccessPackages
                ServiceGroups    = $ServiceGroups
                ServiceName      = $ServiceName
            }
            $ServiceEMAssignmentPolicies = New-EntraOpsServiceEMAssignmentPolicy @ServiceEMAssignmentPolicyOptions
            $report.AssignmentPolicies = $ServiceEMAssignmentPolicies
            
            if ($ServiceEMAssignmentPolicies -and ($ServiceEMAssignmentPolicies | Measure-Object).Count -gt 0) {
                Write-Verbose "$logPrefix Service Access Package Assignment Policy IDs: $($report.AssignmentPolicies.Id|ConvertTo-Json -Compress)"

                Write-Verbose "$logPrefix Processing access package assignments"
                $ServiceEMAssignmentOptions = @{
                    ServiceCatalogId          = $ServiceEMCatalog.Id
                    ServiceMembers            = $graphMembers
                    ServiceOwner              = $graphOwner
                    ServiceAssignmentPolicies = $ServiceEMAssignmentPolicies
                    ServicePackages           = $ServiceEMAccessPackages
                }
                $ServiceEMAssignments = New-EntraOpsServiceEMAssignment @ServiceEMAssignmentOptions
                $report.Assignments = $ServiceEMAssignments
                Write-Verbose "$logPrefix Service Access Package Assignment IDs: $($report.Assignments.Id|ConvertTo-Json -Compress)"
            } else {
                Write-Verbose "$logPrefix No assignment policies created — skipping access package assignments"
            }
        } else {
            Write-Verbose "$logPrefix No access packages to configure — skipping resource assignment, policies, and member assignments"
        }

        if (-not $ProhibitDirectElevation) {
            Write-Verbose "$logPrefix Processing PIM policies"
            $ServicePIMPolicyOptions = @{
                ServiceGroups = $ownedGroups
                ServiceName   = $ServiceName
            }
            $ServicePIMPolicies = New-EntraOpsServicePIMPolicy @ServicePIMPolicyOptions
            $report.PimPolicies = $ServicePIMPolicies
            Write-Verbose "$logPrefix Service PIM Policy IDs: $($report.PimPolicies.Id|ConvertTo-Json -Compress)"

            Write-Verbose "$logPrefix Processing PIM assignments"
            $ServicePIMAssignmentOptions = @{
                ServiceGroups           = $ownedGroups
                GroupPrefix             = $GroupPrefix
                GroupNamingDelimiter    = $GroupNamingDelimiter
                EnableOwnerAssignment   = $EnablePIMOwnerAssignment
                ServiceOwnerPrincipalId = $graphOwner.Id
            }
            $ServicePIMAssignments = New-EntraOpsServicePIMAssignment @ServicePIMAssignmentOptions
            $report.PimAssignments = $ServicePIMAssignments
            Write-Verbose "$logPrefix Service PIM Assignment IDs: $($report.PimAssignments.Id|ConvertTo-Json -Compress)"
        }

        if (-not $SkipAzureResourceGroup) {
            Write-Verbose "$logPrefix Processing Azure Container"
            $ServiceAZContainerOptions = @{
                ServiceName                = $ServiceName
                ServiceGroups              = $ServiceGroups
                Location                   = $AzureRegion
                SkipControlPlaneDelegation = ($SkipControlPlaneDelegation -and [string]::IsNullOrWhiteSpace($ControlPlaneDelegationGroupId))
            }
            $ServiceAzContainer = New-EntraOpsServiceAZContainer @ServiceAZContainerOptions
            $report.AzContainer = $ServiceAzContainer
            Write-Verbose "$logPrefix Service Az Container ID: $($report.AzContainer.ResourceId|ConvertTo-Json -Compress)"
        }

        return $report
    }
}