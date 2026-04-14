<#
.SYNOPSIS
    Creates a two-tier (Sub + Rg split) EAM authorization structure for an Azure subscription.

.DESCRIPTION
    Provisions EAM groups, Entitlement Management catalogs, access packages,
    PIM policies, and Azure resource groups across two separate service scopes:

    Sub scope — subscription-level governance groups:
      SG-<Prefix>-Sub-Members              (Microsoft 365 group)
      SG-<Prefix>-Sub-CatalogPlane-Members
      SG-<Prefix>-Sub-ManagementPlane-Members
      SG-<Prefix>-Sub-ControlPlane-Admins  (PIM eligible: Azure User Access Administrator)

    Rg scope — resource group-level workload groups:
      SG-<Prefix>-Rg-Members               (Microsoft 365 group)
      SG-<Prefix>-Rg-CatalogPlane-Members
      SG-<Prefix>-Rg-ManagementPlane-Members
      SG-<Prefix>-Rg-WorkloadPlane-Users
      SG-<Prefix>-Rg-WorkloadPlane-Admins  (PIM eligible: Azure Contributor on RG)

    Use this variant when subscription-level access (e.g. Azure Policy, Cost
    Management, UAA delegation) must be separated from resource-group-level
    workload access. Use New-EntraOpsSubscriptionLandingZoneAlt for a single-scope
    flat structure without the Sub/Rg distinction.

    Delegation and governance model behaviour:
    - When GovernanceModel = "Centralized" (default), ControlPlane-Admins and
      ManagementPlane-Admins are resolved to tenant-wide shared groups via
      Resolve-EntraOpsServiceEMDelegationGroup for both Sub and Rg scopes.
    - Delegation group IDs are read from EntraOpsConfig.ServiceEM when not
      passed as parameters.

.PARAMETER ServiceMembers
    UPN(s) of users to add as initial WorkloadPlane-Members in both scopes.
    Defaults to the signed-in identity.

.PARAMETER ServiceOwner
    UPN of the service owner (sets group ownership in both scopes). Defaults
    to the signed-in identity.

.PARAMETER OwnerIsNotMember
    When set, the owner is not automatically added as a WorkloadPlane member.

.PARAMETER ProhibitDirectElevation
    When set, skips PIM policy configuration and PIM eligible assignment creation

.PARAMETER EnablePIMOwnerAssignment
    When set, creates PIM for Groups eligible-owner assignments for the service owner
    in addition to the default eligible-member assignments for the Members group.
    Disabled by default — use this switch to opt in.
    for all groups in both scopes.

.PARAMETER SkipAzureResourceGroup
    When set, no Azure resource groups are created for either scope.

.PARAMETER AzureRegion
    Azure region for resource groups (e.g. "westeurope"). Required unless
    -SkipAzureResourceGroup is set.

.PARAMETER DeploymentPrefix
    Prefix used in all group DisplayNames and catalog names. Defaults to
    "Default". Use the subscription or workload name
    (e.g. "Sub-Management", "Sub-Connectivity").

.PARAMETER SkipControlPlaneDelegation
    Skips creation of per-service ControlPlane-Admins groups and their Catalog
    Owner / Azure UAA PIM eligible assignments for both scopes. Applied
    automatically when ControlPlaneDelegationGroupId is provided or when
    GovernanceModel is Centralized.

.PARAMETER SkipManagementPlaneDelegation
    Skips creation of per-service ManagementPlane-Admins groups and their
    entitlement/Azure delegation for both scopes. Applied automatically when
    ManagementPlaneDelegationGroupId is provided or when GovernanceModel is
    Centralized.

.PARAMETER ControlPlaneDelegationGroupId
    Object ID of an existing Entra group to use as ControlPlane-Admins across
    both scopes instead of creating per-scope groups. Receives the Catalog Owner
    role and a PIM eligible User Access Administrator assignment.
    Falls back to EntraOpsConfig.ServiceEM.ControlPlaneDelegationGroupId.

