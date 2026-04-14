<#
.SYNOPSIS
    Assigns service members and the service owner to their initial access packages.

.DESCRIPTION
    Submits adminAdd assignment requests to place service members into the
    WorkloadPlane-Members access package and the service owner into the
    WorkloadPlane-Members package (unless already assigned). Uses the
    "Initial Workload Membership Policy" assignment policy. Skipped gracefully
    when no WorkloadPlane-Members package or policy exists (e.g. Sub-only
    landing zones).

    Idempotent: existing delivered assignments are detected and skipped.

.PARAMETER ServiceCatalogId
    Object ID of the Entitlement Management catalog. Used to scope assignment
    lookups so only assignments from this catalog are considered.

.PARAMETER ServiceMembers
    Graph User objects to assign to the WorkloadPlane-Members access package.
    Typically the output of Get-MgUser for each service member UPN.

.PARAMETER ServiceOwner
    Graph User object for the service owner. Added to WorkloadPlane-Members
    unless already present via ServiceMembers.

.PARAMETER ServiceAssignmentPolicies
    Assignment policy objects returned by New-EntraOpsServiceEMAssignmentPolicy.

.PARAMETER ServicePackages
    Access package objects returned by New-EntraOpsServiceEMAccessPackage.

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsServiceEMAssignment `
        -ServiceCatalogId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ServiceMembers $graphMembers `
        -ServiceOwner $graphOwner `
        -ServiceAssignmentPolicies $policies `
        -ServicePackages $packages

    Assigns every user in $graphMembers (plus the owner) to the
    AP-<ServiceName>-WorkloadPlane-Members access package via adminAdd.

