<#
.SYNOPSIS
    Sync privilege level of Entitlement Management catalogs based on EntraOps classification: Catalogs with Control Plane scope will be protected as "privileged" catalog, catalogs without privileged scope will be reverted to "standard".

.DESCRIPTION
    Identifies Entitlement Management (Access Package) catalogs which have been classified as Control Plane scope in EntraOps
    (RBAC system "IdentityGovernance") and syncs their privilege level (Preview) by using Microsoft Graph API:

    - Catalog with Control Plane scope and privilege level "standard"      -> updated to "privileged" (PROTECT)
    - Catalog with Control Plane scope and privilege level "privileged"    -> no change (KEEP)
    - Catalog without Control Plane scope and privilege level "privileged" -> reverted to "standard" (REVERT)
    - Catalog without Control Plane scope and privilege level "standard"   -> no change (ignored)

    Privileged catalogs apply stricter controls:
    - Applications must have directory role management permissions to write to a privileged catalog.
    - Only Global Administrators, or Privileged Role Administrators who also have the Identity Governance Administrator role,
      can perform create, update, or delete actions.
    - No new auto-assignment policies can be created for privileged catalogs.

    CAUTION: This cmdlet requires the elevated Microsoft Graph permission "EntitlementManagement.ReadWrite.All" and should be
    used with caution. The permission is only assigned by New-EntraOpsWorkloadIdentity when the EntraOpsConfig.json setting
    AutomatedElmCatalogProtection.ApplyPrivilegedElmCatalogProtection is enabled. Reference for required permissions:
    https://learn.microsoft.com/en-us/graph/api/entitlementmanagement-update?view=graph-rest-beta

    CAUTION: EntraOps cannot distinguish whether a catalog has been set to "privileged" by EntraOps or manually by an administrator.
    Catalogs without Control Plane scope in EntraOps will be reverted to "standard", even if they have been protected manually.

    NOTE: Updating the privilege level protects the catalog from delegated modification, but the existing role assignments
    on the catalog will still be classified as Control Plane by EntraOps and should be reviewed and removed as soon as possible.

.PARAMETER ApplyToAccessTierLevel
    Array of Access Tier Levels which will be protected as privileged catalog. Default is ControlPlane.

.PARAMETER RemovalSafetyThreshold
    Fraction of currently privileged catalogs that may be reverted in a single run before catalog reverts abort. Default is 0.5 (50%).

.PARAMETER ForceRemovalBeyondSafetyThreshold
    Apply a reviewed catalog-revert plan even when it exceeds RemovalSafetyThreshold.

.EXAMPLE
    Sync privilege level of all Entitlement Management catalogs based on Control Plane scope classification
    Update-EntraOpsPrivilegedUnprotectedElmCatalog
#>

