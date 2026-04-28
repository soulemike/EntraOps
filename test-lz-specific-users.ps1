#!/usr/bin/env pwsh
# Test Landing Zone with Specific Users

$ErrorActionPreference = "Stop"

$TenantId = 'd2280e3f-26e4-4d90-b991-8933a2aac6c7'
$ClientId = '48280ee2-5903-4005-8781-91b81c004526'
$CertPath = '/workspace/Tests/ServiceEM/TestCertificates/EntraOpsTest.pfx'
$CertPassword = 'TestCert123!'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Landing Zone Test with Specific Users" -ForegroundColor Cyan
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

# Import EntraOps
Write-Host ""
Write-Host "Importing EntraOps module..." -ForegroundColor Yellow
Import-Module /workspace/EntraOps/EntraOps.psd1 -Force
Write-Host "✓ Module imported" -ForegroundColor Green

# Get existing users from the tenant to use as test users
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

# Create config file with specific users
$TestId = "LZTest$(Get-Random -Minimum 1000 -Maximum 9999)"
$ConfigPath = "/workspace/test-config-$TestId.json"

$Config = @{
    TenantId = $TenantId
    TenantName = "M365x60294116.onmicrosoft.com"
    ServiceEM = @{
        GovernanceModel = "PerService"
        DefaultServiceOwner = $TestOwner
        DefaultServiceMembers = $TestMembers
    }
}

$Config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath
Write-Host ""
Write-Host "Created config: $ConfigPath" -ForegroundColor Gray

# Set the global config
$Global:EntraOpsConfig = $Config

# Run Landing Zone test
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Creating Landing Zone: $TestId" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$testStart = Get-Date
try {
    $result = New-EntraOpsSubscriptionLandingZone `
        -DeploymentPrefix $TestId `
        -AzureRegion "westus2" `
        -ServiceOwner $TestOwner `
        -ServiceMembers $TestMembers `
        -SkipAzureResourceGroup `
        -GovernanceModel "PerService" `
        -Verbose

    $duration = (Get-Date) - $testStart
    Write-Host ""
    Write-Host "✅ Landing Zone created successfully! ($($duration.TotalSeconds.ToString('F2'))s)" -ForegroundColor Green
    
    # Display results
    Write-Host ""
    Write-Host "Created Resources:" -ForegroundColor Cyan
    $result | Format-List
    
} catch {
    $duration = (Get-Date) - $testStart
    Write-Host ""
    Write-Host "❌ Landing Zone failed after $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor DarkGray
    $_.ScriptStackTrace -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

# Cleanup
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Remove groups created by the test
$groupFilter = "$TestId"
Write-Host "Looking for groups to clean up..." -ForegroundColor Yellow
$groupsToRemove = Get-MgGroup -Filter "startswith(displayName,'$TestId') or startswith(displayName,'Sub-$TestId') or startswith(displayName,'Rg-$TestId') or startswith(displayName,'SG-$TestId')" -ErrorAction SilentlyContinue

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
$catalogsToRemove = Get-MgEntitlementManagementCatalog -Filter "startswith(displayName,'Catalog-$TestId') or startswith(displayName,'Catalog-Sub-$TestId') or startswith(displayName,'Catalog-Rg-$TestId')" -ErrorAction SilentlyContinue
foreach ($catalog in $catalogsToRemove) {
    try {
        Write-Host "Removing catalog: $($catalog.DisplayName)..." -ForegroundColor Gray
        Remove-MgEntitlementManagementCatalog -AccessPackageCatalogId $catalog.Id -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed" -ForegroundColor Gray
    } catch {
        Write-Host "  ⚠️ Error: $_" -ForegroundColor Yellow
    }
}

# Remove config file
Remove-Item $ConfigPath -ErrorAction SilentlyContinue

Disconnect-MgGraph
Write-Host ""
Write-Host "✅ Test complete!" -ForegroundColor Green
