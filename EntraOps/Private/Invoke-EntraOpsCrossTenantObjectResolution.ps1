<#
.SYNOPSIS
    Resolves object details for principals that could not be found in the home tenant by switching
    context to the configured managing tenant.

.DESCRIPTION
    Phase 2 of the two-phase object resolution strategy. After home-tenant resolution
    (Invoke-EntraOpsParallelObjectResolution) completes, objects that returned 'unknown' type
    are assumed to reside in the managing tenant (Tenant Governance Relationsip).

    This function:
      - Skips immediately if no managing tenant is configured ($Global:ManagingTenantIdContext)
      - Skips immediately if all objects were resolved in Phase 1
      - Switches MgGraph context to the managing tenant using the appropriate strategy:
          Interactive auth (UserInteractive / DeviceAuthentication) → Connect-MgGraph with MSAL cache
            (Stage 1 group expansion primes the MSAL cache; if no cross-tenant groups exist,
             this is the first managing tenant connect and will prompt once)
          Automated auth (MSI / FederatedCredentials / AlreadyAuthenticated) → Get-AzAccessToken silently
      - Delegates the actual resolution to Invoke-EntraOpsParallelObjectResolution (reuse)
      - Merges resolved objects back into the shared ObjectDetailsCache hashtable
      - Always restores the home-tenant MgGraph context in a finally block:
          Interactive: Connect-MgGraph -TenantId (MSAL cache hit, preserves full scope set)
          Automated:   Connect-MgGraph -AccessToken (Az app token carries full application permissions)

.PARAMETER UniqueObjects
    Full array of unique objects from the EAM cmdlet (ObjectId, ObjectType).

.PARAMETER ObjectDetailsCache
    Hashtable from Phase 1 (ObjectId → resolved details). Updated in-place with managing-tenant results.

.PARAMETER EnableParallelProcessing
    Enable parallel processing for the managing-tenant resolution. Default is $true.

.PARAMETER ParallelThrottleLimit
    Maximum number of parallel threads. Default is 10.

.OUTPUTS
    The updated ObjectDetailsCache hashtable with managing-tenant objects merged in.
#>

