<#
.SYNOPSIS
    Validates the prerequisites required to run the EntraOps Tenant Governance Snapshot cmdlets.

.DESCRIPTION
    Checks that:
    - The current Microsoft Graph session or app-only identity holds the "ConfigurationMonitoring.ReadWrite.All" permission
      required to create Tenant Configuration Management (UTCM) snapshots. This is Microsoft's
      documented least-privileged permission for the createSnapshot API - "ConfigurationMonitoring.Read.All"
      alone is not sufficient to create a snapshot job (only to read/list already-created ones).
    - The first-party "Microsoft Tenant Configuration Management" service principal exists in the
      tenant.
    - (Best effort, only if the caller has sufficient permissions to read app role assignments) The
      UTCM service principal has been granted the Microsoft Graph read permissions required for the
      requested resource types.

    Used internally by Get-EntraOpsTenantGovernanceSnapshot before creating a snapshot job, and can
    also be run standalone to troubleshoot configuration issues.

.PARAMETER ResourcesToInclude
    Array of Microsoft Entra resource types to validate UTCM permissions for. Defaults to the
    recommended tenant governance resource set.

.PARAMETER ThrowOnFailure
    Throws a descriptive error (pointing to Register-EntraOpsTenantGovernanceServicePrincipal /
    New-EntraOpsWorkloadIdentity) instead of just returning a status object when a hard prerequisite
    (missing Graph permission or missing UTCM service principal) is not met.

.EXAMPLE
    Test-EntraOpsTenantGovernancePrerequisite

.EXAMPLE
    Test-EntraOpsTenantGovernancePrerequisite -ResourcesToInclude @("microsoft.entra.conditionalAccessPolicy") -ThrowOnFailure
