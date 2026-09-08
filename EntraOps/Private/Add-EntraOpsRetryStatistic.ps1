function Add-EntraOpsRetryStatistic {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('TotalRetries', 'ThrottledRequests', 'FailedRequests', 'NonRetryableRequests')]
        [string]$Name
    )

    $Statistics = $__EntraOpsSession.RetryStatistics
    [System.Threading.Monitor]::Enter($Statistics.SyncRoot)
    try {
        $Statistics[$Name] = [int]$Statistics[$Name] + 1
    } finally {
        [System.Threading.Monitor]::Exit($Statistics.SyncRoot)
    }
}