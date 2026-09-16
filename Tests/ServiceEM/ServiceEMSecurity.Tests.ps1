#Requires -Modules Pester
#Requires -Version 7.0

BeforeAll {
    $script:TestRepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:PreviousEntraOpsConfig = Get-Variable EntraOpsConfig -Scope Global -ErrorAction SilentlyContinue

    function Invoke-EntraOpsMsGraphQuery {
        param(
            [string]$Method,
            [string]$Uri,
            [string]$Body,
            [string]$ConsistencyLevel,
            [string]$OutputType,
            [switch]$DisableCache,
            [switch]$ThrowOnFailure
        )
        throw 'Invoke-EntraOpsMsGraphQuery must be mocked'
    }
    function Get-MgGroup { param($GroupId, $Filter, $ConsistencyLevel, $ErrorAction) throw 'Get-MgGroup must be mocked' }
    function Save-EntraOpsServiceEMConfigKey { param($ConfigKey, $Value, $ConfigFilePath, $logPrefix) }

    . "$script:TestRepositoryRoot/EntraOps/Private/ConvertTo-EntraOpsODataStringLiteral.ps1"
    . "$script:TestRepositoryRoot/EntraOps/Private/Resolve-EntraOpsServiceEMDelegationGroup.ps1"
    . "$script:TestRepositoryRoot/EntraOps/Public/ServiceEM/New-EntraOpsServiceEMCatalog.ps1"
    . "$script:TestRepositoryRoot/EntraOps/Public/ServiceEM/New-EntraOpsServicePIMPolicy.ps1"
    . "$script:TestRepositoryRoot/EntraOps/Public/ServiceEM/Remove-EntraOpsServiceCatalog.ps1"
}

AfterAll {
    if ($script:PreviousEntraOpsConfig) {
        Set-Variable EntraOpsConfig -Scope Global -Value $script:PreviousEntraOpsConfig.Value
    } else {
        Remove-Variable EntraOpsConfig -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'ServiceEM Graph lookup safety' {
    It 'encodes an apostrophe in the destructive catalog lookup' {
        $script:CatalogLookupUri = $null
        Mock Invoke-EntraOpsMsGraphQuery {
            $script:CatalogLookupUri = $Uri
            return @()
        }

        Remove-EntraOpsServiceCatalog -ServiceCatalogName "Catalog-Director's Service" -Force -WarningAction SilentlyContinue | Out-Null

        $script:CatalogLookupUri | Should -Match "displayName eq 'Catalog-Director%27%27s%20Service'"
        $script:CatalogLookupUri | Should -Not -Match "Director's Service"
    }

    It 'uses the same encoded catalog name for every catalog lookup' {
        $script:CatalogLookupUris = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-EntraOpsMsGraphQuery {
            if ($Method -eq 'GET') {
                $script:CatalogLookupUris.Add($Uri)
                return [pscustomobject]@{ Id = 'catalog-id'; DisplayName = "Catalog-Director's Service" }
            }
            throw "Unexpected Graph method: $Method"
        }
        Mock Start-Sleep {}

        New-EntraOpsServiceEMCatalog -ServiceName "Director's Service" | Out-Null

        $script:CatalogLookupUris.Count | Should -Be 2
        @($script:CatalogLookupUris | Where-Object { $_ -notmatch "displayName eq 'Catalog-Director%27%27s%20Service'" }) |
        Should -BeNullOrEmpty
    }

    It 'passes a raw escaped OData literal to the Graph SDK group filter' {
        $script:GroupFilter = $null
        Mock Get-MgGroup {
            $script:GroupFilter = $Filter
            return [pscustomobject]@{ Id = 'group-id'; DisplayName = "Tier 'Zero' Admins" }
        }
        Mock Save-EntraOpsServiceEMConfigKey {}

        $result = Resolve-EntraOpsServiceEMDelegationGroup -Plane ControlPlane -DefaultGroupName "Tier 'Zero' Admins" -ConfigKey ControlPlaneDelegationGroupId

        $result | Should -Be 'group-id'
        $script:GroupFilter | Should -Be "displayName eq 'Tier ''Zero'' Admins'"
        $script:GroupFilter | Should -Not -Match '%27'
    }
}

Describe 'ServiceEM PIM policy safety' {
    BeforeEach {
        $Global:EntraOpsConfig = [pscustomobject]@{
            ServiceEM = [pscustomobject]@{
                PIMAuthenticationContext = [pscustomobject]@{
                    EnableAuthenticationContext = $true
                    ControlPlane                = [pscustomobject]@{
                        AuthenticationContextClassReferenceId = 'c1'
                    }
                }
            }
        }
        $script:PolicyPatchBody = $null
        $script:PolicyPatchThrowsOnFailure = $false
    }

    It 'sends authentication context as a dedicated policy rule' {
        Mock Invoke-EntraOpsMsGraphQuery {
            if ($Method -eq 'GET') {
                return [pscustomobject]@{ Id = 'assignment-member'; PolicyId = 'policy-id' }
            }
            if ($Method -eq 'PATCH') {
                $script:PolicyPatchBody = $Body
                $script:PolicyPatchThrowsOnFailure = $ThrowOnFailure.IsPresent
                return
            }
            throw "Unexpected Graph method: $Method"
        }

        New-EntraOpsServicePIMPolicy -ServiceGroups @([pscustomobject]@{ Id = 'group-id'; DisplayName = 'SG-Test-ControlPlane-Admins' }) | Out-Null

        $payload = $script:PolicyPatchBody | ConvertFrom-Json -Depth 10
        $authenticationContextRules = @($payload.rules | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' })
        $authenticationContextRules.Count | Should -Be 1
        $authenticationContextRules[0].'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
        $authenticationContextRules[0].isEnabled | Should -BeTrue
        $authenticationContextRules[0].claimValue | Should -Be 'c1'
        @($payload.rules | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }).enabledRules |
        Should -Not -Contain 'AuthenticationContext'
        $script:PolicyPatchThrowsOnFailure | Should -BeTrue
    }

    It 'throws after a policy PATCH failure instead of returning success' {
        Mock Invoke-EntraOpsMsGraphQuery {
            if ($Method -eq 'GET') {
                return [pscustomobject]@{ Id = 'assignment-member'; PolicyId = 'policy-id' }
            }
            if ($Method -eq 'PATCH') {
                throw 'Graph rejected the policy update'
            }
        }

        { New-EntraOpsServicePIMPolicy -ServiceGroups @([pscustomobject]@{ Id = 'failed-group'; DisplayName = 'SG-Test-ControlPlane-Admins' }) } |
        Should -Throw '*Failed to update PIM policy for 1 group(s)*failed-group*'
    }
}