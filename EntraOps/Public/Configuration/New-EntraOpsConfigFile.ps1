<#
.SYNOPSIS
    Create config file to store required or optional parameters for executing EntraOps without end-user prompts.

.DESCRIPTION
    Create config file which can be used by other cmdlets (e.g., to create required App Registrations and add required permissions)
    The config file will be also imported by using Connect-EntraOps which allows to use parameters from the file in the pipeline.

.PARAMETER AuthenticationType
    Defines the authentication method which will be used to request token from Microsoft Entra for gain access to Microsoft Graph, Azure Resource Manager and other APIs. Default is FederatedCredentials.

.PARAMETER DevOpsPlatform
    Defines the platform where the EntraOps repository is hosted. Default and support is currently limited to GitHub.

.PARAMETER ConfigFilePath
    Location of the config file which will be created. Default is ./EntraOpsConfig.json.

.PARAMETER IngestToLogAnalytics
    Defines if the classification data should be ingested to Log Analytics or Microsoft Sentinel Workspace. Default is false.

.PARAMETER IngestToWatchLists
    Defines if the classification data should be ingested to Microsoft Sentinel WatchLists. Default is false.

.PARAMETER ApplyAutomatedControlPlaneScopeUpdate
    Defines if the role assignment scope with Control Plane assets should be updated before analyse privileges. Default is false.
    You are able to customize in the config file the data source ("EntraOps", "PrivilegedRolesFromAzGraph", "PrivilegedEdgesFromExposureManagement") and which criticality level or role definition/scope level should be considered.

.PARAMETER ApplyAutomatedClassificationUpdate
    Defines if the classification template files should be updated from GitHub repository "https://github.com/Cloud-Architekt/AzurePrivilegedIAM" before analyse privileges. Default is false.
    You are able to define which classification files should be updated in the config file later.

.PARAMETER RbacSystems
    Defines which RBAC systems should be considered for the analysis. Default selection are all available RBAC systems: EntraID, IdentityGovernance and ResourceApps (Microsoft Graph API only).

.EXAMPLE
    Create environment file in default location with parameters to update classification files before analyse privileges and ingest data to Log Analytics but also Sentinel WatchLists..
    New-EntraOpsConfigFile -TenantName "contoso.onmicrosoft.com" -ApplyAutomatedControlPlaneScopeUpdate $true -IngestToLogAnalytics $true -IngestToWatchLists $true -ApplyAutomatedClassificationUpdate $true
 #>

