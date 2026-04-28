#!/usr/bin/env pwsh
# Full ServiceEM Test with Service Principal

$ErrorActionPreference = "Stop"

$TenantId = 'd2280e3f-26e4-4d90-b991-8933a2aac6c7'
$ClientId = '48280ee2-5903-4005-8781-91b81c004526'
$CertPath = '/workspace/Tests/ServiceEM/TestCertificates/EntraOpsTest.pfx'
$CertPassword = 'TestCert123!'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ServiceEM Full Test Suite" -ForegroundColor Cyan
Write-Host "Service Principal Authentication" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load certificate
Write-Host "Loading certificate..." -ForegroundColor Yellow
$SecurePassword = ConvertTo-SecureString $CertPassword -AsPlainText -Force
$Certificate = Get-PfxCertificate -FilePath $CertPath -Password $SecurePassword
Write-Host "✓ Certificate loaded: $($Certificate.Thumbprint)" -ForegroundColor Green

# Connect to Microsoft Graph
Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Certificate $Certificate -ErrorAction Stop
    $context = Get-MgContext
    Write-Host "✓ Connected successfully!" -ForegroundColor Green
    Write-Host "  App: $($context.AppName)" -ForegroundColor Gray
    Write-Host "  Tenant: $($context.TenantId)" -ForegroundColor Gray
    Write-Host "  AuthType: $($context.AuthType)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Connection failed: $_" -ForegroundColor Red
    exit 1
}

# Get Service Principal Object ID for group ownership
Write-Host ""
Write-Host "Looking up service principal..." -ForegroundColor Yellow
$ServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$ClientId'"
$ServicePrincipalId = $ServicePrincipal.Id
Write-Host "✓ Service Principal Object ID: $ServicePrincipalId" -ForegroundColor Green

# Use service principal as owner (required for app-only auth)
$ServiceOwner = "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId"

# Import EntraOps
Write-Host ""
Write-Host "Importing EntraOps module..." -ForegroundColor Yellow
try {
    Import-Module /workspace/EntraOps/EntraOps.psd1 -Force
    Write-Host "✓ Module imported" -ForegroundColor Green
} catch {
    Write-Host "❌ Module import failed: $_" -ForegroundColor Red
    exit 1
}

# Test Configuration
$TestId = "SvcEM$(Get-Random -Minimum 1000 -Maximum 9999)"
$TestResults = @()
$CreatedGroups = @()
$CreatedCatalogs = @()

function Add-TestResult($Name, $Success, $Duration, $ErrorMsg = $null) {
    $status = if ($Success) { "✅ PASS" } else { "❌ FAIL" }
    $color = if ($Success) { "Green" } else { "Red" }
    Write-Host "$status $Name ($($Duration.TotalSeconds.ToString('F2'))s)" -ForegroundColor $color
    if ($ErrorMsg) {
        Write-Host "   $ErrorMsg" -ForegroundColor Red
    }
    $script:TestResults += [PSCustomObject]@{
        Name = $Name
        Success = $Success
        Duration = $Duration
        Error = $ErrorMsg
    }
}

