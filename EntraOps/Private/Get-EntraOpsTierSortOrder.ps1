function Get-EntraOpsTierSortOrder {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [object]$TierValue
    )

    $NumericTier = 0
    if ([int]::TryParse("$TierValue", [ref]$NumericTier)) {
        return $NumericTier
    }

    return [int]::MaxValue
}