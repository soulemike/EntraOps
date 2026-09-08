<#
.SYNOPSIS
    Pre-warms the Microsoft Graph token for REST-only parallel processing.

.DESCRIPTION
    In REST-only mode (Connect-EntraOps -UseInvokeRestMethodOnly) no Graph SDK context exists, so
    parallel runspaces cannot authenticate through Connect-MgGraph's process-wide context. They
    instead reuse the shared session's MsGraphTokenCache (synchronized hashtable, shared by
    reference into each runspace's module scope). This helper makes sure that cache holds a token
    valid for at least 10 more minutes BEFORE a parallel block starts, so runspaces never need to
    call Get-AzAccessToken themselves (Az context import inside fresh runspaces is not guaranteed).

    Tenant-aware: honors CurrentGraphTenantId (set by cross-tenant code paths) exactly like
    Invoke-EntraOpsMsGraphQuery's own token acquisition, warming the same cache key that the
    runspaces will read.

.OUTPUTS
    $true when a valid token is cached and parallel REST-only processing is safe, otherwise $false.
#>

function Initialize-EntraOpsRestOnlyParallelToken {
    [CmdletBinding()]
    param ()

    $Now = [DateTime]::UtcNow
    $TargetTenantId = $__EntraOpsSession['CurrentGraphTenantId']
    $TokenKey = if ([string]::IsNullOrEmpty($TargetTenantId)) { 'default' } else { $TargetTenantId }

    if ($TokenKey -eq 'default') {
        # A token explicitly provided to Connect-EntraOps -MsGraphAccessToken takes precedence in
        # Invoke-EntraOpsMsGraphQuery's REST path - if it is still valid long enough, we are ready.
        $Provided = $__EntraOpsSession.MsGraphTokenCache['provided']
        if ($null -ne $Provided -and $Provided.Expiry -gt $Now.AddMinutes(10)) {
            return $true
        }
    }

    $Cached = $__EntraOpsSession.MsGraphTokenCache[$TokenKey]
    if ($null -ne $Cached -and $Cached.Expiry -gt $Now.AddMinutes(10)) {
        return $true
    }

    try {
        # Same acquisition/cache shape as Invoke-EntraOpsMsGraphQuery's Get-EntraOpsMsGraphAccessToken
        $TokenParams = @{ ResourceTypeName = 'MSGraph'; AsSecureString = $true; ErrorAction = 'Stop' }
        if ($TokenKey -ne 'default') { $TokenParams.TenantId = $TargetTenantId }
        $TokenResponse = Get-AzAccessToken @TokenParams
        $PlainToken = $TokenResponse.Token | ConvertFrom-SecureString -AsPlainText
        $Expiry = if ($TokenResponse.ExpiresOn) { $TokenResponse.ExpiresOn.UtcDateTime } else { $Now.AddMinutes(30) }
        $__EntraOpsSession.MsGraphTokenCache[$TokenKey] = @{ Token = $PlainToken; Expiry = $Expiry }
        return $true
    } catch {
        Write-Verbose "Unable to pre-warm Microsoft Graph token for REST-only parallel processing: $($_.Exception.Message)"
        return $false
    }
}
