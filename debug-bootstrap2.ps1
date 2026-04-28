#!/usr/bin/env pwsh
$ErrorActionPreference = 'Continue'
$VerbosePreference = 'Continue'
$SecurePassword = ConvertTo-SecureString 'TestCert123!' -AsPlainText -Force
$Certificate = Get-PfxCertificate -FilePath '/workspace/Tests/ServiceEM/TestCertificates/EntraOpsTest.pfx' -Password $SecurePassword
Connect-MgGraph -ClientId '48280ee2-5903-4005-8781-91b81c004526' -TenantId 'd2280e3f-26e4-4d90-b991-8933a2aac6c7' -Certificate $Certificate -NoWelcome
Import-Module /workspace/EntraOps/EntraOps.psd1 -Force

$TestId = "Debug$(Get-Random)"
$ServiceOwner = 'https://graph.microsoft.com/v1.0/servicePrincipals/01dcb22a-e9fd-4181-a0bc-66abf0f4efa5'
$bootstrapRoles = @(
    [pscustomobject]@{accessLevel = ''; name = 'Members'; groupType = 'Unified'}
    [pscustomobject]@{accessLevel = 'WorkloadPlane'; name = 'Users'; groupType = ''}
)

try {
    $result = New-EntraOpsServiceBootstrap `
        -ServiceName "Bootstrap$TestId" `
        -ServiceOwner $ServiceOwner `
        -ServiceRoles $bootstrapRoles `
        -SkipAzureResourceGroup `
        -Verbose
    Write-Host "Success!" -ForegroundColor Green
    $result | Format-List
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Yellow
    Write-Host "Stack Trace:" -ForegroundColor DarkGray
    $_.ScriptStackTrace -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    
    # Check if we can get more details
    if ($_.Exception.InnerException) {
        Write-Host "Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
}