#>
function New-EntraOpsServiceEMAssignment {
    [OutputType([psobject[]])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceCatalogId,

        [Parameter(Mandatory)]
        [psobject[]]$ServiceMembers,

        [Parameter(Mandatory)]
        [psobject]$ServiceOwner,

        [Parameter(Mandatory)]
        [psobject[]]$ServiceAssignmentPolicies,
        
        [Parameter(Mandatory)]
        [psobject[]]$ServicePackages,

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        $assignmentRequests = @()
        $assignments = @()

        $assignmentRequestsUri = "/v1.0/identityGovernance/entitlementManagement/assignmentRequests?`$filter=state eq 'submitted'&`$expand=assignment(`$expand=target),accessPackage,assignment"
        try{
            Write-Verbose "$logPrefix Looking up Assignment Requests"
            $assignmentRequests += Invoke-EntraOpsMsGraphQuery -Method GET -Uri $assignmentRequestsUri -OutputType PSObject
        }catch{
            Write-Verbose "$logPrefix Failed to find Assignment Requests"
            Write-Error $_
        }

        $assignmentsSplat = "/v1.0/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/catalog/id eq '$ServiceCatalogId' and state eq 'delivered'&`$expand=accessPackage(`$expand=catalog),accessPackage,target"
        Write-Verbose "$logPrefix $($assignmentsSplat)"
        try{
            $assignments += Invoke-EntraOpsMsGraphQuery -Method GET -Uri $assignmentsSplat -OutputType PSObject
            if(($assignments|Measure-Object).Count -gt 0){
                Write-Verbose "$logPrefix Found Access Package Assignment IDs: $($assignments.Id|ConvertTo-Json -Compress)"
            }
        }catch{
            Write-Verbose "$logPrefix Failed to find Assignments"
            Write-Error $_
        }

        $wlMembersPackage = $ServicePackages|Where-Object{$_.DisplayName -like "*WorkloadPlane-Members"}
        $wlMembersPolicy  = $ServiceAssignmentPolicies|Where-Object{$_.DisplayName -eq "Initial Workload Membership Policy"}
        # Rg scope fallback: no WorkloadPlane-Members access package → use WorkloadPlane-Users
        if(-not $wlMembersPackage){
            $wlMembersPackage = $ServicePackages|Where-Object{$_.DisplayName -like "*WorkloadPlane-Users"}
            $wlMembersPolicy  = $ServiceAssignmentPolicies|Where-Object{$_.DisplayName -eq "Workload Plane Users Policy"}
        }
        $assignmentParams = @{
            requestType = "adminAdd"
            assignment = @{
                targetId = ""
                assignmentPolicyId = $wlMembersPolicy.Id
                accessPackageId    = $wlMembersPackage.Id
            }
        }
        # Track how many new requests were actually submitted so the end block can exit
        # immediately when nothing was created (avoids an infinite wait).
        $newAssignmentCount = 0
    }

    process {
        if(-not $wlMembersPackage -or -not $wlMembersPolicy){
            Write-Verbose "$logPrefix WorkloadPlane-Members access package or policy not found (Sub-only landing zone?), skipping member assignments"
        } else {
            foreach($member in $ServiceMembers){
                Write-Verbose "$logPrefix Processing Service Member ID: $($member.Id)"
                $assignmentParams.assignment.targetId = $member.Id
                if($member.Id -notin $assignments.Target.ObjectId -and $member.Id -notin $assignmentRequests.Assignment.Target.ObjectId){
                    try{
                        Write-Verbose "$logPrefix Creating Assignment Request"
                        $postResult = Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentRequests" -Body ($assignmentParams | ConvertTo-Json -Depth 10) -OutputType PSObject
                        if($null -ne $postResult){ $assignmentRequests += $postResult; $newAssignmentCount++ }
                    }catch{
                        Write-Verbose "$logPrefix Failed to create Assignment Request"
                        Write-Error $_
                    }
                }
            }
        }

        # Enroll the owner: prefer ManagementPlane-Admins; fall back to WorkloadPlane-Admins
        # (Rg scope with Centralized governance — no ManagementPlane-Admins package is created).
        $mgmtAdminsPackage = $ServicePackages|Where-Object{$_.DisplayName -like "*ManagementPlane-Admins"}
        $mgmtAdminsPolicy  = $ServiceAssignmentPolicies|Where-Object{$_.DisplayName -eq "Initial Management Admin Policy"}
        if(-not $mgmtAdminsPackage){
            $mgmtAdminsPackage = $ServicePackages|Where-Object{$_.DisplayName -like "*WorkloadPlane-Admins"}
            $mgmtAdminsPolicy  = $ServiceAssignmentPolicies|Where-Object{$_.DisplayName -eq "Workload Plane Policy"}
        }
        if($mgmtAdminsPackage -and $mgmtAdminsPolicy){
            # Update this to `in` if upstream function ever switches to array
            if($ServiceOwner.Id -notin $assignments.Target.ObjectId -and $ServiceOwner.Id -notin $assignmentRequests.Assignment.Target.ObjectId){
                try{
                    $assignmentParams.assignment.targetId = $ServiceOwner.Id
                    $assignmentParams.assignment.assignmentPolicyId = $mgmtAdminsPolicy.Id
                    $assignmentParams.assignment.accessPackageId = $mgmtAdminsPackage.Id
                    Write-Verbose "$logPrefix Creating Assignment Request for Service Owner - $($assignmentParams|ConvertTo-Json -Compress)"
                    $postResult = Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentRequests" -Body ($assignmentParams | ConvertTo-Json -Depth 10) -OutputType PSObject
                    if($null -ne $postResult){ $assignmentRequests += $postResult; $newAssignmentCount++ }
                }catch{
                    Write-Verbose "$logPrefix Failed to create Assignment Request for Service Owner"
                    Write-Error $_
                }
            }
        } else {
            Write-Verbose "$logPrefix No suitable owner access package found (ManagementPlane-Admins / WorkloadPlane-Admins), skipping owner assignment"
        }
    }

    end {
        # Nothing was submitted in this run — no point waiting for fulfillment.
        if($newAssignmentCount -eq 0){
            Write-Verbose "$logPrefix No new assignment requests submitted, skipping consistency check"
            return [psobject[]]@()
        }

        $confirmed = $false
        $i = 0
        while(-not $confirmed){
            Start-Sleep -Seconds ([Math]::Pow(2,$i)-1)
            $checkAssignments = @()
            $checkAssignments += Invoke-EntraOpsMsGraphQuery -Method GET -Uri $assignmentsSplat -OutputType PSObject -DisableCache
            $uniqueExpected = @(($ServiceMembers.Id + $ServiceOwner.Id) | Where-Object { $_ } | Sort-Object -Unique)
            $uniqueFound    = @($checkAssignments.Target.ObjectId | Where-Object { $_ } | Sort-Object -Unique)
            Write-Verbose "$logPrefix Expected assignee IDs: $($uniqueExpected|ConvertTo-Json -Compress)"
            Write-Verbose "$logPrefix Found assignment target IDs: $($uniqueFound|ConvertTo-Json -Compress)"
            $missing = @($uniqueExpected | Where-Object { $_ -notin $uniqueFound })
            if($missing.Count -eq 0){
                Write-Verbose "$logPrefix Graph consistency found confirming"
                $confirmed = $true
                continue
            }
            $i++
            if($i -eq 5){
                Write-Warning "$logPrefix Fulfillment can take 5+ minutes to complete"
            }
            if($i -gt 9){
                throw "Access Package Assignment consistency with Entra not achieved"
            }
            Write-Verbose "$logPrefix Graph objects not available, sleeping $([Math]::Pow(2,$i)-1) seconds"
        }
        return [psobject[]]$checkAssignments
    }
}