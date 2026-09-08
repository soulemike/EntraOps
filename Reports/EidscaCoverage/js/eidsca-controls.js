// Curated subset of EIDSCA (Entra ID Security Config Analyzer) control definitions.
// Source: https://raw.githubusercontent.com/Cloud-Architekt/AzureAD-Attack-Defense/AADSCAv4/config/EidscaConfig.json
// Retrieved: 2026-07-17
// Only the "Entra ID Tenant Configuration" category is included - the other two categories
// ("Entra Conditional Access", "Entra Workload ID") are entity-list stubs with no per-property
// checks. Within that category, only control areas whose GraphEndpoint already has a matching
// Tenant Governance Snapshot (UTCM) resource type are kept (see "covered"); the remainder are
// listed in "notCovered" purely for the coverage summary - no UTCM resource type exists for
// them today (Universal/Tenant Configuration Management resource catalog, see
// EntraOps/Private/Get-EntraOpsTenantGovernanceResourceDefinition.ps1).
// This is a fixed reference dataset, not a generated build artifact - refresh by hand from the
// source URL above if EIDSCA adds/changes controls.
window.ENTRAOPS_EIDSCA_CONTROLS = {
  "covered": [
    {
      "controlId": "EIDSCA.AP",
      "controlName": "Default Authorization Settings",
      "utcmType": "microsoft.entra.authorizationPolicy",
      "mitreTactic": [],
      "controls": [
        {
          "name": "allowedToUseSSPR",
          "displayName": "Enabled Self service password reset for administrators",
          "checkId": "EIDSCA.AP01",
          "recommendedValue": "false",
          "severity": "Informational",
          "recommendation": "Administrators with sensitive roles should use phishing-resistant authentication methods only and therefore not able to reset their password using SSPR.",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/PasswordResetMenuBlade/~/AdminPasswordResetPolicy",
          "mitreTactic": ["TA0006 - Credential Access"]
        },
        {
          "name": "blockMsolPowerShell",
          "displayName": "Blocked MSOnline PowerShell access",
          "checkId": "EIDSCA.AP02",
          "recommendedValue": "",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": "",
          "mitreTechnique": ["T1556"]
        },
        {
          "name": "enabledPreviewFeatures",
          "displayName": "Enabled preview features",
          "checkId": "EIDSCA.AP03",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot - no matching M365DSC/UTCM property exists for enabledPreviewFeatures today."
        },
        {
          "name": "allowInvitesFrom",
          "displayName": "Guest invite restrictions",
          "checkId": "EIDSCA.AP04",
          "recommendedValue": "@('adminsAndGuestInviters','none')",
          "severity": "Medium",
          "recommendation": "CISA SCuBA 2.18: Only users with the Guest Inviter role SHOULD be able to invite guest users",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AllowlistPolicyBlade",
          "mitreTactic": ["TA0003 - Persistence"]
        },
        {
          "name": "allowedToSignUpEmailBasedSubscriptions",
          "displayName": "Sign-up for email based subscription",
          "checkId": "EIDSCA.AP05",
          "recommendedValue": "false",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": "",
          "mitreTactic": ["TA0001 - Initial Access"]
        },
        {
          "name": "allowEmailVerifiedUsersToJoinOrganization",
          "displayName": "User can join the tenant by email validation",
          "checkId": "EIDSCA.AP06",
          "recommendedValue": "false",
          "severity": "Medium",
          "recommendation": "https://learn.microsoft.com/en-us/azure/active-directory/enterprise-users/directory-self-service-signup",
          "portalDeepLink": "",
          "mitreTactic": ["TA0001 - Initial Access"]
        },
        {
          "name": "guestUserRole",
          "displayName": "Guest user access",
          "checkId": "EIDSCA.AP07",
          "recommendedValue": "2af84b1e-32c8-42b7-82bc-daa82404023b",
          "severity": "",
          "recommendation": "CISA SCuBA 2.18: Guest users SHOULD have limited access to Entra ID (Azure AD) directory objects.",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AllowlistPolicyBlade",
          "mitreTactic": ["TA0043 - Reconnaissance"],
          "valueMap": {
            "user": "a0b1b346-4d3e-4e8b-98f8-753987be4970",
            "guest": "10dae51f-b6af-4016-8d66-8c2a99b929b3",
            "restrictedguest": "2af84b1e-32c8-42b7-82bc-daa82404023b"
          }
        },
        {
          "name": "permissionGrantPolicyIdsAssignedToDefaultUserRole",
          "displayName": "User consent policy assigned for applications",
          "checkId": "EIDSCA.AP08",
          "recommendedValue": "ManagePermissionGrantsForSelf.microsoft-user-default-low",
          "severity": "High",
          "recommendation": "Microsoft recommends to allow to user consent for apps from verified publisher for selected permissions. CISA SCuBA 2.7 defines that all Non-Admin Users SHALL Be Prevented From Providing Consent To Third-Party Applications.",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserManagementMenuBlade/~/UserSettings",
          "mitreTactic": ["TA0001 - Initial Access", "TA0005 - Defense Evasion", "TA0006 - Credential Access", "TA0008 - Lateral Movement"],
          "mitreTechnique": ["T1566.002", "T1078", "T1550", "T1528"],
          "mitreMitigation": ["M1017", "M1018"]
        },
        {
          "name": "allowUserConsentForRiskyApps",
          "displayName": "Allow user consent on risk-based apps",
          "checkId": "EIDSCA.AP09",
          "recommendedValue": "false",
          "severity": "High",
          "recommendation": "https://learn.microsoft.com/en-us/azure/active-directory/manage-apps/configure-risk-based-step-up-consent",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ConsentPoliciesMenuBlade/~/UserSettings",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot - no matching M365DSC/UTCM property exists for allowUserConsentForRiskyApps today.",
          "mitreTactic": ["TA0001 - Initial Access", "TA0005 - Defense Evasion", "TA0006 - Credential Access", "TA0008 - Lateral Movement"],
          "mitreTechnique": ["T1566.002", "T1078", "T1550", "T1528"],
          "mitreMitigation": ["M1017", "M1018"]
        },
        {
          "name": "defaultUserRoleAllowedToCreateApps",
          "displayName": "Default User Role Permissions - Allowed to create Apps",
          "checkId": "EIDSCA.AP10",
          "recommendedValue": "false",
          "severity": "High",
          "recommendation": "CISA SCuBA 2.6: Only Administrators SHALL Be Allowed To Register Third-Party Applications",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserManagementMenuBlade/~/UserSettings",
          "mitreTactic": ["TA0001 - Initial Access", "TA0005 - Defense Evasion", "TA0006 - Credential Access", "TA0008 - Lateral Movement"],
          "mitreTechnique": ["T1566.002", "T1078", "T1550", "T1528"],
          "mitreMitigation": ["M1017", "M1018", "M1024", "M1047"]
        },
        {
          "name": "defaultUserRoleAllowedToCreateSecurityGroups",
          "displayName": "Default User Role Permissions - Allowed to create Security Groups",
          "checkId": "EIDSCA.AP11",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/GroupsManagementMenuBlade/~/General",
          "mitreTactic": ["TA0003 - Persistence"]
        },
        {
          "name": "defaultUserRoleAllowedToCreateTenants",
          "displayName": "Default User Role Permissions - Allowed to create Tenants",
          "checkId": "EIDSCA.AP12",
          "recommendedValue": "",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserManagementMenuBlade/~/UserSettings",
          "mitreTactic": ["TA0010 - Exfiltration", "TA0040 - Impact"]
        },
        {
          "name": "defaultUserRoleAllowedToReadBitlockerKeysForOwnedDevice",
          "displayName": "Default User Role Permissions - Allowed to read BitLocker Keys for Owned Devices",
          "checkId": "EIDSCA.AP13",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "",
          "mitreTactic": ["TA0003 - Persistence"]
        },
        {
          "name": "defaultUserRoleAllowedToReadOtherUsers",
          "displayName": "Default User Role Permissions - Allowed to read other users",
          "checkId": "EIDSCA.AP14",
          "recommendedValue": "true",
          "severity": "Informational",
          "recommendation": "Restrict this default permissions for members have huge impact on collaboration features and user lookup.",
          "portalDeepLink": "",
          "mitreTactic": ["TA0043 - Reconnaissance"]
        }
      ]
    },
    {
      "controlId": "EIDSCA.EX",
      "controlName": "External Identities",
      "utcmType": "microsoft.entra.externalIdentityPolicy",
      "mitreTactic": [],
      "controls": [
        {
          "name": "allowExternalIdentitiesToLeave",
          "displayName": "External user leave settings",
          "checkId": "EIDSCA.EX01",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AllowlistPolicyBlade"
        },
        {
          "name": "allowDeletedIdentitiesDataRemoval",
          "displayName": "Deleted Identities Data Removal",
          "checkId": "EIDSCA.EX02",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": ""
        }
      ]
    },
    {
      "controlId": "EIDSCA.AG",
      "controlName": "Authentication Method - General Settings",
      "utcmType": "microsoft.entra.authenticationMethodPolicy",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "policyMigrationState",
          "displayName": "Manage migration",
          "checkId": "EIDSCA.AG01",
          "recommendedValue": "@('migrationComplete', '')",
          "severity": "Informational",
          "recommendation": "On September 30th, 2025, the legacy multifactor authentication and self-service password reset policies will be deprecated and you'll manage all authentication methods here in the authentication methods policy. Use this control to manage your migration from the legacy policies to the new unified policy.",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods"
        },
        {
          "name": "reportSuspiciousActivitySettingsState",
          "displayName": "Report suspicious activity - State",
          "checkId": "EIDSCA.AG02",
          "recommendedValue": "enabled",
          "severity": "Medium",
          "recommendation": "Allows to integrate report of fraud attempt by users to identity protection: Users who report an MFA prompt as suspicious are set to High User Risk. Administrators can use risk-based policies to limit access for these users, or enable self-service password reset (SSPR) for users to remediate problems on their own.",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AuthMethodsSettings",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot - no matching M365DSC/UTCM property exists for reportSuspiciousActivitySettings today."
        },
        {
          "name": "reportSuspiciousActivitySettingsIncluded",
          "displayName": "Report suspicious activity - Included users/groups",
          "checkId": "EIDSCA.AG03",
          "recommendedValue": "all_users",
          "severity": "High",
          "recommendation": "Apply this feature to all users.",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AuthMethodsSettings",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot - no matching M365DSC/UTCM property exists for reportSuspiciousActivitySettings today."
        },
        {
          "name": "reportSuspiciousActivitySettingsReporting code",
          "displayName": "Report suspicious activity - Reporting code",
          "checkId": "EIDSCA.AG04",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AuthMethodsSettings",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot - no matching M365DSC/UTCM property exists for reportSuspiciousActivitySettings today."
        },
        {
          "name": "systemCredentialPreferences.state",
          "displayName": "System-preferred multifactor authentication - State",
          "checkId": "EIDSCA.AG05",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AuthMethodsSettings"
        },
        {
          "name": "systemCredentialPreferences.includeTargets",
          "displayName": "System-preferred multifactor authentication - Included users/groups",
          "checkId": "EIDSCA.AG06",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AuthMethodsSettings"
        },
        {
          "name": "systemCredentialPreferences.excludeTargets",
          "displayName": "System-preferred multifactor authentication - Excluded users/groups",
          "checkId": "EIDSCA.AG07",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AuthMethodsSettings"
        },
        {
          "name": "registrationEnforcement.authenticationMethodsRegistrationCampaign.state",
          "displayName": "Registration campaign - State",
          "checkId": "EIDSCA.AG08",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/RegistrationCampaign"
        },
        {
          "name": "registrationEnforcement.authenticationMethodsRegistrationCampaign.includeTargets.id",
          "displayName": "Registration campaign - Included users/groups",
          "checkId": "EIDSCA.AG09",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/RegistrationCampaign"
        },
        {
          "name": "registrationEnforcement.authenticationMethodsRegistrationCampaign.includeTargets.targetedAuthenticationMethod",
          "displayName": "Registration campaign - Authentication Method",
          "checkId": "EIDSCA.AG10",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/RegistrationCampaign"
        },
        {
          "name": "registrationEnforcement.authenticationMethodsRegistrationCampaign.excludeTargets.id",
          "displayName": "Registration campaign - Excluded users/groups",
          "checkId": "EIDSCA.AG11",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/RegistrationCampaign"
        },
        {
          "name": "registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays",
          "displayName": "Registration campaign - Days allowed to snooze",
          "checkId": "EIDSCA.AG12",
          "recommendedValue": "",
          "severity": "Informational",
          "recommendation": "",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/RegistrationCampaign"
        }
      ]
    },
    {
      "controlId": "EIDSCA.AM",
      "controlName": "Authentication Method - Microsoft Authenticator",
      "utcmType": "microsoft.entra.authenticationMethodPolicyAuthenticator",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "state",
          "displayName": "State",
          "checkId": "EIDSCA.AM01",
          "recommendedValue": "enabled",
          "severity": "High",
          "recommendation": "enabled",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods"
        },
        {
          "name": "isSoftwareOathEnabled",
          "displayName": "Allow use of Microsoft Authenticator OTP",
          "checkId": "EIDSCA.AM02",
          "recommendedValue": "false",
          "severity": "High",
          "recommendation": "CISA MS.AAD.3.3v2 recommends disabling Microsoft Authenticator OTP. We recommend using this method only if no stronger MFA option is available, or if it is needed for specific restore scenarios. Make sure you have configured authentication strength to require stronger and phishing-resistant authentication methods, in order to enforce stronger authentication than OTP in all other scenarios.",
          "portalDeepLink": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods"
        },
        {
          "name": "featureSettings.numberMatchingRequiredState.state",
          "displayName": "Require number matching for push notifications",
          "checkId": "EIDSCA.AM03",
          "recommendedValue": "enabled",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": "",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot in every tenant - the FeatureSettings.NumberMatchingRequiredState object is only present in the captured resource once explicitly configured."
        },
        {
          "name": "featureSettings.numberMatchingRequiredState.includeTarget.id",
          "displayName": "Included users/groups of number matching for push notifications",
          "checkId": "EIDSCA.AM04",
          "recommendedValue": "all_users",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": "",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot in every tenant - the FeatureSettings.NumberMatchingRequiredState object is only present in the captured resource once explicitly configured."
        },
        {
          "name": "featureSettings.numberMatchingRequiredState.excludeTarget.id",
          "displayName": "Excluded users/groups of number matching for push notifications",
          "checkId": "EIDSCA.AM05",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": "",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot in every tenant - the FeatureSettings.NumberMatchingRequiredState object is only present in the captured resource once explicitly configured."
        },
        {
          "name": "featureSettings.displayAppInformationRequiredState.state",
          "displayName": "Show application name in push and passwordless notifications",
          "checkId": "EIDSCA.AM06",
          "recommendedValue": "enabled",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "featureSettings.displayAppInformationRequiredState.includeTarget.id",
          "displayName": "Included users/groups to show application name in push and passwordless notifications",
          "checkId": "EIDSCA.AM07",
          "recommendedValue": "all_users",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "featureSettings.displayAppInformationRequiredState.excludeTarget.id",
          "displayName": "Excluded users/groups to show application name in push and passwordless notifications",
          "checkId": "EIDSCA.AM08",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "featureSettings.displayLocationInformationRequiredState.state",
          "displayName": "Show geographic location in push and passwordless notifications",
          "checkId": "EIDSCA.AM09",
          "recommendedValue": "enabled",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "featureSettings.displayLocationInformationRequiredState.includeTarget.id",
          "displayName": "Included users/groups to show geographic location in push and passwordless notifications",
          "checkId": "EIDSCA.AM10",
          "recommendedValue": "all_users",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "featureSettings.displayLocationInformationRequiredState.excludeTarget.id",
          "displayName": "Excluded users/groups to show geographic location in push and passwordless notifications",
          "checkId": "EIDSCA.AM11",
          "recommendedValue": "",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "includeTargets",
          "displayName": "Included users/groups from using Authenticator App",
          "checkId": "EIDSCA.AM12",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "excludeTargets",
          "displayName": "Excluded users/groups from using Authenticator App",
          "checkId": "EIDSCA.AM13",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        }
      ]
    },
    {
      "controlId": "EIDSCA.AF",
      "controlName": "Authentication Method - FIDO2 security key",
      "utcmType": "microsoft.entra.authenticationMethodPolicyFido2",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "state",
          "displayName": "State",
          "checkId": "EIDSCA.AF01",
          "recommendedValue": "enabled",
          "severity": "High",
          "recommendation": "enabled",
          "portalDeepLink": ""
        },
        {
          "name": "isSelfServiceRegistrationAllowed",
          "displayName": "Allow self-service set up",
          "checkId": "EIDSCA.AF02",
          "recommendedValue": "true",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "isAttestationEnforced",
          "displayName": "Enforce attestation",
          "checkId": "EIDSCA.AF03",
          "recommendedValue": "true",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "keyRestrictions.isEnforced",
          "displayName": "Enforce key restrictions",
          "checkId": "EIDSCA.AF04",
          "recommendedValue": "true",
          "severity": "Low",
          "recommendation": "Restrict usage of FIDO2 from unauthorized vendors or platforms",
          "portalDeepLink": ""
        },
        {
          "name": "keyRestrictions.aaGuids",
          "displayName": "Restricted",
          "checkId": "EIDSCA.AF05",
          "recommendedValue": "true",
          "severity": "Low",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "keyRestrictions.enforcementType",
          "displayName": "Restrict specific keys",
          "checkId": "EIDSCA.AF06",
          "recommendedValue": "true",
          "severity": "High",
          "recommendation": "You should use Block or Allow as value to allow- or blocklisting of AAGuids.",
          "portalDeepLink": ""
        },
        {
          "name": "includeTargets",
          "displayName": "Included users/groups from using security keys",
          "checkId": "EIDSCA.AF07",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "excludeTargets",
          "displayName": "Excluded users/groups from using security keys",
          "checkId": "EIDSCA.AF08",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        }
      ]
    },
    {
      "controlId": "EIDSCA.AT",
      "controlName": "Authentication Method - Temporary Access Pass",
      "utcmType": "microsoft.entra.authenticationMethodPolicyTemporary",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "state",
          "displayName": "State",
          "checkId": "EIDSCA.AT01",
          "recommendedValue": "enabled",
          "severity": "High",
          "recommendation": "Use Temporary Access Pass for secure onboarding users (initial password replacement) and enforce MFA for registering security information in Conditional Access Policy.",
          "portalDeepLink": ""
        },
        {
          "name": "isUsableOnce",
          "displayName": "One-time",
          "checkId": "EIDSCA.AT02",
          "recommendedValue": "true",
          "severity": "Medium",
          "recommendation": "Avoid to allow reusable passes and restrict usage to one-time use (if applicable)",
          "portalDeepLink": ""
        },
        {
          "name": "defaultLifetimeInMinutes",
          "displayName": "Default lifetime",
          "checkId": "EIDSCA.AT03",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "defaultLength",
          "displayName": "Length",
          "checkId": "EIDSCA.AT04",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "minimumLifetimeInMinutes",
          "displayName": "Minimum lifetime",
          "checkId": "EIDSCA.AT05",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "maximumLifetimeInMinutes",
          "displayName": "Maximum lifetime",
          "checkId": "EIDSCA.AT06",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "includeTargets",
          "displayName": "Included users/groups from Temporary Access Pass",
          "checkId": "EIDSCA.AT07",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "excludeTargets",
          "displayName": "Excluded users/group from Temporary Access Pass",
          "checkId": "EIDSCA.AT08",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        }
      ]
    },
    {
      "controlId": "EIDSCA.AO",
      "controlName": "Authentication Method - Third-party software OATH tokens",
      "utcmType": "microsoft.entra.authenticationMethodPolicySoftware",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "state",
          "displayName": "State",
          "checkId": "EIDSCA.AO01",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "includeTargets",
          "displayName": "Included users/groups from OATH token",
          "checkId": "EIDSCA.AO02",
          "recommendedValue": "",
          "severity": "",
          "recommendation": "Medium",
          "portalDeepLink": ""
        },
        {
          "name": "excludeTargets",
          "displayName": "Excluded users/group from OATH token",
          "checkId": "EIDSCA.AO03",
          "recommendedValue": "",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": ""
        }
      ]
    },
    {
      "controlId": "EIDSCA.AE",
      "controlName": "Authentication Method - Email OTP",
      "utcmType": "microsoft.entra.authenticationMethodPolicyEmail",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "state",
          "displayName": "State",
          "checkId": "EIDSCA.AE01",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "allowExternalIdToUseEmailOtp",
          "displayName": "Allow external users to use email OTP",
          "checkId": "EIDSCA.AE02",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "includeTargets",
          "displayName": "Included users/groups from Email OTP",
          "checkId": "EIDSCA.AE03",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "excludeTargets",
          "displayName": "Excluded users/group from Email OTP",
          "checkId": "EIDSCA.AE04",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        }
      ]
    },
    {
      "controlId": "EIDSCA.AV",
      "controlName": "Authentication Method - Voice call",
      "utcmType": "microsoft.entra.authenticationMethodPolicyVoice",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "state",
          "displayName": "State",
          "checkId": "EIDSCA.AV01",
          "recommendedValue": "disabled",
          "severity": "High",
          "recommendation": "Choose authentication methods with number matching (Authenticator) ",
          "portalDeepLink": ""
        },
        {
          "name": "isOfficePhoneAllowed",
          "displayName": "Phone Options - Office",
          "checkId": "EIDSCA.AV02",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "includeTargets",
          "displayName": "Included users/groups from Voice call",
          "checkId": "EIDSCA.AV03",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "excludeTargets",
          "displayName": "Excluded users/group from Voice call",
          "checkId": "EIDSCA.AV04",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        }
      ]
    },
    {
      "controlId": "EIDSCA.AS",
      "controlName": "Authentication Method - SMS",
      "utcmType": "microsoft.entra.authenticationMethodPolicySms",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "state",
          "displayName": "State",
          "checkId": "EIDSCA.AS01",
          "recommendedValue": "",
          "severity": "",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "includeTargets",
          "displayName": "Included users/groups from SMS-based authentication",
          "checkId": "EIDSCA.AS02",
          "recommendedValue": "",
          "severity": "",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "excludeTargets",
          "displayName": "Excluded users/group from SMS-based authentication",
          "checkId": "EIDSCA.AS03",
          "recommendedValue": "",
          "severity": "",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "isUsableForSignIn",
          "displayName": "Use for sign-in",
          "checkId": "EIDSCA.AS04",
          "recommendedValue": "false",
          "severity": "High",
          "recommendation": "Avoid to use SMS as primary sign in factor (instead of a password) and consider to implement a MFA or passwordless option also for your special user groups, such as front-line workers.",
          "portalDeepLink": "",
          "notCapturedNote": "Not yet captured by the Tenant Governance Snapshot - no matching M365DSC/UTCM property exists for isUsableForSignIn today."
        }
      ]
    },
    {
      "controlId": "EIDSCA.AC",
      "controlName": "Authentication Method - Certificate-based authentication",
      "utcmType": "microsoft.entra.authenticationMethodPolicyX509",
      "mitreTactic": ["TA0006 - Credential Access"],
      "controls": [
        {
          "name": "state",
          "displayName": "State",
          "checkId": "EIDSCA.AC01",
          "recommendedValue": "",
          "severity": "High",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "includeTargets",
          "displayName": "Included users/groups from CBA",
          "checkId": "EIDSCA.AC02",
          "recommendedValue": "",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "excludeTargets",
          "displayName": "Excluded users/group from CBA",
          "checkId": "EIDSCA.AC03",
          "recommendedValue": "",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "authenticationModeConfiguration.x509CertificateAuthenticationDefaultMode",
          "displayName": "Authentication binding - Protected Level",
          "checkId": "EIDSCA.AC04",
          "recommendedValue": "",
          "severity": "Medium",
          "recommendation": "",
          "portalDeepLink": ""
        },
        {
          "name": "authenticationModeConfiguration.rules",
          "displayName": "Authentication binding - Rules",
          "checkId": "EIDSCA.AC05",
          "recommendedValue": "",
          "severity": "",
          "recommendation": "",
          "portalDeepLink": ""
        }
      ]
    }
  ],
  "notCovered": [
    {
      "controlId": "EIDSCA.CP",
      "controlName": "Default Settings - Consent Policy Settings",
      "endpoint": "settings (directorySetting)",
      "controlCount": 4
    },
    {
      "controlId": "EIDSCA.PR",
      "controlName": "Default Settings - Password Rule Settings",
      "endpoint": "settings (directorySetting)",
      "controlCount": 6
    },
    {
      "controlId": "EIDSCA.ST",
      "controlName": "Default Settings - Classification and M365 Groups",
      "endpoint": "settings (directorySetting)",
      "controlCount": 14
    },
    {
      "controlId": "EIDSCA.DA",
      "controlName": "Default Activity Timeout",
      "endpoint": "activityBasedTimeoutPolicies",
      "controlCount": 1
    },
    {
      "controlId": "EIDSCA.FT",
      "controlName": "Feature Rollout (Enabled Previews)",
      "endpoint": "featureRolloutPolicies",
      "controlCount": 1
    },
    {
      "controlId": "EIDSCA.CR",
      "controlName": "Consent Framework - Admin Consent Request",
      "endpoint": "adminConsentRequestPolicy",
      "controlCount": 6
    }
  ]
};
