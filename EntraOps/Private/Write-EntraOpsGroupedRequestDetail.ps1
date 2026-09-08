function Write-EntraOpsGroupedRequestDetail {
    <#
    .SYNOPSIS
        Renders one summarized console line (+ error message line) for a request-detail group
        produced by Group-EntraOpsRequestDetailsByUriTemplate.
    .DESCRIPTION
        A group with a single distinct ID (or none at all, e.g. no GUID in the Uri) and a single
        request is printed as "[StatusCode] Uri" using the GUID-normalized URI by default. A group
        covering multiple requests and/or distinct GUIDs is collapsed into one line showing the
        URI template and distinct-resource/request counts. Object IDs are always shown; detailed
        error text is included only when IncludeObjectDetails is enabled.
    .PARAMETER Group
        A single group object as returned by Group-EntraOpsRequestDetailsByUriTemplate.
    .PARAMETER Color
        Console color for the main "[StatusCode] Uri [...]" line.
    .PARAMETER DetailColor
        Console color for the secondary error-message line.
    .PARAMETER IncludeObjectDetails
        Include detailed object-specific error text. Defaults to ConsoleOutput.IncludeObjectDetails from
        EntraOpsConfig.json. Object IDs are always included.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Group,
        [Parameter(Mandatory = $false)]
        [string]$Color = "Yellow",
        [Parameter(Mandatory = $false)]
        [string]$DetailColor = "DarkYellow",
        [Parameter(Mandatory = $false)]
        [Alias('IncludeIdentifiers')]
        [boolean]$IncludeObjectDetails = [bool]$Global:EntraOpsIncludeObjectDetails
    )

    $DistinctIdCount = $Group.DistinctIds.Count
    $DisplayErrorMessage = if ($IncludeObjectDetails) {
        $Group.ErrorMessage
    } else {
        'Object-specific error details omitted. Set ConsoleOutput.IncludeObjectDetails to true to include them.'
    }

    if ($DistinctIdCount -le 1 -and $Group.Count -le 1) {
        $DisplayUri = if ($DistinctIdCount -eq 1) { $Group.NormalizedUri.Replace('{id}', $Group.DistinctIds[0]) } else { $Group.NormalizedUri }
        Write-Host "    - [$($Group.StatusCode)] $DisplayUri" -ForegroundColor $Color
        Write-Host "      $DisplayErrorMessage" -ForegroundColor $DetailColor
        return
    }

    $SampleSuffix = ""
    $SampleIds = $Group.DistinctIds | Select-Object -First 3
    if ($SampleIds.Count -gt 0) {
        $SampleText = $SampleIds -join ", "
        if ($DistinctIdCount -gt $SampleIds.Count) {
            $SampleText += " (+$($DistinctIdCount - $SampleIds.Count) more)"
        }
        $SampleSuffix = " e.g. $SampleText"
    }

    $CountLabel = if ($DistinctIdCount -gt 1) { "$DistinctIdCount distinct resource(s), $($Group.Count) request(s)" } else { "$($Group.Count) request(s)" }
    Write-Host "    - [$($Group.StatusCode)] $($Group.NormalizedUri) [$CountLabel]$SampleSuffix" -ForegroundColor $Color
    Write-Host "      $DisplayErrorMessage" -ForegroundColor $DetailColor
}
