<#
.SYNOPSIS
    Removes an Entitlement Management catalog, all its contents, and the associated Entra groups.

.DESCRIPTION
    Performs a complete teardown of an Entitlement Management catalog:
    1. Revokes all active (non-expired) access package assignments via
       adminRemove requests and waits for them to reach Fulfilled state.
    2. Deletes all access packages in the catalog.
    3. Deletes the catalog itself.
    4. Deletes all Entra groups that were registered as catalog resources,
       except any group whose Object ID appears in ExcludeGroupIds (used to
       protect shared delegation/persona groups such as ControlPlane-Admins,
       ManagementPlane-Admins, or CatalogPlane-Members).

    Requires the -Force switch to prevent accidental deletion.
    Intended for decommissioning services provisioned by New-EntraOpsServiceBootstrap.

.PARAMETER ServiceCatalogName
    Display name of the catalog to remove (e.g. "Catalog-MyService").

.PARAMETER Force
    Must be specified to proceed. Without this switch the function warns and
    returns an empty object without making any changes.

.PARAMETER ExcludeGroupIds
    Object IDs of Entra groups that must not be deleted even if they are
    registered as catalog resources. Use this to protect shared delegation
    groups (ControlPlane-Admins, ManagementPlane-Admins, CatalogPlane-Members)
    that are reused across multiple services.

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    Remove-EntraOpsServiceCatalog -ServiceCatalogName "Catalog-MyService" -Force

    Revokes all active assignments, deletes all access packages, removes the
    catalog, and deletes all associated Entra groups.

