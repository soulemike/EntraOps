<#
.SYNOPSIS
    Creates PIM for Groups eligible assignments for service admin groups.

.DESCRIPTION
    For each non-Members group in ServiceGroups, creates a PIM for Groups
    eligible assignment with no expiration. The principal assigned is the
    corresponding Members group (or, for PIM staging groups named
    *-PIM-<AccessLevel>-<Role>, the non-PIM group that matches the same
    AccessLevel-Role suffix).

    Idempotent: existing noExpiration eligible assignments are detected and
    skipped.

    When all admin groups have been delegated externally and no non-Members
    groups remain, the function returns an empty array without error.

.PARAMETER ServiceGroups
    All service group objects (owned groups only — delegated groups must be
    excluded). PIM staging groups (*-PIM-*) are automatically matched to
    their base group.

.PARAMETER ServiceOwnerPrincipalId
    Object ID of the service owner. Required when -EnableOwnerAssignment is set.
    When provided, an eligible-owner assignment is created so the service owner
    can activate ownership of each admin group via PIM.

.PARAMETER EnableOwnerAssignment
    When set, creates PIM for Groups eligible-owner assignments for the service owner
    in addition to the default eligible-member assignments for the Members group.
    Disabled by default — use this switch to opt in.

.PARAMETER GroupPrefix
    Prefix used in group DisplayNames (e.g. "SG"). Must match the prefix
    passed to New-EntraOpsServiceBootstrap. Defaults to "SG".

.PARAMETER GroupNamingDelimiter
    Delimiter between group name segments (e.g. "-"). Defaults to "-".

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsServicePIMAssignment -ServiceGroups $ownedGroups

    Creates PIM eligible assignments so that members of SG-MyService-WorkloadPlane-Members
    can activate membership in SG-MyService-WorkloadPlane-Admins via PIM.

#>
function New-EntraOpsServicePIMAssignment {
    [OutputType([psobject[]])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [psobject[]]$ServiceGroups,

        [string]$GroupPrefix = "SG",
        [string]$GroupNamingDelimiter = "-",

        [string]$ServiceOwnerPrincipalId = "",

        [switch]$EnableOwnerAssignment,

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        $pimEligibilities = @()

        $pimEligibilityParams = @{
            accessId = "member"
            principalId = ($ServiceGroups|Where-Object{$_.DisplayName -like "* Members"}).Id
            groupId = ""
            action = "AdminAssign"
            scheduleInfo = @{
                startDateTime = (Get-Date).AddHours(-1).ToString("o")
                expiration = @{
                    type = "noExpiration"
                }
            }
        }
    }

    process {
        foreach($group in $ServiceGroups|Where-Object{$_.DisplayName -notlike "*Members*"}){
            $pimEligibilityParams.groupId = $group.Id
            Write-Verbose "$logPrefix Looking up eligibility for group ID: $($group.Id)"
            $pimEligibilities += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests?`$filter=groupId eq '$($group.Id)'&`$expand=group,principal,targetSchedule" -OutputType PSObject -DisableCache
        
            if($group.DisplayName -like "*-PIM-*"){
                $pimGroupPrefixLen = "$GroupPrefix$($GroupNamingDelimiter)PIM$GroupNamingDelimiter".Length
                $pimEligibilityParams.principalId = ($ServiceGroups|Where-Object{$_.DisplayName -like "$GroupPrefix$GroupNamingDelimiter"+$group.DisplayName.Substring($pimGroupPrefixLen)}).Id
            }
            $ne = $pimEligibilityParams.principalId+"_noExpiration"
            # Scope check to current group only — accumulated $pimEligibilities spans all groups,
            # so checking the full array causes the second group to incorrectly skip its POST
            # because the first group's matching entry is already present.
            $ee = $pimEligibilities | Where-Object { $_.groupId -eq $group.Id } | ForEach-Object { $_.principalId+"_"+$_.targetSchedule.scheduleInfo.expiration.type }
            if($ne -notin $ee){
                Write-Verbose "$logPrefix $($pimEligibilityParams|ConvertTo-Json -Compress)"
                Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests" -Body ($pimEligibilityParams | ConvertTo-Json -Depth 10) -OutputType PSObject | Out-Null
                $pimEligibilities += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests?`$filter=groupId eq '$($group.Id)'&`$expand=group,principal,targetSchedule" -OutputType PSObject -DisableCache
            }

            # Eligible-owner assignment for the service owner (opt-in only).
            if($EnableOwnerAssignment -and -not [string]::IsNullOrWhiteSpace($ServiceOwnerPrincipalId)){
                $ownerParams = @{
                    accessId    = "owner"
                    principalId = $ServiceOwnerPrincipalId
                    groupId     = $group.Id
                    action      = "AdminAssign"
                    scheduleInfo = @{
                        startDateTime = (Get-Date).AddHours(-1).ToString("o")
                        expiration    = @{ type = "noExpiration" }
                    }
                }
                $neOwner = $ServiceOwnerPrincipalId + "_noExpiration"
                $eeOwner = $pimEligibilities | Where-Object { $_.groupId -eq $group.Id -and $_.accessId -eq "owner" } | ForEach-Object { $_.principalId+"_"+$_.targetSchedule.scheduleInfo.expiration.type }
                if($neOwner -notin $eeOwner){
                    Write-Verbose "$logPrefix Creating owner eligible assignment for $ServiceOwnerPrincipalId on group $($group.Id)"
                    Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests" -Body ($ownerParams | ConvertTo-Json -Depth 10) -OutputType PSObject | Out-Null
                    $pimEligibilities += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests?`$filter=groupId eq '$($group.Id)'&`$expand=group,principal,targetSchedule" -OutputType PSObject -DisableCache
                }
            }
        }
    }

    end {
        $confirmed = $false
        $i = 0
        # When no non-Members groups exist (e.g., all admin groups delegated), skip consistency check.
        if (($ServiceGroups | Where-Object { $_.DisplayName -notlike "*Members*" } | Measure-Object).Count -eq 0) {
            return [psobject[]]@()
        }
        while(-not $confirmed){
            Start-Sleep -Seconds ([Math]::Pow(2,$i)-1)
            $checkPimEligibility = @()
            foreach($group in $ServiceGroups|Where-Object{$_.DisplayName -notlike "*Members*"}){
                $checkPimEligibility += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests?`$filter=groupId eq '$($group.Id)'&`$expand=group,principal,targetSchedule" -OutputType PSObject -DisableCache
            }
            if((Compare-Object @($pimEligibilities.id) @($checkPimEligibility.id) | Measure-Object).Count -eq 0){
                Write-Verbose "$logPrefix Graph consistency found confirming"
                $confirmed = $true
                continue
            }
            $i++
            if($i -gt 5){
                throw "Access Package object consistency with Entra not achieved"
            }
            Write-Verbose "$logPrefix Graph objects not available, sleeping $([Math]::Pow(2,$i)-1) seconds"
        }
        return [psobject[]]$checkPimEligibility
    }
}