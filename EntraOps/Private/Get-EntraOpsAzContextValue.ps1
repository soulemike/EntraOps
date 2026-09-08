function Get-EntraOpsAzContextValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('TenantId', 'SubscriptionId')]
        [string]$Property
    )

    if ($Property -eq 'TenantId' -and -not [string]::IsNullOrWhiteSpace($Global:TenantIdContext)) {
        return $Global:TenantIdContext
    }

    if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
        return $null
    }

    $AzContext = Get-AzContext -ErrorAction SilentlyContinue
    if ($null -eq $AzContext) {
        return $null
    }

    if ($Property -eq 'SubscriptionId') {
        return $AzContext.Subscription.Id
    }

    return $AzContext.Tenant.Id
}