function Update-EntraOpsPrivilegedUnprotectedElmCatalog {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $False)]
        [ValidateSet("ControlPlane", "ManagementPlane")]
        [Array]$ApplyToAccessTierLevel = ("ControlPlane")
        ,
        # Maximum fraction of privileged catalogs reversible per synchronization.
        [Parameter(Mandatory = $False)]
        [ValidateRange(0, 1)]
        [double]$RemovalSafetyThreshold = 0.5
        ,
        # Permits catalog reverts that exceed RemovalSafetyThreshold.
        [Parameter(Mandatory = $False)]
        [switch]$ForceRemovalBeyondSafetyThreshold
        ,
        [Parameter(Mandatory = $False)]
        [boolean]$ApplyPrivilegedElmCatalogProtection = $false
    )

    Write-Warning "This cmdlet updates the privilege level of Entitlement Management catalogs and requires the elevated Microsoft Graph permission 'EntitlementManagement.ReadWrite.All'. Use with caution."

    # Get all privileged EAM objects from IdentityGovernance
    $PrivilegedEamFilePath = "$DefaultFolderClassifiedEam/IdentityGovernance/IdentityGovernance.json"
    if (-not (Test-Path -Path $PrivilegedEamFilePath)) {
        Write-Error "No classified EAM data found at $PrivilegedEamFilePath. Run Save-EntraOpsPrivilegedEAMJson for IdentityGovernance first."
        return
    }
    $PrivilegedEamObjects = Get-Content -Path $PrivilegedEamFilePath | ConvertFrom-Json

    # Identify unique catalogs with role assignments classified at the selected tier levels (desired privileged catalogs)
    $DesiredPrivilegedCatalogIds = [System.Collections.Generic.List[string]]::new()
    foreach ($PrivilegedEamObject in $PrivilegedEamObjects) {
        foreach ($RoleAssignment in @($PrivilegedEamObject.RoleAssignments)) {
            if ("$($RoleAssignment.RoleAssignmentScopeId)" -notlike "/AccessPackageCatalog/*") { continue }
            $TierLevelMatch = @($RoleAssignment.Classification | Where-Object { $_.AdminTierLevelName -in $ApplyToAccessTierLevel })
            if ($TierLevelMatch.Count -eq 0) { continue }
            $CatalogId = "$($RoleAssignment.RoleAssignmentScopeId)".Replace("/AccessPackageCatalog/", "")
            if (-not $DesiredPrivilegedCatalogIds.Contains($CatalogId)) { $DesiredPrivilegedCatalogIds.Add($CatalogId) }
        }
    }

    # Get all Entitlement Management catalogs with their current privilege level
    try {
        $AllCatalogs = Invoke-EntraOpsMsGraphQuery -Method "GET" -Uri "/beta/identityGovernance/catalogs?`$select=id,displayName,privilegeLevel" -OutputType PSObject -DisableCache
    } catch {
        Write-Error "Could not get Entitlement Management catalogs: $_"
        return
    }

    $CurrentPrivilegedCatalogs = @($AllCatalogs | Where-Object { $_.privilegeLevel -eq "privileged" })

    # Evaluate catalog reverts before applying catalog protection updates.
    $PlannedReverts = @($CurrentPrivilegedCatalogs | Where-Object { -not $DesiredPrivilegedCatalogIds.Contains("$($_.id)") })
    $RevertSafetyCheck = Test-EntraOpsRemovalSafetyThreshold -CurrentCount $CurrentPrivilegedCatalogs.Count -RemovalCount $PlannedReverts.Count -RemovalSafetyThreshold $RemovalSafetyThreshold
    $SkipReverts = $false
    if ($RevertSafetyCheck.Exceeds -and -not $ForceRemovalBeyondSafetyThreshold) {
        $SkipReverts = $true
        Write-Warning "[ABORT] $($PlannedReverts.Count) catalog revert(s) exceed the $($RevertSafetyCheck.ThresholdPercent)% safety threshold ($($RevertSafetyCheck.RemovalThreshold) of $($CurrentPrivilegedCatalogs.Count) currently privileged). This may indicate an upstream data issue. Reverts are skipped (protect operations still apply) - review the summary, then re-run with -ForceRemovalBeyondSafetyThreshold to apply."
    } elseif ($RevertSafetyCheck.Exceeds) {
        Write-Warning "[FORCED] Applying $($PlannedReverts.Count) catalog revert(s) despite exceeding the $($RevertSafetyCheck.ThresholdPercent)% safety threshold - requested via -ForceRemovalBeyondSafetyThreshold."
    }

    # Summary tracking
    $SyncSummary = [System.Collections.Generic.List[psobject]]::new()
    $WarningMessages = New-Object -TypeName "System.Collections.Generic.List[psobject]"
    $TotalProtected = 0
    $TotalReverted = 0
    $TotalKept = 0
    $TotalFailed = 0
    $TotalAborted = 0
    if ($SkipReverts) {
        $WarningMessages.Add([PSCustomObject]@{ Type = "SafetyAbort"; Message = "$($PlannedReverts.Count) catalog revert(s) exceed the $($RevertSafetyCheck.ThresholdPercent)% removal safety threshold - reverts skipped (re-run with -ForceRemovalBeyondSafetyThreshold to apply)" })
    }

    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " EntraOps - Privileged ELM Catalog Sync" -ForegroundColor Cyan
    Write-Host " Access Tiers : $($ApplyToAccessTierLevel -join ', ')" -ForegroundColor Cyan
    Write-Host " Catalogs     : $(@($AllCatalogs).Count) total | $($DesiredPrivilegedCatalogIds.Count) with privileged scope | $($CurrentPrivilegedCatalogs.Count) currently privileged" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($Catalog in $AllCatalogs) {

        $IsDesiredPrivileged = $DesiredPrivilegedCatalogIds.Contains("$($Catalog.id)")
        $IsCurrentlyPrivileged = $Catalog.privilegeLevel -eq "privileged"

        # Case 1: Catalog with privileged scope is already protected - no change
        if ($IsDesiredPrivileged -and $IsCurrentlyPrivileged) {
            Write-Host "  [~] KEEP    $($Catalog.displayName) - already privileged" -ForegroundColor DarkGreen
            $SyncSummary.Add([PSCustomObject]@{ Catalog = $Catalog.displayName; Before = "privileged"; After = "privileged"; Action = "Keep"; Status = "OK" })
            $TotalKept++
            continue
        }

        # Case 2: Catalog with privileged scope is not protected yet - update to privileged
        if ($IsDesiredPrivileged -and -not $IsCurrentlyPrivileged) {
            try {
                $Body = @{ privilegeLevel = "privileged" } | ConvertTo-Json
                Invoke-EntraOpsMsGraphQuery -Method "PATCH" -Uri "/beta/identityGovernance/entitlementManagement/catalogs/$($Catalog.id)" -Body $Body -OutputType PSObject -ThrowOnFailure | Out-Null
                Write-Host "  [+] PROTECT $($Catalog.displayName) - privilege level: $($Catalog.privilegeLevel) -> privileged" -ForegroundColor Green
                Write-Warning "  Role assignments to catalog '$($Catalog.displayName)' will still be classified as Control Plane by EntraOps and should be removed as soon as possible."
                $SyncSummary.Add([PSCustomObject]@{ Catalog = $Catalog.displayName; Before = $Catalog.privilegeLevel; After = "privileged"; Action = "Protect"; Status = "OK" })
                $TotalProtected++
            } catch {
                Write-Warning "  [!] FAIL PROTECT $($Catalog.displayName) ($($Catalog.id)): $_"
                $WarningMessages.Add([PSCustomObject]@{ Type = "ApiError"; Message = "FAIL PROTECT catalog $($Catalog.displayName) ($($Catalog.id)): $_" })
                $SyncSummary.Add([PSCustomObject]@{ Catalog = $Catalog.displayName; Before = $Catalog.privilegeLevel; After = $Catalog.privilegeLevel; Action = "Protect"; Status = "FAILED" })
                $TotalFailed++
            }
            continue
        }

        # Case 3: Catalog without privileged scope is still protected - revert to standard
        if (-not $IsDesiredPrivileged -and $IsCurrentlyPrivileged) {
            if ($SkipReverts) {
                Write-Host "  [!] ABORT   $($Catalog.displayName) - revert skipped by removal safety threshold" -ForegroundColor Yellow
                $SyncSummary.Add([PSCustomObject]@{ Catalog = $Catalog.displayName; Before = "privileged"; After = "privileged"; Action = "Revert"; Status = "ABORTED" })
                $TotalAborted++
                continue
            }
            try {
                $Body = @{ privilegeLevel = "standard" } | ConvertTo-Json
                Invoke-EntraOpsMsGraphQuery -Method "PATCH" -Uri "/beta/identityGovernance/entitlementManagement/catalogs/$($Catalog.id)" -Body $Body -OutputType PSObject -ThrowOnFailure | Out-Null
                Write-Host "  [-] REVERT  $($Catalog.displayName) - no longer in scope of $($ApplyToAccessTierLevel -join ', ') - privilege level: privileged -> standard" -ForegroundColor Yellow
                $SyncSummary.Add([PSCustomObject]@{ Catalog = $Catalog.displayName; Before = "privileged"; After = "standard"; Action = "Revert"; Status = "OK" })
                $TotalReverted++
            } catch {
                Write-Warning "  [!] FAIL REVERT $($Catalog.displayName) ($($Catalog.id)): $_"
                $WarningMessages.Add([PSCustomObject]@{ Type = "ApiError"; Message = "FAIL REVERT catalog $($Catalog.displayName) ($($Catalog.id)): $_" })
                $SyncSummary.Add([PSCustomObject]@{ Catalog = $Catalog.displayName; Before = "privileged"; After = "privileged"; Action = "Revert"; Status = "FAILED" })
                $TotalFailed++
            }
            continue
        }

        # Case 4: Catalog without privileged scope and standard privilege level - nothing to do (not shown in summary)
    }

    # Warn about catalogs with privileged scope that could not be found in the tenant (e.g., deleted catalogs)
    foreach ($DesiredCatalogId in $DesiredPrivilegedCatalogIds) {
        if ("$DesiredCatalogId" -notin @($AllCatalogs.id)) {
            Write-Warning "  [!] Catalog $DesiredCatalogId with privileged scope not found in tenant (likely deleted)."
            $WarningMessages.Add([PSCustomObject]@{ Type = "CatalogNotFound"; Message = "Catalog $DesiredCatalogId with privileged scope not found in tenant (likely deleted)." })
            $SyncSummary.Add([PSCustomObject]@{ Catalog = $DesiredCatalogId; Before = "N/A"; After = "N/A"; Action = "Protect"; Status = "NOT FOUND" })
        }
    }

    # Final summary
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " Privileged ELM Catalog Sync Complete" -ForegroundColor Cyan
    Write-Host " Protected: $TotalProtected | Reverted: $TotalReverted | Kept: $TotalKept | Failed: $TotalFailed" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Show-EntraOpsWarningSummary -WarningMessages $WarningMessages
    if ($SyncSummary.Count -gt 0) {
        $SyncSummary | Format-Table -AutoSize -Property Catalog, Before, After, Action, Status
    } else {
        Write-Host "  No catalog changes required - all catalogs are already in sync." -ForegroundColor Gray
    }

    if ($TotalFailed -gt 0 -or $TotalAborted -gt 0) {
        $Reasons = [System.Collections.Generic.List[string]]::new()
        if ($TotalFailed -gt 0) { $Reasons.Add("$TotalFailed privilege level operation(s) failed") | Out-Null }
        if ($TotalAborted -gt 0) { $Reasons.Add("$TotalAborted catalog revert(s) aborted by the removal safety threshold") | Out-Null }
        throw "Entitlement Management catalog sync did not complete: $($Reasons -join '; '). Review the warning summary above."
    }
}