#>
function Test-EntraOpsTenantGovernancePrerequisite {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Array]$ResourcesToInclude = (Get-EntraOpsTenantGovernanceResourceDefinition).DefaultResources
        ,
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnFailure
    )

    $UtcmAppId = "03b07b79-c5bc-4b5e-9bfa-13acf4a99998"
    $Issues = [System.Collections.Generic.List[string]]::new()
    $IsReady = $true

    $Result = [ordered]@{
        IsReady                              = $true
        HasConfigurationMonitoringPermission = $false
        UtcmServicePrincipalExists           = $false
        UtcmServicePrincipalId               = $null
        MissingUtcmPermissions               = @()
        PermissionCheckSkippedReason         = $null
        Issues                               = $Issues
    }

    #region Check Microsoft Graph permission on the current session or app-only identity
    $MgContext = Get-MgContext -ErrorAction SilentlyContinue
    $IsRestOnlyMode = [bool]$__EntraOpsSession['UseInvokeRestMethodOnly']
    $CurrentIdentityClientId = if ($MgContext.ClientId) {
        $MgContext.ClientId
    } elseif ($IsRestOnlyMode) {
        (Get-AzContext -ErrorAction SilentlyContinue).Account.Id
    }

    if (-not $MgContext -and -not $IsRestOnlyMode) {
        $Issues.Add("No active Microsoft Graph session found. Run Connect-EntraOps or Connect-MgGraph first.")
        $IsReady = $false
    } else {
        $Result.HasConfigurationMonitoringPermission = $MgContext.Scopes -contains "ConfigurationMonitoring.ReadWrite.All"
        $ShouldCheckApplicationPermission = $CurrentIdentityClientId -and ($IsRestOnlyMode -or $MgContext.AuthType -eq 'AppOnly')
        if (-not $Result.HasConfigurationMonitoringPermission -and $ShouldCheckApplicationPermission) {
            try {
                $CurrentIdentitySp = @(Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/servicePrincipals?`$filter=appId eq '$CurrentIdentityClientId'" -OutputType PSObject -DisableCache -ThrowOnFailure) | Select-Object -First 1
                $MsGraph = @(Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'" -OutputType PSObject -DisableCache -ThrowOnFailure) | Select-Object -First 1
                $RequiredAppRole = @($MsGraph.appRoles | Where-Object { $_.value -eq 'ConfigurationMonitoring.ReadWrite.All' }) | Select-Object -First 1

                if ($CurrentIdentitySp -and $RequiredAppRole) {
                    $CurrentIdentityAssignments = @(Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/servicePrincipals/$($CurrentIdentitySp.id)/appRoleAssignments" -OutputType PSObject -DisableCache -ThrowOnFailure)
                    $Result.HasConfigurationMonitoringPermission = $CurrentIdentityAssignments.appRoleId -contains $RequiredAppRole.id
                }
            } catch {
                Write-Verbose "Could not verify ConfigurationMonitoring.ReadWrite.All as an application permission for client ID ${CurrentIdentityClientId}: $($_.Exception.Message)"
            }
        }
        if (-not $Result.HasConfigurationMonitoringPermission) {
            $Issues.Add("Microsoft Graph permission 'ConfigurationMonitoring.ReadWrite.All' is missing on the current identity. 'ConfigurationMonitoring.Read.All' alone is not sufficient to create a snapshot job. Run New-EntraOpsWorkloadIdentity (with TenantGovernanceSnapshot.EnableTenantGovernanceSnapshot set to true in the config file) to grant it, or Register-EntraOpsTenantGovernanceServicePrincipal -GrantConfigurationMonitoringReadWrite to (re-)apply it standalone.")
            $IsReady = $false
        }
    }
    #endregion

    #region Check that the UTCM service principal exists
    try {
        $UtcmSp = @(Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/servicePrincipals?`$filter=appId eq '$UtcmAppId'" -OutputType PSObject -DisableCache -ThrowOnFailure) | Select-Object -First 1
        if ($UtcmSp) {
            $Result.UtcmServicePrincipalExists = $true
            $Result.UtcmServicePrincipalId = $UtcmSp.id
        } else {
            $Issues.Add("The first-party 'Microsoft Tenant Configuration Management' service principal (AppId $UtcmAppId) was not found in the tenant. Run Register-EntraOpsTenantGovernanceServicePrincipal to create it and grant the required read permissions.")
            $IsReady = $false
        }
    } catch {
        $Result.PermissionCheckSkippedReason = "Could not verify the Microsoft Tenant Configuration Management service principal (insufficient permission or Graph error): $($_.Exception.Message)"
        Write-Verbose $Result.PermissionCheckSkippedReason
    }
    #endregion

    #region Best-effort check of UTCM service principal permissions for the requested resources
    if ($Result.UtcmServicePrincipalExists) {
        try {
            $ResourceDefinition = Get-EntraOpsTenantGovernanceResourceDefinition
            $RequiredPermissions = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Resource in $ResourcesToInclude) {
                foreach ($Permission in @($ResourceDefinition.ResourcePermissions[$Resource])) {
                    if ($Permission) { $RequiredPermissions.Add($Permission) | Out-Null }
                }
            }

            $MsGraph = @(Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'" -OutputType PSObject -DisableCache -ThrowOnFailure) | Select-Object -First 1
            # Some resource types (e.g. microsoft.securityandcompliance.*) are backed by the Office 365
            # Exchange Online API rather than Microsoft Graph, and require app roles from that resource
            # service principal instead (e.g. "Exchange.ManageAsApp").
            $ExchangeOnline = @(Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/servicePrincipals?`$filter=appId eq '00000002-0000-0ff1-ce00-000000000000'" -OutputType PSObject -DisableCache -ThrowOnFailure) | Select-Object -First 1
            $ExistingAssignments = @(Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/servicePrincipals/$($Result.UtcmServicePrincipalId)/appRoleAssignments" -OutputType PSObject -DisableCache -ThrowOnFailure)
            $AssignedPermissionNames = foreach ($Assignment in $ExistingAssignments) {
                $RoleName = ($MsGraph.appRoles | Where-Object { $_.id -eq $Assignment.appRoleId }).value
                if (-not $RoleName -and $ExchangeOnline) {
                    $RoleName = ($ExchangeOnline.appRoles | Where-Object { $_.id -eq $Assignment.appRoleId }).value
                }
                $RoleName
            }

            $Missing = @($RequiredPermissions | Where-Object { $_ -notin $AssignedPermissionNames })
            if ($Missing.Count -gt 0) {
                $Result.MissingUtcmPermissions = $Missing
                $Issues.Add("The Microsoft Tenant Configuration Management service principal is missing $($Missing.Count) required read permission(s): $($Missing -join ', '). Run Register-EntraOpsTenantGovernanceServicePrincipal to grant them.")
                $IsReady = $false
            }
        } catch {
            $Result.PermissionCheckSkippedReason = "Could not verify the granted permissions of the Microsoft Tenant Configuration Management service principal (insufficient permission or Graph error): $($_.Exception.Message)"
            Write-Verbose $Result.PermissionCheckSkippedReason
        }
    }
    #endregion

    $Result.IsReady = $IsReady
    $ResultObject = [PSCustomObject]$Result

    if ($ThrowOnFailure -and -not $ResultObject.IsReady) {
        throw "Tenant Governance Snapshot prerequisites are not met:`n - $($Issues -join "`n - ")"
    }

    return $ResultObject
}
