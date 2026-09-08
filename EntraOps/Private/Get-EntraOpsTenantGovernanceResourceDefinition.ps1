<#
.SYNOPSIS
    Returns the supported Microsoft Entra resource types and their required Microsoft Graph read
    permissions for the EntraOps Tenant Governance Snapshot feature.

.DESCRIPTION
    Central definition used by the TenantGovernance cmdlets (Get-EntraOpsTenantGovernanceSnapshot,
    Save-EntraOpsTenantGovernanceSnapshotJson) and by New-EntraOpsWorkloadIdentity to configure the
    permissions of the first-party "Microsoft Tenant Configuration Management" (UTCM/TCM) service
    principal.

    Reference: https://learn.microsoft.com/en-us/graph/utcm-entra-resources
#>
function Get-EntraOpsTenantGovernanceResourceDefinition {
    [CmdletBinding()]
    param()

    # All Microsoft Entra resource types currently supported by Tenant Configuration Management (UTCM).
    $AvailableResources = @(
        "microsoft.entra.administrativeUnit",
        "microsoft.entra.application",
        "microsoft.entra.authenticationContextClassReference",
        "microsoft.entra.authenticationMethodPolicy",
        "microsoft.entra.authenticationMethodPolicyAuthenticator",
        "microsoft.entra.authenticationMethodPolicyEmail",
        "microsoft.entra.authenticationMethodPolicyFido2",
        "microsoft.entra.authenticationMethodPolicySms",
        "microsoft.entra.authenticationMethodPolicySoftware",
        "microsoft.entra.authenticationMethodPolicyTemporary",
        "microsoft.entra.authenticationMethodPolicyVoice",
        "microsoft.entra.authenticationMethodPolicyX509",
        "microsoft.entra.authenticationStrengthPolicy",
        "microsoft.entra.authorizationPolicy",
        "microsoft.entra.conditionalAccessPolicy",
        "microsoft.entra.crossTenantAccessPolicy",
        "microsoft.entra.crossTenantAccessPolicyConfigurationDefault",
        "microsoft.entra.crossTenantAccessPolicyConfigurationPartner",
        "microsoft.entra.entitlementManagementAccessPackage",
        "microsoft.entra.entitlementManagementAccessPackageAssignmentPolicy",
        "microsoft.entra.entitlementManagementAccessPackageCatalog",
        "microsoft.entra.entitlementManagementAccessPackageCatalogResource",
        "microsoft.entra.entitlementManagementConnectedOrganization",
        "microsoft.entra.externalIdentityPolicy",
        "microsoft.entra.group",
        "microsoft.entra.groupLifecyclePolicy",
        "microsoft.entra.namedLocationPolicy",
        "microsoft.entra.roleDefinition",
        "microsoft.entra.roleEligibilityScheduleRequest",
        "microsoft.entra.roleSetting",
        "microsoft.entra.securityDefaults",
        "microsoft.entra.servicePrincipal",
        "microsoft.entra.socialIdentityProvider",
        "microsoft.entra.tenantDetails",
        "microsoft.entra.tokenLifetimePolicy",
        "microsoft.entra.user"
    )

    # Least-privileged Microsoft Graph *read* application permissions required by the first-party
    # "Microsoft Tenant Configuration Management" (UTCM/TCM) service principal to capture each
    # resource type in a snapshot. Used by New-EntraOpsWorkloadIdentity to grant only the
    # permissions needed for the resources configured in TenantGovernanceSnapshot.ResourcesToInclude.
    $ResourcePermissions = [ordered]@{
        "microsoft.entra.administrativeUnit"                                 = @("AdministrativeUnit.Read.All", "RoleManagement.Read.Directory")
        "microsoft.entra.application"                                        = @("Application.Read.All", "Policy.Read.All")
        "microsoft.entra.authenticationContextClassReference"                = @("Policy.Read.ConditionalAccess")
        "microsoft.entra.authenticationMethodPolicy"                         = @("Policy.Read.AuthenticationMethod")
        "microsoft.entra.authenticationMethodPolicyAuthenticator"            = @("Policy.Read.AuthenticationMethod", "Group.Read.All")
        "microsoft.entra.authenticationMethodPolicyEmail"                    = @("Policy.Read.AuthenticationMethod", "Group.Read.All")
        "microsoft.entra.authenticationMethodPolicyFido2"                    = @("Policy.Read.AuthenticationMethod", "Group.Read.All")
        "microsoft.entra.authenticationMethodPolicySms"                      = @("Policy.Read.AuthenticationMethod", "Group.Read.All")
        "microsoft.entra.authenticationMethodPolicySoftware"                 = @("Policy.Read.AuthenticationMethod", "Group.Read.All")
        "microsoft.entra.authenticationMethodPolicyTemporary"                = @("Policy.Read.AuthenticationMethod", "Group.Read.All")
        "microsoft.entra.authenticationMethodPolicyVoice"                    = @("Policy.Read.AuthenticationMethod", "Group.Read.All")
        "microsoft.entra.authenticationMethodPolicyX509"                     = @("Policy.Read.AuthenticationMethod", "Group.Read.All")
        "microsoft.entra.authenticationStrengthPolicy"                       = @("Policy.Read.AuthenticationMethod")
        "microsoft.entra.authorizationPolicy"                                = @("Policy.Read.All")
        "microsoft.entra.conditionalAccessPolicy"                            = @("Agreement.Read.All", "Application.Read.All", "Group.Read.All", "Policy.Read.All", "RoleManagement.Read.Directory", "User.Read.All", "CustomSecAttributeDefinition.Read.All")
        "microsoft.entra.crossTenantAccessPolicy"                            = @("Policy.Read.All")
        "microsoft.entra.crossTenantAccessPolicyConfigurationDefault"        = @("Policy.Read.All")
        "microsoft.entra.crossTenantAccessPolicyConfigurationPartner"        = @("Policy.Read.All")
        "microsoft.entra.entitlementManagementAccessPackage"                 = @("EntitlementManagement.Read.All")
        "microsoft.entra.entitlementManagementAccessPackageAssignmentPolicy" = @("EntitlementManagement.Read.All")
        "microsoft.entra.entitlementManagementAccessPackageCatalog"          = @("EntitlementManagement.Read.All")
        "microsoft.entra.entitlementManagementAccessPackageCatalogResource"  = @("EntitlementManagement.Read.All")
        "microsoft.entra.entitlementManagementConnectedOrganization"        = @("EntitlementManagement.Read.All")
        "microsoft.entra.externalIdentityPolicy"                            = @("Policy.Read.All")
        "microsoft.entra.group"                                             = @("Application.Read.All", "Device.Read.All", "Directory.Read.All", "Group.Read.All", "ReportSettings.Read.All")
        "microsoft.entra.groupLifecyclePolicy"                              = @("Directory.Read.All")
        "microsoft.entra.namedLocationPolicy"                               = @("Policy.Read.All")
        "microsoft.entra.roleDefinition"                                    = @("RoleManagement.Read.Directory")
        "microsoft.entra.roleEligibilityScheduleRequest"                    = @("RoleEligibilitySchedule.Read.Directory", "Directory.Read.All")
        "microsoft.entra.roleSetting"                                       = @("Group.Read.All", "RoleManagement.Read.Directory", "User.Read.All", "RoleManagementPolicy.Read.Directory")
        "microsoft.entra.securityDefaults"                                  = @("Policy.Read.All")
        "microsoft.entra.servicePrincipal"                                  = @("Application.Read.All", "Group.Read.All", "User.Read.All")
        "microsoft.entra.socialIdentityProvider"                            = @("IdentityProvider.Read.All")
        "microsoft.entra.tenantDetails"                                     = @("Organization.Read.All")
        "microsoft.entra.tokenLifetimePolicy"                               = @("Policy.Read.All")
        "microsoft.entra.user"                                              = @("RoleManagement.Read.Directory", "User.Read.All")

        # Microsoft Intune resource types (reference: https://learn.microsoft.com/en-us/graph/utcm-intune-resources)
        "microsoft.intune.accountProtectionLocalUserGroupMembershipPolicy"                    = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceCategory"                                                      = @("DeviceManagementManagedDevices.Read.All")
        "microsoft.intune.deviceCompliancePolicyAndroid"                                        = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceCompliancePolicyAndroidDeviceOwner"                             = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceCompliancePolicyAndroidWorkProfile"                             = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceCompliancePolicyIos"                                            = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceCompliancePolicyMacos"                                          = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceCompliancePolicyWindows10"                                      = @("Group.Read.All", "DeviceManagementConfiguration.Read.All", "DeviceManagementScripts.Read.All")
        "microsoft.intune.deviceConfigurationDefenderForEndpointOnboardingPolicyWindows10"      = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceConfigurationDomainJoinPolicyWindows10"                         = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceConfigurationIdentityProtectionPolicyWindows10"                 = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceConfigurationImportedPfxCertificatePolicyWindows10"              = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceConfigurationPkcsCertificatePolicyWindows10"                    = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceConfigurationPolicyMacos"                                       = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceConfigurationScepCertificatePolicyWindows10"                    = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceConfigurationTrustedCertificatePolicyWindows10"                 = @("Group.Read.All", "DeviceManagementConfiguration.Read.All")
        "microsoft.intune.deviceEnrollmentLimitRestriction"                                     = @("DeviceManagementServiceConfig.Read.All")
        "microsoft.intune.deviceEnrollmentPlatformRestriction"                                  = @("Group.Read.All", "DeviceManagementServiceConfig.Read.All")

        # Microsoft Security and Compliance resource types (reference: https://learn.microsoft.com/en-us/graph/utcm-securityandcompliance-resources).
        # These resources are backed by the Office 365 Exchange Online API rather than Microsoft Graph,
        # and require the "Exchange.ManageAsApp" application permission granted on the Office 365
        # Exchange Online resource service principal (AppId 00000002-0000-0ff1-ce00-000000000000).
        "microsoft.securityandcompliance.deviceConditionalAccessPolicy" = @("Exchange.ManageAsApp")
        "microsoft.securityandcompliance.deviceConfigurationPolicy"    = @("Exchange.ManageAsApp")
    }

    # Default identity, access, Intune and compliance resources for tenant governance reporting.
    $DefaultResources = @(
        "microsoft.entra.administrativeUnit",
        "microsoft.entra.authenticationContextClassReference",
        "microsoft.entra.authenticationMethodPolicy",
        "microsoft.entra.authenticationMethodPolicyAuthenticator",
        "microsoft.entra.authenticationMethodPolicyEmail",
        "microsoft.entra.authenticationMethodPolicyFido2",
        "microsoft.entra.authenticationMethodPolicySms",
        "microsoft.entra.authenticationMethodPolicySoftware",
        "microsoft.entra.authenticationMethodPolicyTemporary",
        "microsoft.entra.authenticationMethodPolicyVoice",
        "microsoft.entra.authenticationMethodPolicyX509",
        "microsoft.entra.authenticationStrengthPolicy",
        "microsoft.entra.authorizationPolicy",
        "microsoft.entra.conditionalAccessPolicy",
        "microsoft.entra.crossTenantAccessPolicy",
        "microsoft.entra.crossTenantAccessPolicyConfigurationDefault",
        "microsoft.entra.crossTenantAccessPolicyConfigurationPartner",
        "microsoft.entra.entitlementManagementAccessPackageAssignmentPolicy",
        "microsoft.entra.entitlementManagementConnectedOrganization",
        "microsoft.entra.externalIdentityPolicy",
        "microsoft.entra.groupLifecyclePolicy",
        "microsoft.entra.namedLocationPolicy",
        "microsoft.entra.roleDefinition",
        "microsoft.entra.roleEligibilityScheduleRequest",
        "microsoft.entra.roleSetting",
        "microsoft.entra.securityDefaults",
        "microsoft.entra.socialIdentityProvider",
        "microsoft.entra.tenantDetails",
        "microsoft.entra.tokenLifetimePolicy",
        "microsoft.intune.accountProtectionLocalUserGroupMembershipPolicy",
        "microsoft.intune.deviceCategory",
        "microsoft.intune.deviceCompliancePolicyAndroid",
        "microsoft.intune.deviceCompliancePolicyAndroidDeviceOwner",
        "microsoft.intune.deviceCompliancePolicyAndroidWorkProfile",
        "microsoft.intune.deviceCompliancePolicyIos",
        "microsoft.intune.deviceCompliancePolicyMacos",
        "microsoft.intune.deviceCompliancePolicyWindows10",
        "microsoft.intune.deviceConfigurationDefenderForEndpointOnboardingPolicyWindows10",
        "microsoft.intune.deviceConfigurationDomainJoinPolicyWindows10",
        "microsoft.intune.deviceConfigurationIdentityProtectionPolicyWindows10",
        "microsoft.intune.deviceConfigurationImportedPfxCertificatePolicyWindows10",
        "microsoft.intune.deviceConfigurationPkcsCertificatePolicyWindows10",
        "microsoft.intune.deviceConfigurationPolicyMacos",
        "microsoft.intune.deviceConfigurationScepCertificatePolicyWindows10",
        "microsoft.intune.deviceConfigurationTrustedCertificatePolicyWindows10",
        "microsoft.intune.deviceEnrollmentLimitRestriction",
        "microsoft.intune.deviceEnrollmentPlatformRestriction"
        # NOTE: microsoft.securityandcompliance.* resource types are deliberately NOT part of the default set.
        # They require "Exchange.ManageAsApp", which is not a read permission - it allows running Exchange
        # Online PowerShell as an app and, combined with an Exchange-capable directory role, amounts to
        # tenant-wide mail/compliance management. They remain in $AvailableResources so they can be enabled
        # explicitly via ResourcesToInclude by an operator who accepts that grant.
    )

    return [PSCustomObject]@{
        AvailableResources  = $AvailableResources
        DefaultResources    = $DefaultResources
        ResourcePermissions = $ResourcePermissions
    }
}
