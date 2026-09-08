function Assert-EntraOpsConditionalAccessGroupSyncSucceeded {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$SyncSummary
    )

    $FailureCount = ($SyncSummary | Measure-Object -Property Failed -Sum).Sum
    if ($null -eq $FailureCount) { $FailureCount = 0 }
    $AbortedGroups = @($SyncSummary | Where-Object { $_.Status -eq 'ABORTED' })

    if ($FailureCount -eq 0 -and $AbortedGroups.Count -eq 0) { return }

    $FailureReasons = [System.Collections.Generic.List[string]]::new()
    if ($FailureCount -gt 0) {
        $FailureReasons.Add("$FailureCount membership operation(s) failed") | Out-Null
    }
    if ($AbortedGroups.Count -gt 0) {
        $FailureReasons.Add("$($AbortedGroups.Count) group synchronization(s) aborted by the removal safety threshold") | Out-Null
    }

    throw "Conditional Access group sync did not complete: $($FailureReasons -join '; '). Review the warning summary above."
}