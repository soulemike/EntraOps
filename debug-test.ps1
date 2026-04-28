#!/usr/bin/env pwsh
# Debug test to see actual Graph API error

$ErrorActionPreference = "Stop"

$TenantId = 'd2280e3f-26e4-4d90-b991-8933a2aac6c7'
$ClientId = '48280ee2-5903-4005-8781-91b81c004526'
$CertPath = '/workspace/Tests/ServiceEM/TestCertificates/EntraOpsTest.pfx'
$CertPassword = 'TestCert123!'

Write-Host "Connecting to Graph..." -ForegroundColor Yellow
$SecurePassword = ConvertTo-SecureString $CertPassword -AsPlainText -Force
$Certificate = Get-PfxCertificate -FilePath $CertPath -Password $SecurePassword
Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Certificate $Certificate -NoWelcome

Write-Host "Checking permissions..." -ForegroundColor Yellow
$context = Get-MgContext
Write-Host "Scopes: $($context.Scopes -join ', ')" -ForegroundColor Gray

Write-Host "`nTrying to create a simple group..." -ForegroundColor Yellow

# Get the service principal's object ID
Write-Host "Looking up service principal..." -ForegroundColor Yellow
$sp = Get-MgServicePrincipal -Filter "appId eq '$ClientId'"
Write-Host "Service Principal Object ID: $($sp.Id)" -ForegroundColor Green

# Try to create a group with the service principal as owner
$groupBody = @{
    displayName = "TestGroup$(Get-Random)"
    mailNickname = "test$(Get-Random)"
    groupTypes = @("Unified")
    mailEnabled = $true
    securityEnabled = $true
    "owners@odata.bind" = @("https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.Id)")
} | ConvertTo-Json -Depth 10

Write-Host "`nRequest body:" -ForegroundColor Yellow
Write-Host $groupBody -ForegroundColor Gray

Write-Host "`nSending request..." -ForegroundColor Yellow
try {
    $response = Invoke-MgGraphRequest -Method POST -Uri "/v1.0/groups" -Body $groupBody -ErrorAction Stop
    Write-Host "✓ Success! Group created: $($response.id)" -ForegroundColor Green
    
    # Cleanup
    Remove-MgGroup -GroupId $response.id
    Write-Host "✓ Cleaned up test group" -ForegroundColor Gray
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
    Write-Host "Error Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    Write-Host "Exception: $($_.Exception.GetType().FullName)" -ForegroundColor Red
}

Disconnect-MgGraph
