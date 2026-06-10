<#
.SYNOPSIS
    Creates the full EAM authorization structure for a tenant-level landing zone.

.DESCRIPTION
    Iterates over a set of predefined tenant-level service components (Billing,
    Management Groups, Subscriptions, Resource Groups etc.) and calls
    New-EntraOpsServiceBootstrap for each component. Produces a complete
    multi-service EAM authorization structure in a single call.

    Delegation groups (ControlPlane-Admins, ManagementPlane-Admins) are resolved
    once at the start using Resolve-EntraOpsServiceEMDelegationGroup and reused
    across all components. When GovernanceModel = "Centralized" (default), shared
    tenant-wide delegation groups are used. When GovernanceModel = "Decentralized",
    each component creates its own delegation groups.

    Group IDs and group names can be supplied as parameters or read from
    EntraOpsConfig.ServiceEM.

.PARAMETER ServiceMembers
    UPN(s) of users to add as initial service members. Defaults to the
    signed-in identity.

.PARAMETER ServiceOwner
    UPN of the service owner. Defaults to the signed-in identity.

.PARAMETER OwnerIsNotMember
    When set, the owner is not added as a WorkloadPlane-Members member.

.PARAMETER ProhibitDirectElevation
    When set, PIM eligible assignments and policies are skipped for all
    components.

.PARAMETER SkipAzureResourceGroup
    When set, no Azure resource groups are created.

.PARAMETER AzureRegion
    Azure region for resource groups. Required unless -SkipAzureResourceGroup
    is set.

.PARAMETER SkipControlPlaneDelegation
    Skip ControlPlane-Admins group creation. Applied automatically when
    ControlPlaneDelegationGroupId is provided or set in EntraOpsConfig.

.PARAMETER SkipManagementPlaneDelegation
    Skip ManagementPlane-Admins group creation. Applied automatically when
    ManagementPlaneDelegationGroupId is provided or set in EntraOpsConfig.

.PARAMETER ControlPlaneDelegationGroupId
    Object ID of an existing group to use as ControlPlane-Admins across all
    components. Falls back to EntraOpsConfig.ServiceEM.ControlPlaneDelegationGroupId.

.PARAMETER ManagementPlaneDelegationGroupId
    Object ID of an existing group to use as ManagementPlane-Admins across all
    components. Falls back to EntraOpsConfig.ServiceEM.ManagementPlaneDelegationGroupId.

.PARAMETER AdministratorGroupId
    Object ID of an existing group to use as CatalogPlane-Members across all
    components. Falls back to EntraOpsConfig.ServiceEM.AdministratorGroupId.

.PARAMETER ControlPlaneGroupName
    Display name of the tenant-wide ControlPlane delegation group to look up or
    create. Defaults to "PRG-Tenant-ControlPlane-IdentityOps".

.PARAMETER ManagementPlaneGroupName
    Display name of the tenant-wide ManagementPlane delegation group to look up
    or create. Defaults to "PRG-Tenant-ManagementPlane-PlatformOps".

.PARAMETER LandingZoneComponents
    Array of custom component definitions, each with a Role, Components list,
    and ServiceRole array. Defaults to the standard tenant landing zone layout
    (Billing, Management Groups, Subscriptions, Resource Groups).

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsTenantLandingZone -AzureRegion "westeurope"

    Creates the full tenant landing zone with all default components, using
    the signed-in identity as owner and member. Delegation groups are resolved
    from EntraOpsConfig or created automatically.

.EXAMPLE
    New-EntraOpsTenantLandingZone -AzureRegion "northeurope" `
        -ServiceOwner "owner@contoso.com" `
        -ServiceMembers @("alice@contoso.com", "bob@contoso.com") `
        -ControlPlaneDelegationGroupId "00000000-0000-0000-0000-000000000001" `
        -ManagementPlaneDelegationGroupId "00000000-0000-0000-0000-000000000002"

    Creates the tenant landing zone reusing existing central delegation groups
    for ControlPlane-Admins and ManagementPlane-Admins.

.EXAMPLE
    New-EntraOpsTenantLandingZone -AzureRegion "westeurope" -SkipAzureResourceGroup

    Creates all Entra ID groups, EM catalogs, and access packages without
    provisioning any Azure resource groups.