function New-EntraOpsConfigFile {

    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$TenantName,

        [parameter(Mandatory = $false)]
        [string]$ManagingTenantName = "",        

        [parameter(Mandatory = $false)]
        [string]$ManagingTenantId = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet('UserInteractive', 'SystemAssignedMSI', 'UserAssignedMSI', 'FederatedCredentials', 'AlreadyAuthenticated', 'DeviceAuthentication')]
        [string]$AuthenticationType = "FederatedCredentials",

        [Parameter(Mandatory = $false)]
        [ValidateSet('AzureDevOps', 'GitHub', 'None')]
        [string]$DevOpsPlatform = "GitHub",

        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path (Split-Path $_ -Parent) })]
        [string]$ConfigFilePath = "$EntraOpsBasefolder/EntraOpsConfig.json",

        [Parameter(Mandatory = $false)]
        [boolean]$IngestToLogAnalytics = $false,

        [Parameter(Mandatory = $false)]
        [boolean]$IngestToWatchLists = $false,

        [Parameter(Mandatory = $false)]
        [boolean]$ApplyAutomatedControlPlaneScopeUpdate = $false,

        [Parameter(Mandatory = $false)]
        [boolean]$ApplyAutomatedClassificationUpdate = $false,

        [Parameter(Mandatory = $false)]
        [boolean]$ApplyAutomatedEntraOpsUpdate = $true,

        [Parameter(Mandatory = $false)]
        [boolean]$ApplyConditionalAccessTargetGroups = $false,

        [Parameter(Mandatory = $false)]
        [boolean]$ApplyAdministrativeUnitAssignments = $false,

        [Parameter(Mandatory = $false)]
        [boolean]$ApplyRmauAssignmentsForUnprotectedObjects = $false,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Azure", "AzureBilling", "EntraID", "IdentityGovernance", "DeviceManagement", "ResourceApps", "Defender")]
        [Array]$RbacSystems = ("EntraID", "IdentityGovernance", "ResourceApps", "DeviceManagement"),

        [Parameter(Mandatory = $false)]
        [ValidateSet("None", "All", "VIPUsers", "HighValueAssets", "IdentityCorrelation")]
        [Array]$WatchListTemplates = "None",

        [Parameter(Mandatory = $false)]
        [ValidateSet("ManagedIdentityAssignedResourceId", "All", "WorkloadIdentityAttackPaths", "WorkloadIdentityInfo", "WorkloadIdentityRecommendations")]
        [Array]$WatchListWorkloadIdentity = "None"
    )

    $ErrorActionPreference = "Stop"

    #region Connect to Azure Resource Manager
    # Get TenantId
    try {
        $TenantId = (Invoke-RestMethod -Uri ("https://login.windows.net/$($TenantName)/.well-known/openid-configuration")).token_endpoint.split('/')[3]
    } catch {
        Write-Error "Can't find tenant with name $TenantName. Error: $_"
    }

    Write-Output "Connect to Azure Resource Manager..."
    $AzContext = Get-AzContext
    if ($AzContext.Tenant.Id -ne $TenantId) {
        Write-Verbose "Call Connect-AzAccount to $($TenantId)..."
        Connect-AzAccount -TenantId $TenantId
    } else {
        Write-Verbose "Already connected to $($AzContext.Tenant.Id)"
    }

    try {
        $TenantDetails = Get-AzTenant -TenantId $TenantId
    } catch {
        Write-Error "Failed to get Tenant details for TenantId $TenantId. Error: $_"
    }
    #endregion

    #region Create configuration file schema with default values
    $EnvConfigSchema = [ordered]@{
        TenantId                                      = $($TenantId)
        TenantName                                    = $($TenantDetails.Domains[0])
        ManagingTenantId                              = $($ManagingTenantId)
        ManagingTenantName                            = $($ManagingTenantName)
        AuthenticationType                            = $($AuthenticationType)
        ClientId                                      = "Use New-EntraOpsWorkloadIdentity to create a new App Registration or enter here manually"
        DevOpsPlatform                                = $($DevOpsPlatform)
        RbacSystems                                   = $($RbacSystems)
        WorkflowTrigger                               = [ordered]@{
            PullScheduledTrigger         = $true
            PullScheduledCron            = "30 9 * * *"
            PushAfterPullWorkflowTrigger = $true
        }
        AutomatedControlPlaneScopeUpdate              = [ordered]@{
            ApplyAutomatedControlPlaneScopeUpdate = $ApplyAutomatedControlPlaneScopeUpdate
            PrivilegedObjectClassificationSource  = ("EntraOps", "PrivilegedRolesFromAzGraph", "PrivilegedEdgesFromExposureManagement")
            EntraOpsScopes                        = ("EntraID", "IdentityGovernance", "ResourceApps", "DeviceManagement", "Defender")
            AzureHighPrivilegedRoles              = ("Owner", "Role Based Access Control Administrator", "User Access Administrator")
            AzureHighPrivilegedScopes             = ("/", "/providers/microsoft.management/managementgroups/$($TenantId)")
            ExposureCriticalityLevel              = "<1"
        }
        AutomatedClassificationUpdate                 = [ordered]@{
            ApplyAutomatedClassificationUpdate = $ApplyAutomatedClassificationUpdate
            Classifications                    = ("AadResources", "AadResources.Param", "AppRoles", "Defender", "DeviceManagement", "DeviceManagement.Param", "IdentityGovernance")
        }
        AutomatedEntraOpsUpdate                       = [ordered]@{
            ApplyAutomatedEntraOpsUpdate = $ApplyAutomatedEntraOpsUpdate
            UpdateScheduledTrigger       = $true
            UpdateScheduledCron          = "0 9 * * 3"
        }
        LogAnalytics                                  = [ordered]@{
            IngestToLogAnalytics             = $IngestToLogAnalytics
            DataCollectionRuleName           = "Enter Data Collection Rule Name and run New-EntraOpsWorkloadIdentity to assign permissions"
            DataCollectionRuleSubscriptionId = "Enter Subscription Id of Data Collection Rule and run New-EntraOpsWorkloadIdentity to assign permissions"
            DataCollectionResourceGroupName  = "Enter Resource Group Name of Data Collection Rule and run New-EntraOpsWorkloadIdentity to assign permissions"
            TableName                        = "PrivilegedEAM_CL"
        }
        SentinelWatchLists                            = [ordered]@{
            IngestToWatchLists        = $IngestToWatchLists
            WatchListTemplates        = $WatchListTemplates
            WatchListWorkloadIdentity = $WatchListWorkloadIdentity
            SentinelWorkspaceName     = "Enter Log Analytics Workspace Name and run New-EntraOpsWorkloadIdentity to assign permissions"
            SentinelSubscriptionId    = "Enter Subscription Id of Log Analytics Workspace and run New-EntraOpsWorkloadIdentity to assign permissions"
            SentinelResourceGroupName = "Enter Resource Group of Log Analytics Workspace and run New-EntraOpsWorkloadIdentity to assign permissions"
            WatchListPrefix           = "EntraOps_"
        }        
        AutomatedAdministrativeUnitManagement         = [ordered]@{
            ApplyAdministrativeUnitAssignments = $ApplyAdministrativeUnitAssignments
            ApplyToAccessTierLevel             = ("ControlPlane", "ManagementPlane")
            FilterObjectType                   = ("User", "Group")
            RbacSystems                        = ("EntraID", "IdentityGovernance", "ResourceApps", "DeviceManagement")
            RestrictedAuMode                   = "selected"
        }
        AutomatedConditionalAccessTargetGroups        = [ordered]@{
            ApplyConditionalAccessTargetGroups = $ApplyConditionalAccessTargetGroups
            AdminUnitName                      = "Tier0-ControlPlane.ConditionalAccess"
            ApplyToAccessTierLevel             = ("ControlPlane", "ManagementPlane")
            FilterObjectType                   = ("User", "Group")
            GroupPrefix                        = "sug_Entra.CA.IncludeUsers.PrivilegedAccounts."
            RbacSystems                        = ("EntraID", "IdentityGovernance", "ResourceApps", "DeviceManagement")
        }
        AutomatedRmauAssignmentsForUnprotectedObjects = [ordered]@{
            ApplyRmauAssignmentsForUnprotectedObjects = $ApplyRmauAssignmentsForUnprotectedObjects
            ApplyToAccessTierLevel                    = ("ControlPlane", "ManagementPlane")
            FilterObjectType                          = ("User", "Group")
            RbacSystems                               = ("EntraID", "IdentityGovernance", "DeviceManagement")
        }
        CustomSecurityAttributes                      = [ordered]@{
            PrivilegedUserAttribute             = "privilegedUser"
            PrivilegedUserPawAttribute          = "associatedSecureAdminWorkstation"
            PrivilegedServicePrincipalAttribute = "privilegedWorkloadIdentitiy"
            UserWorkAccountAttribute            = "associatedWorkAccount"
        }
        ServiceEM                                     = [ordered]@{
            GovernanceModel                  = "Centralized"
            ControlPlaneDelegationGroupId    = ""
            ControlPlaneGroupName            = "PRG-Tenant-ControlPlane-IdentityOps"
            ManagementPlaneDelegationGroupId = ""
            ManagementPlaneGroupName         = "PRG-Tenant-ManagementPlane-PlatformOps"
            AdministratorGroupId             = ""
            ConstrainedDelegation            = [ordered]@{
                ManagementPlane = [ordered]@{
                    ExcludedRoleDefinitionIds   = @(
                        "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"  # Owner
                        "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"  # User Access Administrator
                        "f58310d9-a9f6-439a-9e8d-f62e7b41a168"  # Role Based Access Control Administrator
                    )
                    AllowedTargetGroupFilter    = "WorkloadPlane-Admins"
                }
                WorkloadPlane   = [ordered]@{
                    AllowedRoleDefinitionIds    = @(
                        # Key Vault roles
                        "00482a5a-887f-4fb3-b363-3b7fe8e74483"  # Key Vault Administrator
                        "a4417e6f-fecd-4de8-b567-7b0420556985"  # Key Vault Certificates Officer
                        "14b46e9e-c2b7-41b4-b07b-48a6ebf60603"  # Key Vault Crypto Officer
                        "12338af0-0e69-4776-bea7-57ae8d297424"  # Key Vault Crypto User
                        "21090545-7ca7-4776-b22c-e363652d74d2"  # Key Vault Reader
                        "b86a8fe4-44ce-4948-aee5-eccb2c155cd7"  # Key Vault Secrets Officer
                        "4633458b-17de-408a-b874-0445c86b69e6"  # Key Vault Secrets User
                        # Storage roles
                        "ba92f5b4-2d11-453d-a403-e96b0029c9fe"  # Storage Blob Data Contributor
                        "b7e6dc6d-f1e8-4753-8033-0f276bb0955b"  # Storage Blob Data Owner
                        "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"  # Storage Blob Data Reader
                        "0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3"  # Storage Table Data Contributor
                        "76199698-9eea-4c19-bc75-cec21354c6b6"  # Storage Table Data Reader
                        "974c5e8b-45b9-4653-ba55-5f855dd0fb88"  # Storage Queue Data Contributor
                        "19e7f393-937e-4f77-808e-94535e297925"  # Storage Queue Data Reader
                        "8a0f0c08-91a1-4084-bc3d-661d67233fed"  # Storage Queue Data Message Processor
                        "c6a89b2d-59bc-44d0-9896-0f6e12d7b80a"  # Storage Queue Data Message Sender
                    )
                    AllowedTargetGroupFilter    = "WorkloadPlane-Users"
                }
            }
            PIMAuthenticationContext         = [ordered]@{
                EnableAuthenticationContext = $false
                ControlPlane                = [ordered]@{
                    AuthenticationContextClassReferenceId = ""
                    AuthenticationContextDisplayName      = ""
                }
                ManagementPlane             = [ordered]@{
                    AuthenticationContextClassReferenceId = ""
                    AuthenticationContextDisplayName      = ""
                }
                WorkloadPlane               = [ordered]@{
                    AuthenticationContextClassReferenceId = ""
                    AuthenticationContextDisplayName      = ""
                }
            }
        }
    }
    #endregion

    #region Write configuration file to disk
    try {
        Write-Output "Writing configuration file to $($ConfigFilePath)..."
        $EnvConfigSchema | ConvertTo-Json -Depth 10 | Out-File -Path $($ConfigFilePath)
    } catch {
        Write-Error "Failed to write configuration file to $($ConfigFilePath). Error: $_"
    }
    #endregion
}