# ==================== TEST 1: Group Creation ====================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST 1: Group Creation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$testStart = Get-Date
try {
    $ServiceRoles = @(
        [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
        [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""}
        [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Admins"; groupType = ""}
    )

    Write-Host "Creating groups for service: $TestId" -ForegroundColor Yellow
    $groups = New-EntraOpsServiceEntraGroup `
        -ServiceName $TestId `
        -ServiceOwner $ServiceOwner `
        -ServiceRoles $ServiceRoles `
        -Verbose

    $CreatedGroups = $groups
    Write-Host "✓ Created $($groups.Count) groups" -ForegroundColor Green
    $groups | Select-Object DisplayName, MailNickname, GroupTypes | Format-Table

    # Validate
    $membersGroup = $groups | Where-Object { $_.MailNickname -eq "$TestId.Members" }
    $usersGroup = $groups | Where-Object { $_.MailNickname -eq "$TestId.WorkloadPlane.Users" }
    
    if ($membersGroup -and $membersGroup.GroupTypes -contains "Unified") {
        Write-Host "✓ Unified group validated" -ForegroundColor Green
    }
    if ($usersGroup -and $usersGroup.SecurityEnabled) {
        Write-Host "✓ Security group validated" -ForegroundColor Green
    }

    Add-TestResult "Group Creation" $true ((Get-Date) - $testStart)
} catch {
    Add-TestResult "Group Creation" $false ((Get-Date) - $testStart) $_.Exception.Message
}

# ==================== TEST 2: Service Bootstrap ====================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST 2: Service Bootstrap" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$testStart = Get-Date
try {
    $bootstrapRoles = @(
        [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
        [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""}
    )

    Write-Host "Running service bootstrap..." -ForegroundColor Yellow
    $result = New-EntraOpsServiceBootstrap `
        -ServiceName "Bootstrap$TestId" `
        -ServiceOwner $ServiceOwner `
        -ServiceRoles $bootstrapRoles `
        -SkipAzureResourceGroup `
        -Verbose

    if ($result.CatalogId) {
        $CreatedCatalogs += $result.CatalogId
        Write-Host "✓ Catalog created: $($result.CatalogId)" -ForegroundColor Green
    }
    if ($result.AccessPackageIds -and $result.AccessPackageIds.Count -gt 0) {
        Write-Host "✓ Access packages created: $($result.AccessPackageIds.Count)" -ForegroundColor Green
    }

    Add-TestResult "Service Bootstrap" $true ((Get-Date) - $testStart)
} catch {
    Add-TestResult "Service Bootstrap" $false ((Get-Date) - $testStart) $_.Exception.Message
}

# ==================== TEST 3: Landing Zone ====================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST 3: Landing Zone (PerService)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$testStart = Get-Date
try {
    Write-Host "Creating landing zone with PerService governance..." -ForegroundColor Yellow
    $lzResult = New-EntraOpsSubscriptionLandingZone `
        -DeploymentPrefix "LZ$TestId" `
        -AzureRegion "westus2" `
        -SkipAzureResourceGroup `
        -GovernanceModel "PerService" `
        -Verbose

    Write-Host "✓ Landing zone created successfully" -ForegroundColor Green
    Add-TestResult "Landing Zone (PerService)" $true ((Get-Date) - $testStart)
} catch {
    Add-TestResult "Landing Zone (PerService)" $false ((Get-Date) - $testStart) $_.Exception.Message
}

# ==================== TEST 4: Validation Tests ====================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST 4: Input Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$testStart = Get-Date
try {
    # Test invalid ServiceOwner format
    $errorThrown = $false
    try {
        New-EntraOpsServiceEntraGroup `
            -ServiceName "InvalidTest" `
            -ServiceOwner "invalid-format" `
            -ServiceRoles @([pscustomobject]@{accessLevel = ""; name = "Test"; groupType = "Unified"}) `
            -ErrorAction Stop
    } catch {
        $errorThrown = $true
    }
    
    if ($errorThrown) {
        Write-Host "✓ Invalid ServiceOwner correctly rejected" -ForegroundColor Green
    } else {
        throw "Should have rejected invalid ServiceOwner"
    }

    Add-TestResult "Input Validation" $true ((Get-Date) - $testStart)
} catch {
    Add-TestResult "Input Validation" $false ((Get-Date) - $testStart) $_.Exception.Message
}

# ==================== CLEANUP ====================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CLEANUP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($group in $CreatedGroups) {
    try {
        Write-Host "Removing group: $($group.DisplayName)..." -ForegroundColor Gray
        Remove-MgGroup -GroupId $group.Id -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed" -ForegroundColor Gray
    } catch {
        Write-Host "  ⚠️ Error: $_" -ForegroundColor Yellow
    }
}

foreach ($catalogId in $CreatedCatalogs) {
    try {
        Write-Host "Removing catalog: $catalogId..." -ForegroundColor Gray
        Remove-MgEntitlementManagementCatalog -AccessPackageCatalogId $catalogId -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed" -ForegroundColor Gray
    } catch {
        Write-Host "  ⚠️ Error: $_" -ForegroundColor Yellow
    }
}

# ==================== SUMMARY ====================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passed = ($TestResults | Where-Object { $_.Success }).Count
$failed = ($TestResults | Where-Object { -not $_.Success }).Count
$total = $TestResults.Count

Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "✅ Passed: $passed" -ForegroundColor Green
Write-Host "❌ Failed: $failed" -ForegroundColor Red
Write-Host ""

$TestResults | Format-Table -AutoSize

Disconnect-MgGraph
Write-Host ""
Write-Host "✅ Testing complete!" -ForegroundColor Green

if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}