.EXAMPLE
    Remove-EntraOpsServiceCatalog -ServiceCatalogName "Catalog-MyService" -Force `
        -ExcludeGroupIds @(
            "00000000-0000-0000-0000-000000000001",  # ControlPlane-Admins (shared)
            "00000000-0000-0000-0000-000000000002"   # ManagementPlane-Admins (shared)
        )

    Same as above but skips deletion of the two shared delegation groups.

.EXAMPLE
    Remove-EntraOpsServiceCatalog -ServiceCatalogName "Catalog-MyService"

    Outputs a warning and returns without making any changes (dry-run behaviour).

#>
function Remove-EntraOpsServiceCatalog {
    [OutputType([psobject[]])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceCatalogName,

        [switch]$Force,

        [string[]]$ExcludeGroupIds = @(),

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    process {
        if(-not $force){
            Write-Warning "$logPrefix Catalog and all associated assignments will be deleted, please use -Force switch to proceed"
            return @{}
        }
        $catalog = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/identityGovernance/entitlementManagement/catalogs?`$filter=displayName eq '$ServiceCatalogName'&`$expand=accessPackages,resources" -OutputType PSObject -DisableCache
        if(($catalog|Measure-Object).Count -eq 0){
            Write-Warning "$logPrefix Unable to obtain catalog by name"
            return @{}
        }
        Write-Verbose "$logPrefix Obtained Service Catalog $($catalog.Id)"

        # Terminal states for assignment requests — any of these means processing is done (success or failure).
        # Graph EM uses camelCase; comparisons are case-insensitive via -iin/-inotin equivalents.
        $terminalStates = @("fulfilled","delivered","canceled","deliveryfailed","denied","completed","partiallydelivered","dropped")

        # Step 1: Submit ALL adminRemove requests across all packages at once.
        $allRemoveRequestIds = [System.Collections.Generic.List[string]]::new()
        foreach($accessPackage in $catalog.accessPackages){
            # Filtering by navigation path 'accessPackage/id' requires ConsistencyLevel:eventual + $count=true.
            $assignments = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/identityGovernance/entitlementManagement/assignments?`$count=true&`$filter=accessPackage/id eq '$($accessPackage.Id)'&`$expand=target" -OutputType PSObject -DisableCache -ConsistencyLevel "eventual"
            foreach($assignment in @($assignments) | Where-Object { $_ -and ($_.state -ine "expired") }){
                Write-Verbose "$logPrefix Queuing adminRemove for $($assignment.target.displayName) [$($assignment.target.email)] in $($accessPackage.displayName)"
                $params = @{ requestType = "adminRemove"; assignment = @{id = $assignment.id} }
                $req = Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentRequests" -Body ($params | ConvertTo-Json -Depth 10) -OutputType PSObject
                if($req -and $req.id){
                    $allRemoveRequestIds.Add($req.id)
                } else {
                    Write-Warning "$logPrefix adminRemove POST returned null for assignment '$($assignment.id)' — skipping"
                }
            }
        }

        # Step 2: Wait for ALL removal requests to reach a terminal state (single polling loop).
        if($allRemoveRequestIds.Count -gt 0){
            Write-Verbose "$logPrefix Waiting for $($allRemoveRequestIds.Count) assignment removal request(s) to complete"
            $i = 0
            $confirmed = $false
            while(-not $confirmed){
                Start-Sleep -Seconds ([Math]::Pow(2, $i))
                $pending = @($allRemoveRequestIds | ForEach-Object {
                    Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/identityGovernance/entitlementManagement/assignmentRequests/$_" -OutputType PSObject -DisableCache
                } | Where-Object { $_ -and ($terminalStates -notcontains $_.status.ToLower()) })
                if($pending.Count -eq 0){
                    Write-Verbose "$logPrefix All assignment removals reached terminal state"
                    $confirmed = $true
                } else {
                    $i++
                    if($i -gt 9){
                        Write-Warning "$logPrefix $($pending.Count) assignment removal(s) still pending after max retries — proceeding anyway"
                        break
                    }
                    Write-Verbose "$logPrefix $($pending.Count) removal(s) still pending, sleeping $([Math]::Pow(2,$i)) seconds"
                }
            }
        }

        # Step 3: Delete each access package (remove resource role scopes first — Graph 400s otherwise).
        foreach($accessPackage in $catalog.accessPackages){
            $resourceRoleScopes = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/identityGovernance/entitlementManagement/accessPackages/$($accessPackage.Id)/resourceRoleScopes" -OutputType PSObject -DisableCache
            foreach ($rrs in @($resourceRoleScopes) | Where-Object { $_ -and $_.Id }) {
                Write-Verbose "$logPrefix Removing resource role scope $($rrs.Id) from $($accessPackage.displayName)"
                Invoke-EntraOpsMsGraphQuery -Method DELETE -Uri "/v1.0/identityGovernance/entitlementManagement/accessPackages/$($accessPackage.Id)/resourceRoleScopes/$($rrs.Id)" | Out-Null
            }
            Write-Verbose "$logPrefix Deleting $($accessPackage.displayName) [$($accessPackage.Id)]"
            Invoke-EntraOpsMsGraphQuery -Method DELETE -Uri "/v1.0/identityGovernance/entitlementManagement/accessPackages/$($accessPackage.Id)" | Out-Null
        }

        # Step 4: Delete the catalog.
        Write-Verbose "$logPrefix Deleting Catalog"
        Invoke-EntraOpsMsGraphQuery -Method DELETE -Uri "/v1.0/identityGovernance/entitlementManagement/catalogs/$($catalog.Id)" | Out-Null

        # Step 5: Delete associated Entra groups.
        Write-Verbose "$logPrefix Deleting associated Entra groups from catalog resources"
        foreach ($resource in $catalog.Resources | Where-Object { $_.OriginSystem -eq "AadGroup" }) {
            if ($resource.OriginId -in $ExcludeGroupIds) {
                Write-Verbose "$logPrefix Skipping excluded group: $($resource.DisplayName) [$($resource.OriginId)]"
                continue
            }
            try {
                Write-Verbose "$logPrefix Deleting group: $($resource.DisplayName) [$($resource.OriginId)]"
                Invoke-EntraOpsMsGraphQuery -Method DELETE -Uri "/v1.0/groups/$($resource.OriginId)" | Out-Null
            } catch {
                Write-Verbose "$logPrefix Failed to delete group $($resource.DisplayName) [$($resource.OriginId)]"
                Write-Error $_
            }
        }
    }

    end {
        return @{}
    }
}
