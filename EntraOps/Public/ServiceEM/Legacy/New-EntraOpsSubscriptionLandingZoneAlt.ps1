<#
.SYNOPSIS
    Creates a flat (single-scope) EAM authorization structure for an Azure subscription.

.DESCRIPTION
    Provisions all EAM groups, an Entitlement Management catalog, access packages,
    PIM policies, and an Azure resource group for a single subscription — all roles
    are created at one level with no Sub/Rg split (use New-EntraOpsSubscriptionLandingZone
    for the two-tier Sub + Rg variant).

    The default LandingZoneComponents create the following groups under the
    DeploymentPrefix service name:

      SG-<Prefix>-Members              (Microsoft 365 group — workload team channel)
      SG-<Prefix>-CatalogPlane-Members (controls who requests elevated packages)
      SG-<Prefix>-ManagementPlane-Members
      SG-<Prefix>-ManagementPlane-Admins  (PIM eligible: Azure Contributor)
      SG-<Prefix>-WorkloadPlane-Users
      SG-<Prefix>-WorkloadPlane-Members
      SG-<Prefix>-WorkloadPlane-Admins    (PIM eligible: subscription-scoped)
      SG-<Prefix>-ControlPlane-Admins     (PIM eligible: Azure User Access Administrator)

    Delegation and governance model behaviour:
    - When GovernanceModel = "Centralized" (default), ControlPlane-Admins and
      ManagementPlane-Admins are resolved to tenant-wide shared groups via
      Resolve-EntraOpsServiceEMDelegationGroup. Per-service ControlPlane,
      ManagementPlane-Admins, ManagementPlane-Members, and CatalogPlane-Members
      groups are removed from LandingZoneComponents automatically.
    - When GovernanceModel = "PerService", per-service admin groups are created
      unless explicit delegation group IDs are provided.
    - Delegation group IDs are read from EntraOpsConfig.ServiceEM when not passed
      as parameters.

.PARAMETER ServiceMembers
    UPN(s) of users to add as initial WorkloadPlane-Members. Defaults to the
    signed-in identity.

.PARAMETER ServiceOwner
    UPN of the service owner (sets group ownership). Defaults to the signed-in
    identity.

.PARAMETER OwnerIsNotMember
    When set, the owner is not automatically added as a WorkloadPlane member.

.PARAMETER ProhibitDirectElevation
    When set, skips PIM policy configuration and PIM eligible assignment creation
    for all groups.

.PARAMETER SkipAzureResourceGroup
    When set, no Azure resource group is created.

.PARAMETER AzureRegion
    Azure region for the resource group (e.g. "westeurope"). Required unless
    -SkipAzureResourceGroup is set.

.PARAMETER DeploymentPrefix
    Prefix used in all group DisplayNames and the catalog name. Defaults to
    "Default". Use the subscription or workload name (e.g. "Sub-Production").

.PARAMETER SkipControlPlaneDelegation
    Skips creation of a per-service ControlPlane-Admins group and its Catalog
    Owner / Azure UAA PIM eligible assignment. Applied automatically when
    ControlPlaneDelegationGroupId is provided or when GovernanceModel is
    Centralized.

.PARAMETER SkipManagementPlaneDelegation
    Skips creation of a per-service ManagementPlane-Admins group and its
    entitlement/Azure delegation. Applied automatically when
    ManagementPlaneDelegationGroupId is provided or when GovernanceModel is
    Centralized.

.PARAMETER ControlPlaneDelegationGroupId
    Object ID of an existing Entra group to use as ControlPlane-Admins instead
    of creating a new per-service group. The group receives the Catalog Owner
    role and a PIM eligible User Access Administrator assignment on the resource
    group. Falls back to EntraOpsConfig.ServiceEM.ControlPlaneDelegationGroupId.

.PARAMETER ManagementPlaneDelegationGroupId
    Object ID of an existing Entra group to use as ManagementPlane-Admins.
    Receives the AP Assignment Manager catalog role, approver role in access
    package policies, and a PIM eligible Contributor role on the resource group.
    Falls back to EntraOpsConfig.ServiceEM.ManagementPlaneDelegationGroupId.

.PARAMETER AdministratorGroupId
    Object ID of an existing Entra group to use as CatalogPlane-Members.
    Controls who can request elevated access packages and who reviews expiring
    assignments. Falls back to EntraOpsConfig.ServiceEM.AdministratorGroupId.

.PARAMETER ControlPlaneGroupName
    Display name of the tenant-wide ControlPlane delegation group to look up or
    create when GovernanceModel is Centralized. Defaults to
    "PRG-Tenant-ControlPlane-IdentityOps". Overridden by
    EntraOpsConfig.ServiceEM.ControlPlaneGroupName.

.PARAMETER ManagementPlaneGroupName
    Display name of the tenant-wide ManagementPlane delegation group to look up
    or create when GovernanceModel is Centralized. Defaults to
    "PRG-Tenant-ManagementPlane-PlatformOps". Overridden by
    EntraOpsConfig.ServiceEM.ManagementPlaneGroupName.

