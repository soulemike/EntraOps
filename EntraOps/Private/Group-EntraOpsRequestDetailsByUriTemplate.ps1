function Group-EntraOpsRequestDetailsByUriTemplate {
    <#
    .SYNOPSIS
        Collapses a list of failed/non-retryable request details into one summary entry per
        GUID-normalized URI template, instead of one line per individual request.
    .DESCRIPTION
        Many recurring failures (e.g. deleted Access Package Catalogs, orphaned directory objects)
        only differ by the GUID embedded in the request URI - the endpoint/query shape and the
        resulting error are otherwise identical. Printing one line per request in these cases makes
        the API Throttling Summary unreadable when dozens of distinct catalogs/objects are affected.
        This groups by (StatusCode, GUID-normalized Uri) and returns one summary object per group,
        with the distinct IDs and total request count so the caller can render a single line like:
        "[404] .../accessPackageCatalogs/{id} [27 distinct resource(s), 84 request(s)] e.g. id1, id2, id3 (+24 more)"
    .PARAMETER RequestDetails
        Objects with Uri, StatusCode and ErrorMessage properties (as recorded in
        $__EntraOpsSession.RetryStatistics.NonRetryableRequestDetails / FailedRequestDetails).
    .OUTPUTS
        PSCustomObject per distinct (StatusCode, NormalizedUri) group with:
        StatusCode, NormalizedUri, Count, DistinctIds (List[string], first-seen order), ErrorMessage
        (from the first request in the group).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$RequestDetails
    )

    $GuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $Groups = [ordered]@{}

    foreach ($Detail in $RequestDetails) {
        $NormalizedUri = [regex]::Replace($Detail.Uri, $GuidPattern, '{id}')
        $GroupKey = "$($Detail.StatusCode)|$NormalizedUri"

        if (-not $Groups.Contains($GroupKey)) {
            $Groups[$GroupKey] = [PSCustomObject]@{
                StatusCode    = $Detail.StatusCode
                NormalizedUri = $NormalizedUri
                Count         = 0
                DistinctIds   = [System.Collections.Generic.List[string]]::new()
                ErrorMessage  = $Detail.ErrorMessage
            }
        }

        $Group = $Groups[$GroupKey]
        $Group.Count++
        foreach ($Id in ([regex]::Matches($Detail.Uri, $GuidPattern) | ForEach-Object { $_.Value } | Select-Object -Unique)) {
            if (-not $Group.DistinctIds.Contains($Id)) {
                $Group.DistinctIds.Add($Id)
            }
        }
    }

    return $Groups.Values
}