.PARAMETER ManagementPlaneDelegationGroupId
    Object ID of an existing Entra group to use as ManagementPlane-Admins across
    both scopes. Receives the AP Assignment Manager catalog role, approver role
    in access package policies, and a PIM eligible Contributor role.
    Falls back to EntraOpsConfig.ServiceEM.ManagementPlaneDelegationGroupId.

.PARAMETER AdministratorGroupId
    Object ID of an existing Entra group to use as CatalogPlane-Members across
    both scopes. Controls who can request elevated access packages and who reviews
    expiring assignments. Falls back to EntraOpsConfig.ServiceEM.AdministratorGroupId.

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
    Custom landing zone scope definitions. Each entry must have a Role name
    ("Sub", "Rg", or any custom label) and a ServiceRole array. Defaults to
    the standard Sub + Rg split structure.

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsSubscriptionLandingZone -DeploymentPrefix "Sub-Management" `
        -AzureRegion "westeurope" `
        -ServiceOwner "owner@contoso.com" `
        -ServiceMembers @("alice@contoso.com", "bob@contoso.com")

    Creates the full Sub + Rg EAM structure for "Sub-Management" with resource
    groups in West Europe. Delegation groups are resolved from EntraOpsConfig or
    auto-created (Centralized governance model default).

.EXAMPLE
    New-EntraOpsSubscriptionLandingZone -DeploymentPrefix "Sub-Connectivity" `
        -AzureRegion "northeurope" `
        -ControlPlaneDelegationGroupId "00000000-0000-0000-0000-000000000001" `
        -ManagementPlaneDelegationGroupId "00000000-0000-0000-0000-000000000002" `
        -AdministratorGroupId "00000000-0000-0000-0000-000000000003"

    Creates the Sub + Rg landing zone reusing explicit tenant-wide delegation
    groups for ControlPlane-Admins, ManagementPlane-Admins, and CatalogPlane-Members
    across both scopes.

.EXAMPLE
    New-EntraOpsSubscriptionLandingZone -DeploymentPrefix "Sub-Dev" `
        -SkipAzureResourceGroup -ProhibitDirectElevation

    Creates all Entra ID groups, EM catalogs, and access packages for both Sub and
    Rg scopes without Azure resource groups and without PIM. Useful for development
    environments or Entra-only access structures.

