<#
.SYNOPSIS
    Configures PIM activation policies for service admin groups.

.DESCRIPTION
    Updates the Unified Role Management Policy for the member role of each
    non-Members group in ServiceGroups. Policies enforce:

    - Expiration_Admin_Eligibility: no expiration for eligible assignments.
    - Expiration_Admin_Assignment: 15-day maximum for active assignments.
    - Expiration_EndUser_Assignment: 10-hour maximum for activated sessions.
    - Enablement_EndUser_Assignment: MFA + Justification required on activation.

    When EntraOpsConfig.ServiceEM.PIMAuthenticationContext.EnableAuthenticationContext
    is true and an AuthenticationContextClassReferenceId is configured for the
    group's access level (ControlPlane / ManagementPlane / WorkloadPlane), an
    authentication context step-up is added to the enablement rules.

    Access level is determined from the group DisplayName (ControlPlane,
    ManagementPlane, or WorkloadPlane).

    When all admin groups are delegated and no non-Members groups remain,
    returns an empty array without error.

.PARAMETER ServiceGroups
    All owned service group objects. Non-Members groups receive policy updates.
    Pass only owned (non-delegated) groups.

.PARAMETER ServiceName
    Name of the service. Optional; not currently used in policy computation
    but provided for logging context and future use.

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsServicePIMPolicy -ServiceGroups $ownedGroups

    Applies PIM policy (MFA + Justification, 10h activation limit) to all
    non-Members groups for the service.

.EXAMPLE
    New-EntraOpsServicePIMPolicy -ServiceGroups $ownedGroups -ServiceName "MyService"

    Same as above; ServiceName is passed for log context.

#>
function New-EntraOpsServicePIMPolicy {
    [OutputType([psobject[]])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [psobject[]]$ServiceGroups,

        [string]$ServiceName = "",

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        $groupPolicies = @()
        $groupPolicyAssignments = @()
        
        # Load PIM Authentication Context configuration from global config
        $pimAuthContextConfig = $null
        if ($Global:EntraOpsConfig.ServiceEM.PIMAuthenticationContext.EnableAuthenticationContext -eq $true) {
            $pimAuthContextConfig = $Global:EntraOpsConfig.ServiceEM.PIMAuthenticationContext
            Write-Verbose "$logPrefix PIM Authentication Context is enabled in configuration"
        } else {
            Write-Verbose "$logPrefix PIM Authentication Context is disabled in configuration - will enforce MFA + Justification only"
        }
    }

    process {
        foreach($group in $ServiceGroups|Where-Object{$_.DisplayName -notlike "*Members*"}){
            # Determine access level from group DisplayName
            $accessLevel = $null
            if ($group.DisplayName -match 'ControlPlane') {
                $accessLevel = "ControlPlane"
            } elseif ($group.DisplayName -match 'ManagementPlane') {
                $accessLevel = "ManagementPlane"
            } elseif ($group.DisplayName -match 'WorkloadPlane') {
                $accessLevel = "WorkloadPlane"
            }

            # Create a fresh copy of policy params for each group to avoid cross-contamination
            $currentGroupPolicyParams = @{
                rules = @(
                    @{
                        "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyExpirationRule"
                        id = "Expiration_Admin_Eligibility"
                        isExpirationRequired = $false
                    },
                    @{
                        "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyExpirationRule"
                        id = "Expiration_Admin_Assignment"
                        isExpirationRequired = $true
                        maximumDuration = "P15D"
                    },
                    @{
                        "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyExpirationRule"
                        id = "Expiration_EndUser_Assignment"
                        maximumDuration = "PT10H"
                    },
                    @{
                        "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyEnablementRule"
                        id = "Enablement_EndUser_Assignment"
                        enabledRules = @(
                            "MultiFactorAuthentication",
                            "Justification"
                        )
                    }
                )
            }

            # Add authentication context to enablement rules if explicitly enabled and configured for this access level
            if ($pimAuthContextConfig -and 
                $pimAuthContextConfig.EnableAuthenticationContext -eq $true -and
                $accessLevel -and 
                $pimAuthContextConfig[$accessLevel]) {
                
                $authContextId = $pimAuthContextConfig[$accessLevel].AuthenticationContextClassReferenceId
                if (-not [string]::IsNullOrWhiteSpace($authContextId)) {
                    Write-Verbose "$logPrefix Enabling authentication context '$authContextId' for $accessLevel group: $($group.DisplayName)"
                    
                    # Add authentication context to the enablement rule
                    $enablementRule = $currentGroupPolicyParams.rules | Where-Object { $_.id -eq "Enablement_EndUser_Assignment" }
                    if ($enablementRule) {
                        # Add AuthenticationContext to enabled rules
                        $enablementRule.enabledRules += "AuthenticationContext"
                    }
                } else {
                    Write-Verbose "$logPrefix Authentication context enabled but no ID configured for $accessLevel - using MFA + Justification only"
                }
            } else {
                Write-Verbose "$logPrefix Authentication context not enabled for $($group.DisplayName) - enforcing MFA + Justification only"
            }

            try{
                Write-Verbose "$logPrefix Looking up PIM Policies with Assignments"
                $groupPolicyAssignment = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '$($group.Id)' and scopeType eq 'Group'" -OutputType PSObject
                $groupPolicyAssignments += $groupPolicyAssignment
            }catch{
                Write-Verbose "$logPrefix Failed to find PIM Policies with Assignments"
                Write-Error $_
            }
            $memberPolicy = $groupPolicyAssignment|Where-Object{$_.id -like "*member"}
            try{
                Write-Verbose "$logPrefix Updating PIM Policy ID: $($memberPolicy.policyId)"
                Invoke-EntraOpsMsGraphQuery -Method PATCH -Uri "/v1.0/policies/roleManagementPolicies/$($memberPolicy.policyId)" -Body ($currentGroupPolicyParams | ConvertTo-Json -Depth 10) | Out-Null
            }catch{
                Write-Verbose "$logPrefix Failed to update PIM Policy"
                Write-Error $_
            }
        }
    }

    end {
        # When no non-Members groups exist (e.g., all admin groups delegated), nothing to return.
        if (($ServiceGroups | Where-Object { $_.DisplayName -notlike "*Members*" } | Measure-Object).Count -eq 0) {
            return [psobject[]]@()
        }
        # Update-MgPolicyRoleManagementPolicy updates policy rules synchronously — there is no
        # eventual consistency to wait for. The PolicyId (assignment) never changes across the
        # update, so a retry loop comparing PolicyIds is both unnecessary and fragile under
        # transient Graph timeouts. Return the assignments collected during process; fall back
        # to a single fresh lookup if $groupPolicyAssignments is empty (transient failure in process).
        $result = @($groupPolicyAssignments | Where-Object { $_.id -like "*member" })
        if ($result.Count -eq 0) {
            Write-Verbose "$logPrefix groupPolicyAssignments empty — performing single recovery lookup"
            try {
                foreach ($group in $ServiceGroups | Where-Object { $_.DisplayName -notlike "*Members*" }) {
                    $recovery = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '$($group.Id)' and scopeType eq 'Group'" -OutputType PSObject
                    $result += @($recovery | Where-Object { $_.id -like "*member" })
                }
            } catch {
                Write-Verbose "$logPrefix Recovery lookup failed — returning empty result"
                Write-Error $_
            }
        }
        return [psobject[]]$result
    }
}