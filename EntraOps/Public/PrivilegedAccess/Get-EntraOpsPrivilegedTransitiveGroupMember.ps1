<#
.SYNOPSIS
    Get transitive group members of a security group in Microsoft Entra ID.

.DESCRIPTION
    Get transitive group members of a security group in Microsoft Entra ID.
    This covers also direct and nested group members which are eligible or active members in PIM for Groups.

.PARAMETER GroupObjectId
    Object ID of the security group in Microsoft Entra ID.

.EXAMPLE
    Get a list of all direct and nested group members of a security group in Microsoft Entra ID:
    Get-EntaOpsPrivilegedTransitiveGroupMember -GroupObjectId "00000000-0000-0000-0000-000000000000"
#>

function Get-EntraOpsPrivilegedTransitiveGroupMember {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [System.String]$GroupObjectId,

        [Parameter(Mandatory = $False)]
        [System.String]$TenantId,

        [Parameter(Mandatory = $False, DontShow)]
        [string[]]$AncestorObjectIds = @(),

        [Parameter(Mandatory = $False, DontShow)]
        [string[]]$AncestorObjectDisplayNames = @(),

        [Parameter(Mandatory = $False)]
        [System.Collections.Generic.List[psobject]]$WarningMessages
    )

    # Guard against a genuine Entra ID nested-group cycle (e.g. Group A eligible-nests Group B,
    # Group B eligible-nests Group A back) - without this, the recursive expansion below would
    # recurse forever since each group keeps discovering the other as a "new" nested group.
    if ($GroupObjectId -in $AncestorObjectIds) {
        $CycleWarningMessage = "Cycle detected in nested group membership: $GroupObjectId is already an ancestor in the current nesting path ($($AncestorObjectIds -join ' -> ')). Skipping to avoid infinite recursion."
        if ($null -ne $WarningMessages) {
            $WarningMessages.Add([pscustomobject]@{ Timestamp = (Get-Date); Type = "GroupNestingCycle"; ObjectId = $GroupObjectId; Message = $CycleWarningMessage })
        }
        Write-Warning $CycleWarningMessage
        return @()
    }

    # Check details for security group to identify synchronized groups
    try {
        $GroupUri = "/beta/groups/$($GroupObjectId)?`$select=id,displayName,onPremisesSyncEnabled"
        $GroupDetails = Invoke-EntraOpsMsGraphQuery -Method "Get" -Uri $GroupUri -OutputType PSObject | select-object DisplayName, Id, onPremisesSyncEnabled
        Write-Verbose "Get transitive group members of $($GroupDetails.displayName)"
    } catch {
        Write-Error $_
        throw "Group object with ID $($GroupObjectId) can not be found!"
    }

    # Build the current nesting path by appending this group
    $CurrentObjectIds = $AncestorObjectIds + @($GroupObjectId)
    $CurrentObjectDisplayNames = $AncestorObjectDisplayNames + @($GroupDetails.displayName)

    # Check if group is synchronized from on-premises AD and otherwise check if group has member assignments in PIM for Groups
    if ($GroupDetails.onPremisesSyncEnabled -ne $true) {
        if ($__EntraOpsSession.NonPimGroupIds.ContainsKey($GroupObjectId)) {
            # Already confirmed (earlier in this session, possibly via a different nesting/catalog
            # path) that this group has no PIM for Groups eligibility/assignment data - skip the
            # repeat (and, for structurally PIM-incapable groups, always-failing) Graph probe.
            Write-Verbose "Group $($GroupDetails.displayName) previously confirmed to have no PIM for Groups assignments - skipping re-probe"
            $PimForGroupMembers = $null
        } else {
            try {
                Write-Verbose "Try to get identify if $($GroupDetails.displayName) has eligible or active users in PIM for Groups"
                $PimForGroupMembersUri = "/beta/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=groupId eq `'$($GroupObjectId)`'&`$expand=principal"
                $PimForGroupMembers = @(Invoke-EntraOpsMsGraphQuery -Method "Get" -Uri $PimForGroupMembersUri -OutputType PSObject -SuppressBadRequestWarning -ThrowOnFailure)
            } catch {
                # 400 (BadRequest) is Graph's normal answer for this query against a group that is
                # not PIM-capable (not onboarded to PIM for Groups) - not a genuine failure. The
                # response's error message text isn't a stable contract to match against, so treat
                # any 400 from this specific probe URI as "not PIM-capable" rather than pattern-matching it.
                $StatusCode = $_.Exception.Data['StatusCode']
                if ($StatusCode -eq 400) {
                    Write-Verbose "Group $($GroupDetails.displayName) is not PIM-capable - caching the capability result"
                    $__EntraOpsSession.NonPimGroupIds[$GroupObjectId] = $true
                    $PimForGroupMembers = $null
                } else {
                    Write-Error $_
                    throw "Validation of Group object with ID $($GroupObjectId) on eligible or active assignment has been failed"
                }
            }
            if ($null -ne $PimForGroupMembers -and -not $PimForGroupMembers) {
                $__EntraOpsSession.NonPimGroupIds[$GroupObjectId] = $true
            }
        }
    } else {
        Write-Verbose "Group $($GroupDetails.displayName) is synchronized from on-premises AD and can not be managed by PIM for Groups"
    }

    $AllGroupMembers = @()

    # Check direct or nested eligible membership for cloud-only security groups which can be managed by PIM for Groups
    if ($PimForGroupMembers) {

        # Query for roleAssignmentScheduleInstances to get permanent and active members
        $PimForGroupsMembersUri = "/beta/identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=groupId eq `'$($GroupObjectId)`'&`$expand=principal"
        $PimForGroupsMembers = (Invoke-EntraOpsMsGraphQuery -Method "Get" -Uri $PimForGroupsMembersUri -OutputType PSObject)

        #Permanent Members in PIM-managed Group
        Write-Verbose "- Permanent membership"
        $PermanentMembers = ($PimForGroupsMembers | Where-Object { $_.assignmentType -eq "assigned" -and $null -ne $_.principal.Id }).principal | select-object DisplayName, Id, '@odata.type'
        $PermanentMembers | Add-Member -MemberType NoteProperty -Name "RoleAssignmentSubType" -Value "Permanent member" -Force

        #Active Members in PIM-managed Group
        $ActiveMembers = ($PimForGroupsMembers | Where-Object { $_.assignmentType -eq "active" -and $null -ne $_.principal.Id }).principal | select-object DisplayName, Id, '@odata.type'
        $ActiveMembers | Add-Member -MemberType NoteProperty -Name "RoleAssignmentSubType" -Value "Active member" -Force

        # Eligible Member
        Write-Verbose "- Direct eligible membership"
        $EligibleMembersUri = "/beta/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=groupId eq `'$($GroupObjectId)`'&`$expand=principal"
        $EligibleMembers = (Invoke-EntraOpsMsGraphQuery -Method "Get" -Uri $EligibleMembersUri -OutputType PSObject | Where-Object { $_.status -eq "Provisioned" -and $_.accessId -eq "member" -and $null -ne $_.principal.Id }).principal | select-object DisplayName, Id, '@odata.type'
        $EligibleMembers | Add-Member -MemberType NoteProperty -Name "RoleAssignmentSubType" -Value "Eligible member" -Force

        # Check if Eligible Member groups have nested permanent group assignments
        Write-Verbose "- Nested permanent group member of eligible group"
        $EligibleNestedPermanentMembers = $EligibleMembers | Where-Object { $_.'@odata.type' -eq "#microsoft.graph.group" } | ForEach-Object {
            $EligibleNestedPermanentMembersUri = "/beta/groups/$($_.id)/transitiveMembers?`$select=id,displayName,userPrincipalName"
            $EligibleNestedPermanentMember = Invoke-EntraOpsMsGraphQuery -Method "Get" -Uri $EligibleNestedPermanentMembersUri -OutputType PSObject
            $EligibleNestedPermanentMember | Add-Member -MemberType NoteProperty -Name "RoleAssignmentSubType" -Value "Nested Eligible member" -Force
            $NestedNestingIds = $CurrentObjectIds + @($_.id)
            $NestedNestingNames = $CurrentObjectDisplayNames + @($_.displayName)
            $EligibleNestedPermanentMember | Add-Member -MemberType NoteProperty -Name "NestingObjectIds" -Value $NestedNestingIds -Force
            $EligibleNestedPermanentMember | Add-Member -MemberType NoteProperty -Name "NestingObjectDisplayNames" -Value $NestedNestingNames -Force
            $EligibleNestedPermanentMember | Where-Object { $null -ne $_.Id }
        }

        # Summarize all eligible and transitive eligible members of direct or direct nested groups
        $AllGroupMembers = @()
        $AllGroupMembers += $PermanentMembers
        $AllGroupMembers += $ActiveMembers
        $AllGroupMembers += $EligibleMembers
        $AllGroupMembers += $EligibleNestedPermanentMembers

        #region Check if Eligible Member group has eligible member
        Write-Verbose "- Eligible member group has eligible members"

        $NestedMemberGroups = $AllGroupMembers | Where-Object { $_.'@odata.type' -eq "#microsoft.graph.group" }
        $TransitiveNestedEligibleMembers = @()
        foreach ($NestedMemberGroup in $NestedMemberGroups) {
            # A single recursive call is sufficient - Get-EntraOpsPrivilegedTransitiveGroupMember
            # already walks its own nested eligible groups internally (via this same recursive
            # call), so wrapping it in an additional loop here would just re-expand the same
            # group repeatedly without ever progressing to a deeper level.
            Write-Verbose "- Expand nesting for $($NestedMemberGroup.id)"
            $NestedEligibleMembers = Get-EntraOpsPrivilegedTransitiveGroupMember -GroupObjectId $NestedMemberGroup.id -TenantId $TenantId -AncestorObjectIds $CurrentObjectIds -AncestorObjectDisplayNames $CurrentObjectDisplayNames -WarningMessages $WarningMessages
            $NestedEligibleMembers | Add-Member -MemberType NoteProperty -Name "RoleAssignmentSubType" -Value "Nested Eligible group member" -Force

            # Check if nested group is not already in the list
            $NestedEligibleMembers = $NestedEligibleMembers | Where-Object { $_.Id -notin $TransitiveNestedEligibleMembers.Id }
            $TransitiveNestedEligibleMembers += $NestedEligibleMembers
        }
        #endregion

        $AllGroupMembers += $TransitiveNestedEligibleMembers | Where-Object { $_.id -notin $AllGroupMembers.id }

    } else {
        # Permanent Transitive Member
        Write-Verbose "- Transitive permanent membership"
        $TransitivePermanentMembersUri = "/beta/groups/$($GroupObjectId)/transitiveMembers?`$select=id,displayName,userPrincipalName"
        $TransitivePermanentMembers = Invoke-EntraOpsMsGraphQuery -Method "Get" -Uri $TransitivePermanentMembersUri -OutputType PSObject | Where-Object { $null -ne $_.Id } | select-object DisplayName, Id, '@odata.type'
        $TransitivePermanentMembers | Add-Member -MemberType NoteProperty -Name "RoleAssignmentSubType" -Value "Permanent member" -Force

        # No eligible members to add
        $AllGroupMembers += $TransitivePermanentMembers
    }
    #endregion

    # Attach nesting path to members that don't already have it set (from recursive calls)
    foreach ($m in $AllGroupMembers) {
        if ($null -eq $m.NestingObjectIds) {
            $m | Add-Member -MemberType NoteProperty -Name "NestingObjectIds" -Value $CurrentObjectIds -Force
            $m | Add-Member -MemberType NoteProperty -Name "NestingObjectDisplayNames" -Value $CurrentObjectDisplayNames -Force
        }
    }

    return $AllGroupMembers
}