#>
function New-EntraOpsTenantLandingZone {
    [OutputType([System.String])]
    [cmdletbinding()]
    param(
        [string[]]$ServiceMembers,

        [string]$ServiceOwner,

        [switch]$OwnerIsNotMember,

        [switch]$ProhibitDirectElevation,

        [switch]$SkipControlPlaneDelegation,

        [switch]$SkipManagementPlaneDelegation,

        [string]$ControlPlaneDelegationGroupId = "",

        [string]$ManagementPlaneDelegationGroupId = "",

        [string]$AdministratorGroupId = "",

        [string]$ControlPlaneGroupName = "PRG-Tenant-ControlPlane-IdentityOps",

        [string]$ManagementPlaneGroupName = "PRG-Tenant-ManagementPlane-PlatformOps",

        [Parameter(Mandatory)]
        [string]$AzureRegion,

        [pscustomobject[]]$LandingZoneComponents = @(
            [pscustomobject]@{
                Role = "Billing"
                Components = @(
                    "Bill-Organization"
                )
                ServiceRole = @(
                    [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
                    [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Admins"; groupType = ""}
                )
            },
            [pscustomobject]@{
                Role = "Mgs"
                Components = @(
                    "Tenant Root Group",
                    "MG-Platform",
                    "MG-Production",
                    "MG-Build"
                )
                ServiceRole = @(
                    [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
                    [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Admins"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
                )
            },
            [pscustomobject]@{
                Role = "Subs"
                Components = @(
                    "Sub-Management",
                    "Sub-Identity",
                    "Sub-Connectivity",
                    "Sub-Prod-Decommissioned",
                    "Sub-Prod-Platfrom",
                    "Sub-Prod-App",
                    "Sub-Build-Decommissioned",
                    "Sub-Build-Platfrom",
                    "Sub-Build-App"
                )
                ServiceRole = @(
                    [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
                    [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
                )
            },
            [pscustomobject]@{
                Role = "Rg"
                Components = @(
                    "Rg-Default"
                )
                ServiceRole = @(
                    [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
                    [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""},
                    [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Admins"; groupType = ""},
                    [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Admins"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Admins"; groupType = ""}
                )
            }
        ),

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        $report = @{}

        # Read delegation Group IDs from EntraOpsConfig when not supplied as parameters.
        if ([string]::IsNullOrWhiteSpace($ControlPlaneDelegationGroupId) -and
            $null -ne $Global:EntraOpsConfig -and
            $Global:EntraOpsConfig.ContainsKey('ServiceEM') -and
            -not [string]::IsNullOrWhiteSpace($Global:EntraOpsConfig.ServiceEM.ControlPlaneDelegationGroupId)) {
            Write-Verbose "$logPrefix Reading ControlPlaneDelegationGroupId from EntraOpsConfig"
            $ControlPlaneDelegationGroupId = $Global:EntraOpsConfig.ServiceEM.ControlPlaneDelegationGroupId
        }
        if ([string]::IsNullOrWhiteSpace($ManagementPlaneDelegationGroupId) -and
            $null -ne $Global:EntraOpsConfig -and
            $Global:EntraOpsConfig.ContainsKey('ServiceEM') -and
            -not [string]::IsNullOrWhiteSpace($Global:EntraOpsConfig.ServiceEM.ManagementPlaneDelegationGroupId)) {
            Write-Verbose "$logPrefix Reading ManagementPlaneDelegationGroupId from EntraOpsConfig"
            $ManagementPlaneDelegationGroupId = $Global:EntraOpsConfig.ServiceEM.ManagementPlaneDelegationGroupId
        }
        if ([string]::IsNullOrWhiteSpace($AdministratorGroupId) -and
            $null -ne $Global:EntraOpsConfig -and
            $Global:EntraOpsConfig.ContainsKey('ServiceEM') -and
            -not [string]::IsNullOrWhiteSpace($Global:EntraOpsConfig.ServiceEM.AdministratorGroupId)) {
            Write-Verbose "$logPrefix Reading AdministratorGroupId from EntraOpsConfig"
            $AdministratorGroupId = $Global:EntraOpsConfig.ServiceEM.AdministratorGroupId
        }

        # Read GovernanceModel from config (default: Centralized)
        $governanceModel = "Centralized"
        if ($null -ne $Global:EntraOpsConfig -and
            $Global:EntraOpsConfig.ContainsKey('ServiceEM') -and
            -not [string]::IsNullOrWhiteSpace($Global:EntraOpsConfig.ServiceEM.GovernanceModel)) {
            $governanceModel = $Global:EntraOpsConfig.ServiceEM.GovernanceModel
            Write-Verbose "$logPrefix Using ServiceEM.GovernanceModel: $governanceModel"
        }

        # Auto-resolve or create role-assignable delegation groups.
        if ($null -ne $Global:EntraOpsConfig -and
            $Global:EntraOpsConfig.ContainsKey('ServiceEM')) {
            if (-not [string]::IsNullOrWhiteSpace($Global:EntraOpsConfig.ServiceEM.ControlPlaneGroupName)) {
                $ControlPlaneGroupName = $Global:EntraOpsConfig.ServiceEM.ControlPlaneGroupName
            }
            if (-not [string]::IsNullOrWhiteSpace($Global:EntraOpsConfig.ServiceEM.ManagementPlaneGroupName)) {
                $ManagementPlaneGroupName = $Global:EntraOpsConfig.ServiceEM.ManagementPlaneGroupName
            }
        }

        if ($governanceModel -eq "Centralized") {
            Write-Verbose "$logPrefix Centralized governance model - using tenant-wide delegation groups"
            
            $ControlPlaneDelegationGroupId = Resolve-EntraOpsServiceEMDelegationGroup `
                -Plane "ControlPlane" `
                -GroupId $ControlPlaneDelegationGroupId `
                -DefaultGroupName $ControlPlaneGroupName `
                -ConfigKey "ControlPlaneDelegationGroupId" `
                -logPrefix $logPrefix
            $SkipControlPlaneDelegation = $true

            $ManagementPlaneDelegationGroupId = Resolve-EntraOpsServiceEMDelegationGroup `
                -Plane "ManagementPlane" `
                -GroupId $ManagementPlaneDelegationGroupId `
                -DefaultGroupName $ManagementPlaneGroupName `
                -ConfigKey "ManagementPlaneDelegationGroupId" `
                -logPrefix $logPrefix
            $SkipManagementPlaneDelegation = $true

            # Remove per-service ControlPlane, ManagementPlane, CatalogPlane groups from each component
            Write-Verbose "$logPrefix Removing ControlPlane/ManagementPlane/CatalogPlane from per-service groups"
            foreach ($component in $LandingZoneComponents) {
                $component.ServiceRole = @($component.ServiceRole | Where-Object {
                    -not (($_.accessLevel -eq "ControlPlane" -and $_.name -eq "Admins") -or
                          ($_.accessLevel -eq "ManagementPlane" -and $_.name -eq "Admins") -or
                          ($_.accessLevel -eq "ManagementPlane" -and $_.name -eq "Members") -or
                          ($_.accessLevel -eq "CatalogPlane" -and $_.name -eq "Members"))
                })
            }
        } else {
            Write-Verbose "$logPrefix PerService governance model - creating per-service admin groups"
            
            if (-not [string]::IsNullOrWhiteSpace($ControlPlaneDelegationGroupId)) {
                $ControlPlaneDelegationGroupId = Resolve-EntraOpsServiceEMDelegationGroup `
                    -Plane "ControlPlane" `
                    -GroupId $ControlPlaneDelegationGroupId `
                    -DefaultGroupName $ControlPlaneGroupName `
                    -ConfigKey "ControlPlaneDelegationGroupId" `
                    -logPrefix $logPrefix
                $SkipControlPlaneDelegation = $true
            }

            if (-not [string]::IsNullOrWhiteSpace($ManagementPlaneDelegationGroupId)) {
                $ManagementPlaneDelegationGroupId = Resolve-EntraOpsServiceEMDelegationGroup `
                    -Plane "ManagementPlane" `
                    -GroupId $ManagementPlaneDelegationGroupId `
                    -DefaultGroupName $ManagementPlaneGroupName `
                    -ConfigKey "ManagementPlaneDelegationGroupId" `
                    -logPrefix $logPrefix
                $SkipManagementPlaneDelegation = $true
            }
        }
    }

    process {
        Write-Verbose "$logPrefix Processing LZ"

        foreach($role in $LandingZoneComponents){
            Write-Verbose "$logPrefix Processing LZ Role: $($role.Role)"
            $report|Add-Member -MemberType NoteProperty -Name $role.Role -Value @{}
            foreach($component in $role.Components){
                Write-Verbose "$logPrefix Processing LZ Components: $($component)"
                $report.$($role.Role)|Add-Member -MemberType NoteProperty -Name $component -Value @{}
                $splatServiceBootstrap = @{
                    ServiceName                      = $component
                    ServiceMembers                   = $ServiceMembers
                    ServiceOwner                     = $ServiceOwner
                    OwnerIsNotMember                 = $OwnerIsNotMember
                    ProhibitDirectElevation          = $ProhibitDirectElevation
                    AzureRegion                      = $AzureRegion
                    ServiceRoles                     = $role.ServiceRole
                    SkipControlPlaneDelegation       = $SkipControlPlaneDelegation
                    SkipManagementPlaneDelegation    = $SkipManagementPlaneDelegation
                    ControlPlaneDelegationGroupId    = $ControlPlaneDelegationGroupId
                    ManagementPlaneDelegationGroupId = $ManagementPlaneDelegationGroupId
                    AdministratorGroupId             = $AdministratorGroupId
                }
                $report.$($role.Role).$component = New-EntraOpsServiceBootstrap @splatServiceBootstrap
            }
        }

        return $report
    }
}
