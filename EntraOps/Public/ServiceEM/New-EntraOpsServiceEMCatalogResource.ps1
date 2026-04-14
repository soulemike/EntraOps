<#
.SYNOPSIS
    Registers Entra security groups as resources inside an EM catalog.

.DESCRIPTION
    Submits adminAdd resource requests to onboard each provided Entra group
    as an AadGroup resource inside the specified Entitlement Management
    catalog. Only groups not already registered are onboarded.

    Idempotent: groups already present in the catalog (ResourceAlreadyOnboarded)
    are silently skipped.

    Note: Only owned (non-delegated) groups should be passed. Delegated groups
    are not catalog resources and must not be registered here.

.PARAMETER ServiceGroups
    Entra group objects to register as catalog resources. Pass only the
    $ownedGroups subset from New-EntraOpsServiceBootstrap (IsDelegated -ne true).

.PARAMETER ServiceCatalogId
    Object ID of the Entitlement Management catalog to register resources in.

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsServiceEMCatalogResource `
        -ServiceGroups ($groups | Where-Object { -not $_.IsDelegated }) `
        -ServiceCatalogId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

    Registers all owned service groups as AadGroup resources in the catalog.

#>
function New-EntraOpsServiceEMCatalogResource {
    [OutputType([psobject[]])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [psobject[]]$ServiceGroups,

        [Parameter(Mandatory)]
        [string]$ServiceCatalogId,

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        $resourceRequests = @()
        $resources = @()
        Write-Verbose "$logPrefix Looking up Catalog Resources"
        try{
            #Catalog Resource Registration
            $catalogResourceUri = "/v1.0/identityGovernance/entitlementManagement/catalogs/$ServiceCatalogId/resources?`$expand=roles,scopes"
            $resources += Invoke-EntraOpsMsGraphQuery -Method GET -Uri $catalogResourceUri -OutputType PSObject
        }catch{
            Write-Verbose "$logPrefix Failed to find Catalog Resources"
            Write-Error $_
        }
    }

    process {
        Write-Verbose "$logPrefix Processing $(($ServiceGroups|Measure-Object).Count) Catalog Resources"
        foreach($group in $ServiceGroups){
            $resourceRequestParam = @{
                requestType = "adminAdd"
                resource = @{
                    originId     = $group.Id
                    originSystem = "AadGroup"
                }
                catalog = @{
                    id = $ServiceCatalogId
                }
            }

            if($group.DisplayName -notin $resources.DisplayName){
                $confirmed = $false
                $i = 0
                while(-not $confirmed){
                    Start-Sleep -Seconds ([Math]::Pow(2,$i)-1)
                    try{
                        Write-Verbose "$logPrefix $($group.DisplayName) not found as catalog resource, adding"
                        $result = Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/identityGovernance/entitlementManagement/resourceRequests" -Body ($resourceRequestParam | ConvertTo-Json -Depth 10) -OutputType PSObject -ErrorAction Stop
                        if($null -ne $result){
                            $resourceRequests += $result
                            $confirmed = $true
                            continue
                        }
                        # null return means wrapper absorbed the error as a warning — treat as retriable
                        Write-Verbose "$logPrefix Resource request returned null — will retry"
                    }catch{
                        Write-Verbose "$logPrefix Failed to add catalog resource"
                        if($_.FullyQualifiedErrorId -like "ResourceAlreadyOnboarded*"){
                            Write-Verbose "$logPrefix Resource already onboarded"
                            $confirmed = $true
                            continue
                        }elseif($_.FullyQualifiedErrorId -like "ResourceNotFoundInOriginSystem*"){
                            # Group exists in Graph but has not yet propagated to EM origin system.
                            # This is an expected transient condition after group creation — log only,
                            # do NOT write to the error stream (Write-Error would terminate the caller
                            # when $ErrorActionPreference = "Stop" before the retry loop can run).
                            Write-Verbose "$logPrefix Group not yet indexed by Entitlement Management, will retry"
                        }else{
                            # Unexpected failure — surface as a warning so it is visible without
                            # terminating the caller; the retry loop will still run.
                            Write-Warning "$logPrefix Unexpected error adding catalog resource: $($_.Exception.Message)"
                        }
                    }
                    $i++
                    if($i -gt 8){
                        throw "Group object consistency with Entitlement Management not achieved after $i retries"
                    }
                    Write-Verbose "$logPrefix Group objects not available, sleeping $([Math]::Pow(2,$i)-1) seconds"
                }
            }
        }
    }

    end {
        $confirmed = $false
        $i = 0
        while(-not $confirmed){
            Start-Sleep -Seconds ([Math]::Pow(2,$i)-1)
            $checkResources = @()
            $checkResources = Invoke-EntraOpsMsGraphQuery -Method GET -Uri $catalogResourceUri -OutputType PSObject -DisableCache
            $refNames = @($ServiceGroups.DisplayName | Where-Object { $_ })
            $chkNames = @($checkResources.DisplayName | Where-Object { $_ })
            if($refNames.Count -gt 0 -and $chkNames.Count -ge $refNames.Count -and (Compare-Object $refNames $chkNames | Measure-Object).Count -eq 0){
                Write-Verbose "$logPrefix Graph consistency found confirming"
                $confirmed = $true
                continue
            }
            $i++
            if($i -gt 5){
                throw "Catalog Resource object consistency with Entra not achieved"
            }
            Write-Verbose "$logPrefix Graph objects not available, sleeping $([Math]::Pow(2,$i)-1) seconds"
        }
        return [psobject[]]$checkResources
    }
}