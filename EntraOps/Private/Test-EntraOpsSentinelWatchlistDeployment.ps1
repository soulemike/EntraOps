<#
.SYNOPSIS
    Verify that a deployed Sentinel watchlist contains as many items as were exported to CSV.

.DESCRIPTION
    New-GkSeAzSentinelWatchlist (SentinelEnrichment) splits a CSV larger than ~1 MB into several blocks and
    deploys each one as an ARM template deployment that reuses a single deployment name - the watchlist
    display name. Observed behaviour is that a block can be reported as deployed while its deployment is
    still in "running" state, after which the next block starts a deployment under the same name. That race
    can drop the rows of an earlier block without surfacing any error.

    This helper closes the gap on the EntraOps side: it counts the items actually present in the watchlist
    and warns when the count does not match what was exported. It never throws - a verification problem must
    not fail a sync that may well have succeeded - so callers get a warning plus the returned count.

    Counting means paging the whole watchlist, which costs one request per page, so verification is limited
    to watchlists large enough to be split. A CSV below SplitThresholdBytes is deployed as a single ARM
    deployment, cannot hit the race, and is skipped.

.PARAMETER SubscriptionId
    Subscription of the Log Analytics workspace hosting the watchlist.

.PARAMETER ResourceGroupName
    Resource group of the Log Analytics workspace hosting the watchlist.

.PARAMETER WorkspaceName
    Name of the Log Analytics workspace hosting the watchlist.

.PARAMETER WatchListName
    Alias/display name of the watchlist to verify.

.PARAMETER ExpectedItemCount
    Number of rows exported to the CSV for this watchlist.

.PARAMETER WatchListFilePath
    Path to the exported CSV. Its size decides whether SentinelEnrichment splits the upload, and therefore
    whether verification is worth its paging cost. Omit to always verify.

.PARAMETER SplitThresholdBytes
    CSV size at or above which SentinelEnrichment splits the upload into multiple blocks. Default is 1 MB,
    matching the module's own behaviour ("CSV file size is X MB. Splitting into blocks of ~1 MB...").

.PARAMETER ApiVersion
    Microsoft.SecurityInsights API version. Defaults to the version used by SentinelEnrichment.

.OUTPUTS
    [int] Number of items counted in the watchlist, -1 when the count could not be determined, or -2 when
    verification was skipped because the watchlist was too small to be split.
#>

function Test-EntraOpsSentinelWatchlistDeployment {

    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
        ,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
        ,
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceName
        ,
        [Parameter(Mandatory = $true)]
        [string]$WatchListName
        ,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedItemCount
        ,
        [Parameter(Mandatory = $false)]
        [string]$WatchListFilePath
        ,
        [Parameter(Mandatory = $false)]
        [long]$SplitThresholdBytes = 1MB
        ,
        [Parameter(Mandatory = $false)]
        [string]$ApiVersion = "2025-06-01"
    )

    # A single-block upload gets one ARM deployment of its own and cannot hit the shared-name race, so it is
    # not worth paging the whole watchlist to verify it.
    if (-not [string]::IsNullOrEmpty($WatchListFilePath) -and (Test-Path -LiteralPath $WatchListFilePath)) {
        $CsvSize = (Get-Item -LiteralPath $WatchListFilePath).Length
        if ($CsvSize -lt $SplitThresholdBytes) {
            Write-Verbose "Skipping verification of $WatchListName - CSV is $([Math]::Round($CsvSize / 1MB, 2)) MB, below the $([Math]::Round($SplitThresholdBytes / 1MB, 2)) MB split threshold, so it deploys as a single block."
            return -2
        }
        Write-Verbose "Verifying $WatchListName - CSV is $([Math]::Round($CsvSize / 1MB, 2)) MB and will be split into multiple same-named ARM deployments."
    }

    $EncodedWatchListName = [System.Uri]::EscapeDataString($WatchListName)
    $BaseUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/watchlists/$EncodedWatchListName/watchlistItems?api-version=$ApiVersion"

    $ItemCount = 0
    $Uri = $BaseUri
    $PageCount = 0
    # Bound the paging loop: a watchlist that keeps returning nextLink must not hang the sync.
    $MaxPages = 500

    try {
        while ($null -ne $Uri -and $PageCount -lt $MaxPages) {
            $Response = Invoke-AzRestMethod -Method "GET" -Uri $Uri
            if ($Response.StatusCode -ne 200) {
                Write-Warning "  [!] Could not verify watchlist $WatchListName - item query returned HTTP $($Response.StatusCode)."
                return -1
            }
            $Payload = $Response.Content | ConvertFrom-Json -Depth 20
            $ItemCount += @($Payload.value).Count
            $Uri = $Payload.nextLink
            $PageCount++
        }
    } catch {
        Write-Warning "  [!] Could not verify watchlist $WatchListName - item query failed: $($_.Exception.Message)"
        return -1
    }

    if ($PageCount -ge $MaxPages -and $null -ne $Uri) {
        Write-Warning "  [!] Stopped counting items of watchlist $WatchListName after $MaxPages pages - verification incomplete."
        return -1
    }

    if ($ItemCount -eq $ExpectedItemCount) {
        Write-Verbose "Watchlist $WatchListName verified: $ItemCount item(s) match the exported row count."
    } else {
        Write-Warning "  [!] Watchlist $WatchListName contains $ItemCount item(s) but $ExpectedItemCount row(s) were exported. Large watchlists are deployed in blocks that share one ARM deployment name, so an earlier block may have been overwritten. Re-run the watchlist upload and verify in Sentinel."
    }

    return $ItemCount
}
