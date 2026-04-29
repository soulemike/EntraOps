#!/usr/bin/env pwsh
# Test ServiceEM with Specific Owner and Members

$ErrorActionPreference = "Stop"

$TenantId = 'd2280e3f-26e4-4d90-b991-8933a2aac6c7'
$ClientId = '48280ee2-5903-4005-8781-91b81c004526'
$CertPath = '/workspace/Tests/ServiceEM/TestCertificates/EntraOpsTest.pfx'
$CertPassword = 'TestCert123!'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ServiceEM Test with Specific Owner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load certificate and connect
Write-Host "Loading certificate..." -ForegroundColor Yellow
$SecurePassword = ConvertTo-SecureString $CertPassword -AsPlainText -Force
$Certificate = Get-PfxCertificate -FilePath $CertPath -Password $SecurePassword
Write-Host "✓ Certificate loaded: $($Certificate.Thumbprint)" -ForegroundColor Green

Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Certificate $Certificate -NoWelcome
$context = Get-MgContext
Write-Host "✓ Connected successfully!" -ForegroundColor Green
Write-Host "  AuthType: $($context.AuthType)" -ForegroundColor Gray

# Import EntraOps
Write-Host ""
Write-Host "Importing EntraOps module..." -ForegroundColor Yellow
Import-Module /workspace/EntraOps/EntraOps.psd1 -Force
Write-Host "✓ Module imported" -ForegroundColor Green

# Get existing users from the tenant
Write-Host ""
Write-Host "Finding test users in tenant..." -ForegroundColor Yellow
$users = Get-MgUser -Top 5 -Property "id,userPrincipalName,displayName" | Select-Object -First 3

if ($users.Count -lt 2) {
    Write-Host "❌ Not enough users found in tenant. Need at least 2 users." -ForegroundColor Red
    exit 1
}

$TestOwner = $users[0].UserPrincipalName
$TestMembers = @($users[1].UserPrincipalName)
if ($users.Count -gt 2) {
    $TestMembers += $users[2].UserPrincipalName
}

Write-Host "✓ Selected users:" -ForegroundColor Green
Write-Host "  Owner: $TestOwner" -ForegroundColor Gray
Write-Host "  Members: $($TestMembers -join ', ')" -ForegroundColor Gray

# Test 1: Service Bootstrap with specific owner and members
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST 1: Service Bootstrap with Owner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$TestId = "Svc$(Get-Random -Minimum 1000 -Maximum 9999)"
$testStart = Get-Date

try {
    Write-Host "Creating service: $TestId" -ForegroundColor Yellow
    Write-Host "  Owner: $TestOwner" -ForegroundColor Gray
    Write-Host "  Members: $($TestMembers -join ', ')" -ForegroundColor Gray
    
    $ServiceRoles = @(
        [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
        [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""}
        [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Admins"; groupType = ""}
    )
    
    $result = New-EntraOpsServiceBootstrap `
        -ServiceName $TestId `
        -ServiceOwner $TestOwner `
        -ServiceMembers $TestMembers `
        -ServiceRoles $ServiceRoles `
        -SkipAzureResourceGroup `
        -Verbose

    $duration = (Get-Date) - $testStart
    Write-Host ""
    Write-Host "✅ Service Bootstrap completed successfully! ($($duration.TotalSeconds.ToString('F2'))s)" -ForegroundColor Green
    
    if ($result.CatalogId) {
        Write-Host "  Catalog ID: $($result.CatalogId)" -ForegroundColor Gray
    }
    if ($result.AccessPackageIds) {
        Write-Host "  Access Packages: $($result.AccessPackageIds.Count) created" -ForegroundColor Gray
    }
    if ($result.Groups) {
        Write-Host "  Groups: $($result.Groups.Count) created" -ForegroundColor Gray
    }
    
} catch {
    $duration = (Get-Date) - $testStart
    Write-Host ""
    Write-Host "❌ Service Bootstrap failed after $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
}

# Test 2: Landing Zone with specific owner and members
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST 2: Landing Zone with Owner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$LZTestId = "LZ$(Get-Random -Minimum 1000 -Maximum 9999)"
$lzStart = Get-Date

try {
    Write-Host "Creating landing zone: $LZTestId" -ForegroundColor Yellow
    Write-Host "  Owner: $TestOwner" -ForegroundColor Gray
    Write-Host "  Members: $($TestMembers -join ', ')" -ForegroundColor Gray
    
    $lzResult = New-EntraOpsSubscriptionLandingZone `
        -DeploymentPrefix $LZTestId `
        -AzureRegion "westus2" `
        -ServiceOwner $TestOwner `
        -ServiceMembers $TestMembers `
        -SkipAzureResourceGroup `
        -GovernanceModel "PerService" `
        -Verbose

    $lzDuration = (Get-Date) - $lzStart
    Write-Host ""
    Write-Host "✅ Landing Zone created successfully! ($($lzDuration.TotalSeconds.ToString('F2'))s)" -ForegroundColor Green
    
} catch {
    $lzDuration = (Get-Date) - $lzStart
    Write-Host ""
    Write-Host "❌ Landing Zone failed after $($lzDuration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
}

# Cleanup
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Remove groups
$groupsToRemove = Get-MgGroup -Filter "startswith(displayName,'$TestId') or startswith(displayName,'$LZTestId') or startswith(displayName,'Sub-$LZTestId') or startswith(displayName,'Rg-$LZTestId') or startswith(displayName,'SG-$TestId') or startswith(displayName,'SG-$LZTestId')" -ErrorAction SilentlyContinue

foreach ($group in $groupsToRemove) {
    try {
        Write-Host "Removing group: $($group.DisplayName)..." -ForegroundColor Gray
        Remove-MgGroup -GroupId $group.Id -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed" -ForegroundColor Gray
    } catch {
        Write-Host "  ⚠️ Error: $_" -ForegroundColor Yellow
    }
}

# Remove catalogs
$catalogsToRemove = Get-MgEntitlementManagementCatalog -Filter "startswith(displayName,'Catalog-$TestId') or startswith(displayName,'Catalog-Sub-$LZTestId') or startswith(displayName,'Catalog-Rg-$LZTestId')" -ErrorAction SilentlyContinue
foreach ($catalog in $catalogsToRemove) {
    try {
        Write-Host "Removing catalog: $($catalog.DisplayName)..." -ForegroundColor Gray
        Remove-MgEntitlementManagementCatalog -AccessPackageCatalogId $catalog.Id -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed" -ForegroundColor Gray
    } catch {
        Write-Host "  ⚠️ Error: $_" -ForegroundColor Yellow
    }
}

Disconnect-MgGraph
Write-Host ""
Write-Host "✅ Test complete!" -ForegroundColor Green
