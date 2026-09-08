function Select-EntraOpsUniqueGraphObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$ObjectDescription,

        [Parameter(Mandatory = $false)]
        [switch]$AllowNotFound
    )

    $Objects = @($InputObject | Where-Object { $null -ne $_ })
    if ($Objects.Count -gt 1) {
        throw "Multiple objects matched $ObjectDescription. Use a unique name before continuing."
    }
    if ($Objects.Count -eq 0) {
        if ($AllowNotFound) { return $null }
        throw "No object matched $ObjectDescription."
    }

    return $Objects[0]
}