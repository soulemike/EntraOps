function Get-EntraOpsReportingTenantName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $tenantName = Get-Variable -Name TenantNameContext -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($tenantName)) {
        return $tenantName
    }

    $configPath = Join-Path $RepoRoot 'EntraOpsConfig.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return ''
    }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if ($config.PSObject.Properties.Name -contains 'TenantName' -and -not [string]::IsNullOrWhiteSpace($config.TenantName)) {
            return $config.TenantName
        }
    } catch {
        Write-Verbose ('Could not read tenant name from {0}: {1}' -f $configPath, $_.Exception.Message)
    }

    return ''
}