.PARAMETER LandingZoneComponents
    Custom service role definitions as an array of PSCustomObjects with
    accessLevel, name, and groupType columns. Defaults to the full flat Alt
    structure (all roles at subscription scope). Use this to reduce the role set
    for simpler workloads.

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsSubscriptionLandingZoneAlt -DeploymentPrefix "Sub-Production" `
        -AzureRegion "westeurope" `
        -ServiceOwner "owner@contoso.com" `
        -ServiceMembers @("alice@contoso.com", "bob@contoso.com")

    Creates the full flat EAM structure for "Sub-Production" with an Azure resource
    group in West Europe. Delegation groups are resolved from EntraOpsConfig or
    auto-created (Centralized governance model default).

.EXAMPLE
    New-EntraOpsSubscriptionLandingZoneAlt -DeploymentPrefix "Sub-Production" `
        -AzureRegion "westeurope" `
        -ControlPlaneDelegationGroupId "00000000-0000-0000-0000-000000000001" `
        -ManagementPlaneDelegationGroupId "00000000-0000-0000-0000-000000000002" `
        -AdministratorGroupId "00000000-0000-0000-0000-000000000003"

    Creates the flat landing zone reusing explicit tenant-wide delegation groups
    for all three administrative planes instead of creating per-service groups.

.EXAMPLE
    New-EntraOpsSubscriptionLandingZoneAlt -DeploymentPrefix "Sub-Dev" `
        -SkipAzureResourceGroup -ProhibitDirectElevation

    Creates all Entra ID groups, EM catalog, and access packages for "Sub-Dev"
    without an Azure resource group and without PIM configuration. Useful for
    dev/test landing zones or Entra-only workloads.

.EXAMPLE
    $CustomRoles = @(
        [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
        [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Members"; groupType = ""},
        [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Admins"; groupType = ""}
    )
    New-EntraOpsSubscriptionLandingZoneAlt -DeploymentPrefix "Sub-Shared" `
        -AzureRegion "northeurope" -LandingZoneComponents $CustomRoles

    Creates a reduced flat landing zone for "Sub-Shared" with only WorkloadPlane
    groups — no ManagementPlane or ControlPlane separation.

#>
function New-EntraOpsSubscriptionLandingZoneAlt {
    [OutputType([System.String])]
    [cmdletbinding()]
    param(
        [string[]]$ServiceMembers,

        [string]$ServiceOwner,

        [switch]$OwnerIsNotMember,

        [switch]$ProhibitDirectElevation,

        [switch]$SkipControlPlaneDelegation,

        [switch]$SkipManagementPlaneDelegation,

        [switch]$SkipAzureResourceGroup,

        [string]$AzureRegion,

        [string]$DeploymentPrefix = "Default",

        [switch]$Smb,

        [string]$ControlPlaneDelegationGroupId = "",

        [string]$ManagementPlaneDelegationGroupId = "",

        [string]$AdministratorGroupId = "",

        [string]$ControlPlaneGroupName = "PRG-Tenant-ControlPlane-IdentityOps",

        [string]$ManagementPlaneGroupName = "PRG-Tenant-ManagementPlane-PlatformOps",

        [pscustomobject[]]$LandingZoneComponents = @(
            [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Admins"; groupType = ""},
            [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
            [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Admins"; groupType = ""},
            [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Members"; groupType = ""},
            [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""},
            [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
            [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
            [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""}
        ),

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        $report = @()
    }

    process {

        if (-not $SkipAzureResourceGroup -and [string]::IsNullOrWhiteSpace($AzureRegion)) {
            throw "Parameter -AzureRegion is required unless -SkipAzureResourceGroup is specified."
        }

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

            # Remove per-service ControlPlane, ManagementPlane, CatalogPlane groups
            Write-Verbose "$logPrefix Removing ControlPlane/ManagementPlane/CatalogPlane from per-service groups"
            $LandingZoneComponents = @($LandingZoneComponents | Where-Object {
                -not (($_.accessLevel -eq "ControlPlane" -and $_.name -eq "Admins") -or
                      ($_.accessLevel -eq "ManagementPlane" -and $_.name -eq "Admins") -or
                      ($_.accessLevel -eq "ManagementPlane" -and $_.name -eq "Members") -or
                      ($_.accessLevel -eq "CatalogPlane" -and $_.name -eq "Members"))
            })
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

        if ($SkipControlPlaneDelegation) {
            Write-Verbose "$logPrefix Removing ControlPlane components from LandingZoneComponents"
            $LandingZoneComponents = $LandingZoneComponents | Where-Object { $_.accessLevel -ne "ControlPlane" }
        }
        if ($SkipManagementPlaneDelegation) {
            Write-Verbose "$logPrefix Removing ManagementPlane-Admins component from LandingZoneComponents"
            $LandingZoneComponents = $LandingZoneComponents | Where-Object {
                -not ($_.name -eq "Admins" -and $_.accessLevel -eq "ManagementPlane")
            }
        }

        Write-Verbose "$logPrefix Processing LZ"

        $splatServiceBootstrap = @{
            ServiceName                      = $DeploymentPrefix
            OwnerIsNotMember                 = $OwnerIsNotMember
            ProhibitDirectElevation          = $ProhibitDirectElevation
            AzureRegion                      = $AzureRegion
            ServiceRoles                     = $LandingZoneComponents
            ServiceMembers                   = $ServiceMembers
            ServiceOwner                     = $ServiceOwner
            SkipAzureResourceGroup           = $SkipAzureResourceGroup
            SkipControlPlaneDelegation       = $SkipControlPlaneDelegation
            SkipManagementPlaneDelegation    = $SkipManagementPlaneDelegation
            ControlPlaneDelegationGroupId    = $ControlPlaneDelegationGroupId
            ManagementPlaneDelegationGroupId = $ManagementPlaneDelegationGroupId
            AdministratorGroupId             = $AdministratorGroupId
        }
        $report += New-EntraOpsServiceBootstrap @splatServiceBootstrap

        return $report
    }
}
