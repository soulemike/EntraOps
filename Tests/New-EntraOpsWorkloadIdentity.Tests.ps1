#Requires -Modules Pester

BeforeAll {
    function Install-EntraOpsRequiredModule { param($ModuleName) }
    function Connect-MgGraph { param($Scopes, $TenantId) }
    function Get-MgServicePrincipal { param($Filter, $ServicePrincipalId) }
    function Get-MgApplication { param($Filter) }
    function New-MgApplication { param($DisplayName, $SignInAudience) }
    function New-MgServicePrincipal { param($DisplayName, $AppId) }
    function Get-MgServicePrincipalAppRoleAssignment { param($ServicePrincipalId, [switch]$All) }
    function New-MgServicePrincipalAppRoleAssignment { param($ServicePrincipalId, $PrincipalId, $ResourceId, $AppRoleId) }
    function Get-MgApplicationFederatedIdentityCredential { param($ApplicationId, [switch]$All) }
    function New-MgApplicationFederatedIdentityCredential { param($ApplicationId, $BodyParameter) }
    function Get-AzContext {}
    function Connect-AzAccount { param($Tenant) }
    function Get-AzRoleAssignment { param($ObjectId, $RoleDefinitionName, $Scope) }
    function New-AzRoleAssignment { param($ObjectId, $ApplicationId, $RoleDefinitionName, $Scope) }
    function Register-EntraOpsTenantGovernanceServicePrincipal { param($ResourcesToInclude, $TenantId) }

    . "$PSScriptRoot/../EntraOps/Public/Configuration/New-EntraOpsWorkloadIdentity.ps1"

    $script:PullPermissionNames = @(
        'AdministrativeUnit.Read.All'
        'Application.Read.All'
        'CustomSecAttributeAssignment.Read.All'
        'DeviceManagementConfiguration.Read.All'
        'DeviceManagementManagedDevices.Read.All'
        'DeviceManagementRBAC.Read.All'
        'DeviceManagementServiceConfig.Read.All'
        'Directory.Read.All'
        'DirectoryRecommendations.Read.All'
        'EntitlementManagement.Read.All'
        'Group.Read.All'
        'RemoteTenantGroups.Read.All'
        'PrivilegedAccess.Read.AzureADGroup'
        'PrivilegedEligibilitySchedule.Read.AzureADGroup'
        'Policy.Read.All'
        'RoleManagement.Read.All'
        'TenantGovernance-Relationship.Read.All'
        'ThreatHunting.Read.All'
        'User.Read.All'
        'Zone.Read.All'
    )

    function New-WorkloadIdentityTestConfig {
        param (
            [Parameter(Mandatory = $true)][string]$Path,
            [string[]]$RbacSystems = @('Azure'),
            [bool]$EnableTenantGovernanceSnapshot = $false
        )

        @{
            TenantId                                      = '11111111-1111-1111-1111-111111111111'
            AuthenticationType                            = 'FederatedCredentials'
            DevOpsPlatform                                = 'GitHub'
            ClientId                                      = 'not-configured'
            RbacSystems                                   = $RbacSystems
            AutomatedAdministrativeUnitManagement        = @{ ApplyAdministrativeUnitAssignments = $false }
            AutomatedRmauAssignmentsForUnprotectedObjects = @{ ApplyRmauAssignmentsForUnprotectedObjects = $false }
            AutomatedElmCatalogProtection                = @{ ApplyPrivilegedElmCatalogProtection = $false }
            AutomatedConditionalAccessTargetGroups       = @{ ApplyConditionalAccessTargetGroups = $false }
            AutomatedControlPlaneScopeUpdate              = @{
                ApplyAutomatedControlPlaneScopeUpdate = $false
                PrivilegedObjectClassificationSource  = @()
            }
            LogAnalytics                                  = @{ IngestToLogAnalytics = $false }
            SentinelWatchLists                            = @{
                IngestToWatchLists      = $false
                WatchListTemplates      = @('None')
                WatchListWorkloadIdentity = @('None')
            }
            TenantGovernanceSnapshot                      = @{
                EnableTenantGovernanceSnapshot = $EnableTenantGovernanceSnapshot
                ResourcesToInclude             = @('microsoft.entra.conditionalAccessPolicy')
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

Describe 'New-EntraOpsWorkloadIdentity provisioning safety' {
    BeforeEach {
        $script:GraphServicePrincipal = [pscustomobject]@{
            Id       = 'graph-sp-object-id'
            AppRoles = @($script:PullPermissionNames | ForEach-Object {
                    [pscustomobject]@{ Id = "role-$($_)"; Value = $_; Origin = 'Application' }
                }) + @(
                [pscustomobject]@{ Id = 'role-AdministrativeUnit.ReadWrite.All'; Value = 'AdministrativeUnit.ReadWrite.All'; Origin = 'Application' }
                [pscustomobject]@{ Id = 'role-EntitlementManagement.ReadWrite.All'; Value = 'EntitlementManagement.ReadWrite.All'; Origin = 'Application' }
                [pscustomobject]@{ Id = 'role-ConfigurationMonitoring.ReadWrite.All'; Value = 'ConfigurationMonitoring.ReadWrite.All'; Origin = 'Application' }
            )
        }
        $script:Application = [pscustomobject]@{ Id = 'app-object-id'; AppId = 'app-client-id' }
        $script:ServicePrincipal = [pscustomobject]@{ Id = 'workload-sp-object-id'; AppId = 'app-client-id'; DisplayName = 'entraops' }

        Mock Install-EntraOpsRequiredModule {}
        Mock Connect-MgGraph {}
        Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111' } } }
        Mock Connect-AzAccount {}
        Mock New-MgApplication { $script:Application }
        Mock Get-MgApplication { $script:Application }
        Mock New-MgServicePrincipal { $script:ServicePrincipal }
        Mock Get-MgServicePrincipal {
            if ($Filter) { return $script:GraphServicePrincipal }
            return $script:ServicePrincipal
        }
        Mock Get-MgServicePrincipalAppRoleAssignment { @() }
        Mock New-MgServicePrincipalAppRoleAssignment {
            [pscustomobject]@{ ResourceId = $ResourceId; AppRoleId = $AppRoleId }
        }
        Mock Get-AzRoleAssignment { @() }
        Mock New-AzRoleAssignment { [pscustomobject]@{ Scope = $Scope; RoleDefinitionName = $RoleDefinitionName } }
        Mock Get-MgApplicationFederatedIdentityCredential { @() }
        Mock New-MgApplicationFederatedIdentityCredential {}
        Mock Register-EntraOpsTenantGovernanceServicePrincipal {}
        Mock Start-Sleep {}
    }

    It 'grants Reader on the tenant root management group for Azure collection' {
        $ConfigPath = Join-Path $TestDrive 'azure.json'
        New-WorkloadIdentityTestConfig -Path $ConfigPath

        { New-EntraOpsWorkloadIdentity -AppDisplayName 'entraops' -ConfigFile $ConfigPath } | Should -Not -Throw

        Should -Invoke New-AzRoleAssignment -Times 1 -ParameterFilter {
            $ObjectId -eq 'workload-sp-object-id' -and
            $RoleDefinitionName -eq 'Reader' -and
            $Scope -eq '/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111'
        }
    }

    It 'does not grant root management group Reader when Azure and Azure-backed features are excluded' {
        $ConfigPath = Join-Path $TestDrive 'entra-only.json'
        New-WorkloadIdentityTestConfig -Path $ConfigPath -RbacSystems @('EntraID')

        { New-EntraOpsWorkloadIdentity -AppDisplayName 'entraops' -ConfigFile $ConfigPath } | Should -Not -Throw

        Should -Invoke New-AzRoleAssignment -Times 0
    }

    It 'does not duplicate an existing tenant root management group Reader assignment' {
        $ConfigPath = Join-Path $TestDrive 'azure-idempotent.json'
        New-WorkloadIdentityTestConfig -Path $ConfigPath
        Mock Get-AzRoleAssignment {
            [pscustomobject]@{ Scope = $Scope; RoleDefinitionName = $RoleDefinitionName; ObjectId = $ObjectId }
        }

        { New-EntraOpsWorkloadIdentity -AppDisplayName 'entraops' -ConfigFile $ConfigPath } | Should -Not -Throw

        Should -Invoke New-AzRoleAssignment -Times 0
    }

    It 'fails the setup when a required Graph permission cannot be assigned' {
        $ConfigPath = Join-Path $TestDrive 'graph-failure.json'
        New-WorkloadIdentityTestConfig -Path $ConfigPath -RbacSystems @('EntraID')
        Mock New-MgServicePrincipalAppRoleAssignment {
            if ($AppRoleId -eq 'role-Directory.Read.All') { throw 'consent denied' }
            [pscustomobject]@{ ResourceId = $ResourceId; AppRoleId = $AppRoleId }
        }

        { New-EntraOpsWorkloadIdentity -AppDisplayName 'entraops' -ConfigFile $ConfigPath } |
            Should -Throw "*Directory.Read.All*consent denied*"
    }

    It 'fails the setup when the requested federated credential cannot be created' {
        $ConfigPath = Join-Path $TestDrive 'federated-failure.json'
        New-WorkloadIdentityTestConfig -Path $ConfigPath -RbacSystems @('EntraID')
        Mock New-MgApplicationFederatedIdentityCredential { throw 'federation denied' }

        { New-EntraOpsWorkloadIdentity -AppDisplayName 'entraops' -ConfigFile $ConfigPath -ExistingSpObjectId 'workload-sp-object-id' -CreateFederatedCredential `
                -GitHubOrg 'Contoso' -GitHubRepo 'EntraOps-Prod' -FederatedEntityType Branch -FederatedEntityName main } |
            Should -Throw "*Federated Credential*EntraOps-Prod-Branch-main*federation denied*"
    }

    It 'skips application permissions and a federated credential that already exist' {
        $ConfigPath = Join-Path $TestDrive 'idempotent.json'
        New-WorkloadIdentityTestConfig -Path $ConfigPath -RbacSystems @('EntraID')
        Mock Get-MgServicePrincipalAppRoleAssignment {
            @($script:GraphServicePrincipal.AppRoles | Where-Object { $_.Value -in $script:PullPermissionNames } | ForEach-Object {
                    [pscustomobject]@{ ResourceId = $script:GraphServicePrincipal.Id; AppRoleId = $_.Id }
                })
        }
        Mock Get-MgApplicationFederatedIdentityCredential {
            [pscustomobject]@{
                Name      = 'EntraOps-Prod-Branch-main'
                Issuer    = 'https://token.actions.githubusercontent.com'
                Subject   = 'repo:Contoso/EntraOps-Prod:ref:refs/heads/main'
                Audiences = @('api://AzureADTokenExchange')
            }
        }

        { New-EntraOpsWorkloadIdentity -AppDisplayName 'entraops' -ConfigFile $ConfigPath -ExistingSpObjectId 'workload-sp-object-id' -CreateFederatedCredential `
                -GitHubOrg 'Contoso' -GitHubRepo 'EntraOps-Prod' -FederatedEntityType Branch -FederatedEntityName main } |
            Should -Not -Throw

        Should -Invoke New-MgApplication -Times 0
        Should -Invoke New-MgServicePrincipalAppRoleAssignment -Times 0
        Should -Invoke New-MgApplicationFederatedIdentityCredential -Times 0
    }

    It 'rejects an existing federated credential whose case-sensitive subject does not match' {
        $ConfigPath = Join-Path $TestDrive 'federated-case-mismatch.json'
        New-WorkloadIdentityTestConfig -Path $ConfigPath -RbacSystems @('EntraID')
        Mock Get-MgApplicationFederatedIdentityCredential {
            [pscustomobject]@{
                Name      = 'EntraOps-Prod-Branch-main'
                Issuer    = 'https://token.actions.githubusercontent.com'
                Subject   = 'repo:contoso/EntraOps-Prod:ref:refs/heads/main'
                Audiences = @('api://AzureADTokenExchange')
            }
        }

        { New-EntraOpsWorkloadIdentity -AppDisplayName 'entraops' -ConfigFile $ConfigPath -ExistingSpObjectId 'workload-sp-object-id' -CreateFederatedCredential `
                -GitHubOrg 'Contoso' -GitHubRepo 'EntraOps-Prod' -FederatedEntityType Branch -FederatedEntityName main } |
            Should -Throw '*issuer, subject, or audience does not match*'

        Should -Invoke New-MgApplicationFederatedIdentityCredential -Times 0
    }
}
