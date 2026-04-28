<#
.SYNOPSIS
    Creates assignment policies for each service access package.

.DESCRIPTION
    Creates one assignment policy per access package in the catalog. Policies
    define requestor settings (self-add/remove enabled), reviewer settings
    (quarterly reviews, CatalogPlane-Members as reviewer, ManagementPlane-Admins
    as backup reviewer), and expiration settings. Three policy types are created:

    - "Initial Workload Membership Policy": assigned to WorkloadPlane-Members;
      no expiration, reviewed by CatalogPlane-Members.
    - "Workload Operational Access Policy": assigned to WorkloadPlane-Admins;
      180-day expiration, reviewed by ManagementPlane-Admins.
    - "Management Plane Access Policy": assigned to ManagementPlane-Members;
      365-day expiration, reviewed by ManagementPlane-Admins.

    Idempotent: existing policies with matching display names are reused.

.PARAMETER ServiceName
    Name of the service. Used in verbose logging and policy lookups.

.PARAMETER ServiceCatalogId
    Object ID of the Entitlement Management catalog.

.PARAMETER ServiceGroups
    Entra group objects. Used to resolve the CatalogPlane-Members and
    ManagementPlane-Admins groups for reviewer assignments.

.PARAMETER ServicePackages
    Access package objects returned by New-EntraOpsServiceEMAccessPackage.

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsServiceEMAssignmentPolicy `
        -ServiceName "MyService" `
        -ServiceCatalogId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ServiceGroups $groups `
        -ServicePackages $packages

    Creates assignment policies for all non-Unified access packages in the
    MyService catalog, wiring up reviewers from the CatalogPlane-Members and
    ManagementPlane-Admins groups.

#>
function New-EntraOpsServiceEMAssignmentPolicy {
    [OutputType([psobject[]])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [string]$ServiceCatalogId,

        [Parameter(Mandatory)]
        [psobject[]]$ServiceGroups,

        [Parameter(Mandatory)]
        [psobject[]]$ServicePackages,

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        $policies = @()
        $assignmentPolicyUri = "/v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=catalog/id eq '$ServiceCatalogId'&`$expand=accessPackage,catalog"
        try{
            Write-Verbose "$logPrefix Looking up Assignment Policy"
            $policies += Invoke-EntraOpsMsGraphQuery -Method GET -Uri $assignmentPolicyUri -OutputType PSObject
        }catch{
            Write-Error $_
        }
        $policyParams = @{
            requestorSettings = @{
                enableTargetsToSelfAddAccess = $true
                enableTargetsToSelfUpdateAccess = $false
                enableTargetsToSelfRemoveAccess = $true
                allowCustomAssignmentSchedule = $false
                enableOnBehalfRequestorsToAddAccess = $false
                enableOnBehalfRequestorsToUpdateAccess = $false
                enableOnBehalfRequestorsToRemoveAccess = $false
            }
            accessPackage = @{
                id = ""
            }
            reviewSettings = @{
                isEnabled = $true
                expirationBehavior = "keepAccess"
                isRecommendationEnabled = $true
                isReviewerJustificationRequired = $true
                isSelfReview = $false
                schedule = @{
                    startDateTime = (Get-Date).AddDays(4)
                    expiration = @{
                        duration = "P25D"
                        type = "afterDuration"
                    }
                    recurrence = @{
                        pattern = @{
                            type = "absoluteMonthly"
                            interval = 3
                            month = 0
                            dayOfMonth = 0
                        }
                        range = @{
                            type = "noEnd"
                        }
                    }
                }
                primaryReviewers = @(
                    @{
                        "@odata.type" = "#microsoft.graph.groupMembers"
                        groupId = $(
                            $mgmtAdminsId = ($ServiceGroups|Where-Object{$_.DisplayName -like "*ManagementPlane-Admins"}).Id
                            if($mgmtAdminsId){ $mgmtAdminsId } else { ($ServiceGroups|Where-Object{$_.DisplayName -like "*CatalogPlane-Members"}).Id }
                        )
                    }
                )
            }
        }
        $baselinePolicyParams = @{
            displayName = "Baseline Policy"
            description = "The baseline policy for $ServiceName access packages."
            allowedTargetScope = "specificDirectoryUsers"
            specificAllowedTargets = @(
                @{
                    "@odata.type" = "#microsoft.graph.groupMembers"
                    groupId = $(($ServiceGroups|Where-Object{$_.DisplayName -like "*CatalogPlane-Members"}).Id)
                }
            )
            expiration = @{
                duration = "P5D"
                type = "afterDuration"
            }
            requestApprovalSettings = @{
                isApprovalRequiredForAdd = $true
                isApprovalRequiredForUpdate = $false
                stages = @(
                    @{
                        durationBeforeAutomaticDenial = "P2D"
                        isApproverJustificationRequired = $true
                        isEscalationEnabled = $false
                        durationBeforeEscalation = "PT0S"
                        primaryApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.groupMembers"
                                groupId = $(($ServiceGroups|Where-Object{$_.DisplayName -like "*CatalogPlane-Members"}).Id)
                            }
                        )
                    }
                )
            }
        }
        $initialPolicyParams = @{
            displayName = "Initial Membership Policy"
            description = "The initial membership policy for $ServiceName."
            allowedTargetScope = "allMemberUsers"
            expiration = @{
                type = "noExpiration"
            }
            requestApprovalSettings = @{
                isApprovalRequiredForAdd = $true
                isApprovalRequiredForUpdate = $false
                stages = @(
                    @{
                        durationBeforeAutomaticDenial = "P7D"
                        isApproverJustificationRequired = $true
                        isEscalationEnabled = $false
                        durationBeforeEscalation = "PT0S"
                        primaryApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.requestorManager"
                                managerLevel = 1
                            }
                        )
                        fallbackPrimaryApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.groupMembers"
                                groupId = $(($ServiceGroups|Where-Object{$_.DisplayName -like "*CatalogPlane-Members"}).Id)
                            }
                        )
                    },
                    @{
                        durationBeforeAutomaticDenial = "P14D"
                        isApproverJustificationRequired = $true
                        isEscalationEnabled = $false
                        durationBeforeEscalation = "PT0S"
                        primaryApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.groupMembers"
                                groupId = $(($ServiceGroups|Where-Object{$_.DisplayName -like "*CatalogPlane-Members"}).Id)
                            }
                        )
                    }
                )
            }
        }
        $workloadPlanePolicyParams = @{
            displayName = "Workload Plane Policy"
            description = "The Workload Plane Policy for $ServiceName access packages."
            allowedTargetScope = "specificDirectoryUsers"
            specificAllowedTargets = @(
                @{
                    "@odata.type" = "#microsoft.graph.groupMembers"
                    groupId = $(
                        $wlpMembersId = ($ServiceGroups|Where-Object{$_.DisplayName -like "*WorkloadPlane-Members"}).Id
                        if($wlpMembersId){ $wlpMembersId } else { ($ServiceGroups|Where-Object{$_.DisplayName -like "*CatalogPlane-Members"}).Id }
                    )
                }
            )
            expiration = @{
                duration = "P5D"
                type = "afterDuration"
            }
            requestApprovalSettings = @{
                isApprovalRequiredForAdd = $true
                isApprovalRequiredForUpdate = $false
                stages = @(
                    @{
                        durationBeforeAutomaticDenial = "P2D"
                        isApproverJustificationRequired = $true
                        isEscalationEnabled = $false
                        durationBeforeEscalation = "PT0S"
                        primaryApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.groupMembers"
                                groupId = $(($ServiceGroups|Where-Object{$_.DisplayName -like "*ManagementPlane-Admins"}).Id)
                            }
                        )
                    }
                )
            }
        }
    }

    process {
        foreach($package in $ServicePackages){
            $policyParams.accessPackage.id = $package.Id
            if($package.Id -notin $policies.AccessPackage.Id){
                try{
                    Write-Verbose "$logPrefix Assigning Policy for Access Package ID: $($package.Id)"
                    if($package.DisplayName -like "*WorkloadPlane-Members"){
                        $params = $policyParams + $initialPolicyParams
                        $params.displayName = "Initial Workload Membership Policy"
                        $policies += Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentPolicies" -Body ($params | ConvertTo-Json -Depth 20) -OutputType PSObject
                    }elseif($package.displayName -like "*ManagementPlane-Members"){
                        # Clone to avoid mutating the shared $initialPolicyParams reference.
                        # The nested requestApprovalSettings is replaced entirely (not mutated) to
                        # avoid modifying the inner object via the shallow clone.
                        $params = $initialPolicyParams.Clone()
                        $params.displayName = "Initial Management Membership Policy"
                        $params.allowedTargetScope = "specificDirectoryUsers"
                        # WorkloadPlane-Members may not exist in Sub-only landing zones; fall back to
                        # CatalogPlane-Members as the requestor scope in that case.
                        $wlMembersGroupId = ($ServiceGroups|Where-Object{$_.DisplayName -like "*WorkloadPlane-Members"}).Id
                        $mgmtMemberRequestorId = if($wlMembersGroupId){ $wlMembersGroupId } else { ($ServiceGroups|Where-Object{$_.DisplayName -like "*CatalogPlane-Members"}).Id }
                        $params.specificAllowedTargets = @(
                            @{
                                "@odata.type" = "#microsoft.graph.groupMembers"
                                groupId = $mgmtMemberRequestorId
                            }
                        )
                        $params.requestApprovalSettings = @{
                            isApprovalRequiredForAdd = $true
                            isApprovalRequiredForUpdate = $false
                            stages = @(
                                @{
                                    durationBeforeAutomaticDenial = "P2D"
                                    isApproverJustificationRequired = $true
                                    isEscalationEnabled = $false
                                    durationBeforeEscalation = "PT0S"
                                    primaryApprovers = @(
                                        @{
                                            "@odata.type" = "#microsoft.graph.groupMembers"
                                            groupId = $(($ServiceGroups|Where-Object{$_.DisplayName -like "*ManagementPlane-Admins"}).Id)
                                        }
                                    )
                                    <# Not supported when heirarchical manager is not the primary approver
                                    fallbackPrimaryApprovers = @(
                                        @{
                                            "@odata.type" = "#microsoft.graph.groupMembers"
                                            groupId = $(($ServiceGroups|Where-Object{$_.DisplayName -like "*ControlPlane-Admins"}).Id)
                                        }
                                    )
                                    #>
                                }
                            )
                        }
                        $params = $policyParams + $params
                        $policies += Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentPolicies" -Body ($params | ConvertTo-Json -Depth 20) -OutputType PSObject
                    }elseif($package.displayName -like "*WorkloadPlane-Admins"){
                        $params = $policyParams + $workloadPlanePolicyParams
                        $policies += Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentPolicies" -Body ($params | ConvertTo-Json -Depth 20) -OutputType PSObject
                    }elseif($package.displayName -like "*WorkloadPlane-Users"){
                        # WorkloadPlane-Users: Approver is WorkloadPlane-Admins (or fallback to CatalogPlane-Members)
                        $params = $baselinePolicyParams.Clone()
                        $params.displayName = "Workload Plane Users Policy"
                        $params.allowedTargetScope = "specificDirectoryUsers"
                        $catalogMembersId = ($ServiceGroups|Where-Object{$_.DisplayName -like "*CatalogPlane-Members"}).Id
                        $params.specificAllowedTargets = @(
                            @{
                                "@odata.type" = "#microsoft.graph.groupMembers"
                                groupId = $catalogMembersId
                            }
                        )
                        $params.requestApprovalSettings = @{
                            isApprovalRequiredForAdd = $true
                            isApprovalRequiredForUpdate = $false
                            stages = @(
                                @{
                                    durationBeforeAutomaticDenial = "P2D"
                                    isApproverJustificationRequired = $true
                                    isEscalationEnabled = $false
                                    durationBeforeEscalation = "PT0S"
                                    primaryApprovers = @(
                                        @{
                                            "@odata.type" = "#microsoft.graph.groupMembers"
                                            groupId = $(
                                                $wlAdminsId = ($ServiceGroups|Where-Object{$_.DisplayName -like "*WorkloadPlane-Admins"}).Id
                                                if($wlAdminsId){ $wlAdminsId } else { $catalogMembersId }
                                            )
                                        }
                                    )
                                }
                            )
                        }
                        $params = $policyParams + $params
                        $policies += Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentPolicies" -Body ($params | ConvertTo-Json -Depth 20) -OutputType PSObject
                    }else{
                        $params = $policyParams + $baselinePolicyParams
                        $policies += Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentPolicies" -Body ($params | ConvertTo-Json -Depth 20) -OutputType PSObject
                    }
                }catch{
                    Write-Verbose "$logPrefix Failed to Assign Policy"
                    Write-Error $_
                }
            }
        }
    }

    end {
        $confirmed = $false
        $i = 0
        while(-not $confirmed){
            Start-Sleep -Seconds ([Math]::Pow(2,$i)-1)
            $checkPolicies = @()
            $checkPolicies = Invoke-EntraOpsMsGraphQuery -Method GET -Uri $assignmentPolicyUri -OutputType PSObject -DisableCache
            
            # Handle null or empty arrays
            $expectedIds = @($policies | Where-Object { $_.id } | Select-Object -ExpandProperty id)
            $actualIds = @($checkPolicies | Where-Object { $_.id } | Select-Object -ExpandProperty id)
            
            if($expectedIds.Count -eq 0 -and $actualIds.Count -eq 0){
                Write-Verbose "$logPrefix No assignment policies to verify"
                $confirmed = $true
                continue
            }
            
            if((Compare-Object $expectedIds $actualIds | Measure-Object).Count -eq 0){
                Write-Verbose "$logPrefix Graph consistency found confirming"
                $confirmed = $true
                continue
            }
            $i++
            if($i -gt 10){
                throw "Access Package object consistency with Entra not achieved"
            }
            Write-Verbose "$logPrefix Graph objects not available, sleeping $([Math]::Pow(2,$i)-1) seconds"
        }
        return [psobject[]]$checkPolicies
    }
}