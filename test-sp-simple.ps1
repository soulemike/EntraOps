#!/usr/bin/env pwsh
# Simple Service Principal Test

$ErrorActionPreference = "Stop"

$TenantId = 'd2280e3f-26e4-4d90-b991-8933a2aac6c7'
$ClientId = '48280ee2-5903-4005-8781-91b81c004526'
$CertPath = '/workspace/Tests/ServiceEM/TestCertificates/EntraOpsTest.pfx'
$CertPassword = 'TestCert123!'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ServiceEM Test with Service Principal" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tenant ID: $TenantId"
Write-Host "Client ID: $ClientId"
Write-Host "Certificate: $CertPath"
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
} catch {
    Write-Host "❌ Connection failed: $_" -ForegroundColor Red
    exit 1
}

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

# Run simple test
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test: Group Creation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$TestId = "SPTest$(Get-Random -Minimum 1000 -Maximum 9999)"
$ServiceRoles = @(
    [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
    [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""}
)

try {
    Write-Host "Creating test groups for: $TestId" -ForegroundColor Yellow
    $groups = New-EntraOpsServiceEntraGroup `
        -ServiceName $TestId `
        -ServiceOwner "https://graph.microsoft.com/v1.0/users/$ClientId" `
        -ServiceRoles $ServiceRoles
    
    Write-Host "✓ Created $($groups.Count) groups:" -ForegroundColor Green
    $groups | Select-Object DisplayName, MailNickname | Format-Table
    
    # Cleanup
    Write-Host "Cleaning up..." -ForegroundColor Yellow
    $groups | ForEach-Object {
        Remove-MgGroup -GroupId $_.Id -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($_.DisplayName)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "✅ Test completed successfully!" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "❌ Test failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
}

Disconnect-MgGraph
Write-Host ""
Write-Host "Disconnected." -ForegroundColor Gray