function Invoke-EntraOpsCrossTenantObjectResolution {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Array]$UniqueObjects,

        [Parameter(Mandatory = $true)]
        [hashtable]$ObjectDetailsCache,

        [Parameter(Mandatory = $false)]
        [bool]$EnableParallelProcessing = $true,

        [Parameter(Mandatory = $false)]
        [int]$ParallelThrottleLimit = 10
    )

    # Guard: managing tenant must be configured
    if ([string]::IsNullOrEmpty($Global:ManagingTenantIdContext)) {
        Write-Verbose "No managing tenant configured — skipping cross-tenant object resolution."
        return $ObjectDetailsCache
    }

    # Identify objects that Phase 1 could not resolve in the home tenant
    $UnresolvedObjects = @($UniqueObjects | Where-Object {
        $Details = $ObjectDetailsCache[$_.ObjectId]
        $null -eq $Details -or $Details.ObjectType -eq 'unknown'
    })

    if ($UnresolvedObjects.Count -eq 0) {
        Write-Verbose "All objects resolved in home tenant — skipping cross-tenant resolution."
        return $ObjectDetailsCache
    }

    Write-Host "Cross-tenant resolution: $($UnresolvedObjects.Count) unresolved object(s) will be queried against managing tenant '$Global:ManagingTenantIdContext'..." -ForegroundColor Cyan

    $AuthType = $__EntraOpsSession.AuthenticationType
    $IsInteractiveAuth = $AuthType -in @('UserInteractive', 'DeviceAuthentication')

    # Managing tenant: always use Get-AzAccessToken regardless of auth type.
    # Connect-EntraOps already pre-authenticates to the managing tenant via Get-AzAccessToken for
    # ALL auth types (including UserInteractive). The Az session therefore has a cached managing
    # tenant token — Get-AzAccessToken here is silent, no browser/device prompt needed.
    # Home restore: auth-type-aware (see finally block).
    try {
        $ManagingToken = (Get-AzAccessToken -ResourceTypeName "MSGraph" -TenantId $Global:ManagingTenantIdContext -AsSecureString -ErrorAction Stop).Token
    } catch {
        Write-Warning "Could not acquire managing tenant token: $($_.Exception.Message). Cross-tenant resolution skipped."
        return $ObjectDetailsCache
    }

    # Home token needed only for non-interactive restore (Connect-MgGraph -AccessToken).
    # For interactive, home restore uses Connect-MgGraph -TenantId (MSAL cache, see finally).
    $HomeToken = $null
    if (-not $IsInteractiveAuth) {
        try {
            $HomeToken = (Get-AzAccessToken -ResourceTypeName "MSGraph" -TenantId $Global:TenantIdContext -AsSecureString -ErrorAction Stop).Token
        } catch {
            Write-Warning "Could not acquire home tenant token for context restore: $($_.Exception.Message). Cross-tenant resolution skipped."
            return $ObjectDetailsCache
        }
    }

    # Scopes for the interactive home-tenant restore via Connect-MgGraph -TenantId.
    # Must be a subset of what Connect-EntraOps requested so MSAL returns the cached
    # full-scope home tenant token without prompting.
    $HomeTenantScopes = @(
        "AdministrativeUnit.Read.All",
        "Application.Read.All",
        "CustomSecAttributeAssignment.Read.All",
        "Directory.Read.All",
        "Group.Read.All",
        "GroupMember.Read.All",
        "PrivilegedAccess.Read.AzureADGroup",
        "PrivilegedEligibilitySchedule.Read.AzureADGroup",
        "RoleManagement.Read.All",
        "User.Read.All"
    )

    try {
        #region Switch MgGraph context to managing tenant (silent — Az session token)
        Connect-MgGraph -AccessToken $ManagingToken -NoWelcome -ErrorAction Stop
        Write-Host "Connected to managing tenant '$Global:ManagingTenantIdContext'." -ForegroundColor Cyan
        #endregion

        #region Resolve unresolved objects in managing tenant context
        $ManagingTenantCache = Invoke-EntraOpsParallelObjectResolution `
            -UniqueObjects $UnresolvedObjects `
            -TenantId $Global:ManagingTenantIdContext `
            -EnableParallelProcessing $EnableParallelProcessing `
            -ParallelThrottleLimit $ParallelThrottleLimit
        #endregion

        #region Merge results back into shared cache
        $MergedCount = 0
        foreach ($ObjectId in $ManagingTenantCache.Keys) {
            if ($null -ne $ManagingTenantCache[$ObjectId]) {
                $ObjectDetailsCache[$ObjectId] = $ManagingTenantCache[$ObjectId]
                $MergedCount++
            }
        }
        Write-Host "Cross-tenant resolution complete: $MergedCount of $($UnresolvedObjects.Count) object(s) resolved in managing tenant." -ForegroundColor Cyan
        #endregion

    } catch {
        Write-Warning "Cross-tenant object resolution failed: $($_.Exception.Message)"
    } finally {
        # Always restore home-tenant MgGraph context regardless of success or failure.
        # Interactive: Connect-MgGraph -TenantId hits the MSAL cache (full-scope token from
        #              Connect-EntraOps) — no prompt, no scope loss.
        # Non-interactive: Connect-MgGraph -AccessToken uses the Az app token which carries
        #              full application permissions.
        try {
            if ($IsInteractiveAuth) {
                Connect-MgGraph -TenantId $Global:TenantIdContext -Scopes $HomeTenantScopes -NoWelcome -ErrorAction Stop
            } else {
                Connect-MgGraph -AccessToken $HomeToken -NoWelcome -ErrorAction Stop
            }
            Write-Verbose "Restored Microsoft Graph context to home tenant '$Global:TenantIdContext'."
        } catch {
            Write-Warning "Failed to restore home tenant Microsoft Graph context: $($_.Exception.Message)"
        }
    }

    return $ObjectDetailsCache
}