.EXAMPLE
    $CustomComponents = @(
        [pscustomobject]@{
            Role = "Sub"
            ServiceRole = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
                [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
                [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
            )
        },
        [pscustomobject]@{
            Role = "Rg"
            ServiceRole = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
                [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Admins"; groupType = ""}
            )
        }
    )
    New-EntraOpsSubscriptionLandingZone -DeploymentPrefix "Sub-Shared" `
        -AzureRegion "westeurope" -LandingZoneComponents $CustomComponents

    Creates a reduced Sub + Rg landing zone for "Sub-Shared" with only the
    essential governance groups and no ManagementPlane separation.

#>
function New-EntraOpsSubscriptionLandingZone {
    [OutputType([System.String])]
    [cmdletbinding()]
    param(
        [string[]]$ServiceMembers,

        [string]$ServiceOwner,

        [switch]$OwnerIsNotMember,

        [switch]$ProhibitDirectElevation,

        [switch]$EnablePIMOwnerAssignment,

        [switch]$SkipAzureResourceGroup,

        [switch]$SkipControlPlaneDelegation,

        [switch]$SkipManagementPlaneDelegation,

        [string]$AzureRegion,

        [string]$DeploymentPrefix = "Default",

        [switch]$Smb,

        [string]$ControlPlaneDelegationGroupId = "",

        [string]$ManagementPlaneDelegationGroupId = "",

        [string]$AdministratorGroupId = "",

        [string]$ControlPlaneGroupName = "PRG-Tenant-ControlPlane-IdentityOps",

        [string]$ManagementPlaneGroupName = "PRG-Tenant-ManagementPlane-PlatformOps",

        [pscustomobject[]]$LandingZoneComponents = @(
            [pscustomobject]@{
                Role = "Sub"
                ServiceRole = @(
                    [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
                    [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
                )
            },
            [pscustomobject]@{
                Role = "Rg"
                ServiceRole = @(
                    [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
                    [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
                    [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""},
                    [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Admins"; groupType = ""}
                )
            }
        ),
        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        $report = @()

        if (-not $SkipAzureResourceGroup -and [string]::IsNullOrWhiteSpace($AzureRegion)) {
            throw "Parameter -AzureRegion is required unless -SkipAzureResourceGroup is specified."
        }

        # Read delegation Group IDs from EntraOpsConfig when not supplied as parameters.
        # A non-empty config value also auto-activates the corresponding skip flag.
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
        # Searches by config ID, then by default group name, then creates if permissions allow.
        # Read group names from config if available.
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
            # Centralized model: Use tenant-wide delegation groups
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

            # Remove per-service ControlPlane, ManagementPlane, CatalogPlane groups from ServiceRoles
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
            # PerService model: Keep per-service groups, but still resolve delegation if IDs provided
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

        # Add ManagementPlane-Admins to the appropriate component unless it is being delegated.
        if (-not $SkipManagementPlaneDelegation) {
            if ($smb) {
                $i = [array]::IndexOf($LandingZoneComponents.Role, "Rg")
                $LandingZoneComponents[$i].ServiceRole += [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Admins"; groupType = ""}
            } else {
                $i = [array]::IndexOf($LandingZoneComponents.Role, "Sub")
                $LandingZoneComponents[$i].ServiceRole += [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Admins"; groupType = ""}
            }
        }

        if ($SkipControlPlaneDelegation) {
            Write-Verbose "$logPrefix Removing ControlPlane components from Sub ServiceRoles"
            $i = [array]::IndexOf($LandingZoneComponents.Role, "Sub")
            $LandingZoneComponents[$i].ServiceRole = $LandingZoneComponents[$i].ServiceRole |
                Where-Object { $_.accessLevel -ne "ControlPlane" }
        }
    }

    process {
        Write-Verbose "$logPrefix Processing LZ"

        foreach ($component in $LandingZoneComponents) {
            Write-Verbose "$logPrefix Processing LZ Role: $($component.Role)"

            $splatServiceBootstrap = @{
                ServiceName                      = $component.Role + "-" + $DeploymentPrefix
                OwnerIsNotMember                 = $OwnerIsNotMember
                ProhibitDirectElevation          = $ProhibitDirectElevation
                EnablePIMOwnerAssignment         = $EnablePIMOwnerAssignment
                AzureRegion                      = $AzureRegion
                ServiceRoles                     = $component.ServiceRole
                SkipControlPlaneDelegation       = $SkipControlPlaneDelegation
                SkipManagementPlaneDelegation    = $SkipManagementPlaneDelegation
                ControlPlaneDelegationGroupId    = $ControlPlaneDelegationGroupId
                ManagementPlaneDelegationGroupId = $ManagementPlaneDelegationGroupId
                AdministratorGroupId             = $AdministratorGroupId
            }
            if ($component.Role -eq "Sub") {
                $splatServiceBootstrap += @{
                    SkipAzureResourceGroup = $true
                }
            } else {
                $splatServiceBootstrap += @{
                    SkipAzureResourceGroup = $SkipAzureResourceGroup
                }
            }
            # Forward ServiceOwner and ServiceMembers to every component so that all
            # scopes (Sub, Rg, etc.) use the same owner and member list rather than
            # defaulting to the calling account for non-Sub components.
            if ($PSBoundParameters.ContainsKey('ServiceOwner')) {
                $splatServiceBootstrap.ServiceOwner = $ServiceOwner
            }
            if ($PSBoundParameters.ContainsKey('ServiceMembers')) {
                $splatServiceBootstrap.ServiceMembers = $ServiceMembers
            }
            $report += New-EntraOpsServiceBootstrap @splatServiceBootstrap
        }

        return $report
    }
}
