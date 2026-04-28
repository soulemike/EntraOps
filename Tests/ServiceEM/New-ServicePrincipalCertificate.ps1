#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Generates a self-signed certificate for Service Principal authentication.

.DESCRIPTION
    Creates a certificate for automated testing of ServiceEM without interactive MFA.
    The certificate can be used with Microsoft Graph PowerShell SDK for unattended
    authentication in CI/CD pipelines or automated test environments.

.PARAMETER TenantId
    The Azure AD tenant ID where the service principal will be registered.

.PARAMETER AppName
    The display name for the application registration. Default: "EntraOps-Test-Automation"

.PARAMETER CertificateName
    The subject name for the certificate. Default: "CN=EntraOpsTest"

.PARAMETER ValidityYears
    Number of years the certificate is valid. Default: 1

.PARAMETER OutputPath
    Directory to save certificate files. Default: ./TestCertificates

.EXAMPLE
    .\New-ServicePrincipalCertificate.ps1 -TenantId "M365x60294116.onmicrosoft.com"

.EXAMPLE
    .\New-ServicePrincipalCertificate.ps1 -TenantId "contoso.onmicrosoft.com" -AppName "MyTestApp" -ValidityYears 2

.OUTPUTS
    Creates three files:
    - EntraOpsTest.cer: Public certificate (upload to Azure AD)
    - EntraOpsTest.pfx: Private key with certificate (for application use)
    - ServicePrincipal.json: Configuration details

.NOTES
    After running this script, you must:
    1. Register an application in Azure AD
    2. Upload the .cer file to the app registration
    3. Grant admin consent for Microsoft Graph permissions
    4. Use the .pfx file in your automated tests
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [string]$AppName = "EntraOps-Test-Automation",

    [string]$CertificateName = "CN=EntraOpsTest",

    [int]$ValidityYears = 1,

    [string]$OutputPath = "$PSScriptRoot/TestCertificates",

    [SecureString]$CertificatePassword = (ConvertTo-SecureString -String "TestCert123!" -AsPlainText -Force)
)

#Requires -PSEdition Core

$ErrorActionPreference = "Stop"

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "✓ Created output directory: $OutputPath" -ForegroundColor Green
}

$certPath = Join-Path $OutputPath "EntraOpsTest"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Service Principal Certificate Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nConfiguration:" -ForegroundColor Yellow
Write-Host "  Tenant ID: $TenantId"
Write-Host "  App Name: $AppName"
Write-Host "  Certificate: $CertificateName"
Write-Host "  Validity: $ValidityYears year(s)"
Write-Host "  Output: $OutputPath"

# Generate certificate
Write-Host "`n🔐 Generating self-signed certificate..." -ForegroundColor Yellow

try {
    # Create certificate parameters
    $certParams = @{
        Subject = $CertificateName
        CertStoreLocation = "Cert:\\CurrentUser\\My"
        KeyAlgorithm = "RSA"
        KeyLength = 2048
        KeyExportPolicy = "Exportable"
        NotAfter = (Get-Date).AddYears($ValidityYears)
        HashAlgorithm = "SHA256"
    }

    $cert = New-SelfSignedCertificate @certParams

    Write-Host "✓ Certificate generated successfully" -ForegroundColor Green
    Write-Host "  Thumbprint: $($cert.Thumbprint)"
    Write-Host "  Valid From: $($cert.NotBefore)"
    Write-Host "  Valid To: $($cert.NotAfter)"

    # Export public certificate (CER) - for Azure AD upload
    $cerPath = "$certPath.cer"
    Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null
    Write-Host "`n📄 Exported public certificate: $cerPath" -ForegroundColor Green

    # Export private key (PFX) - for application authentication
    $pfxPath = "$certPath.pfx"
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $CertificatePassword | Out-Null
    Write-Host "📄 Exported private key: $pfxPath" -ForegroundColor Green

    # Export public key in Base64 format (alternative for some scenarios)
    $base64Cert = [Convert]::ToBase64String($cert.RawData)
    $base64Path = "$certPath-base64.txt"
    $base64Cert | Set-Content -Path $base64Path
    Write-Host "📄 Exported Base64 certificate: $base64Path" -ForegroundColor Green

    # Create configuration file
    $config = @{
        TenantId = $TenantId
        AppName = $AppName
        CertificateThumbprint = $cert.Thumbprint
        CertificateSubject = $CertificateName
        CertificateValidFrom = $cert.NotBefore.ToString("yyyy-MM-dd HH:mm:ss")
        CertificateValidTo = $cert.NotAfter.ToString("yyyy-MM-dd HH:mm:ss")
        CerFilePath = (Resolve-Path $cerPath).Path
        PfxFilePath = (Resolve-Path $pfxPath).Path
        Base64FilePath = (Resolve-Path $base64Path).Path
        SetupInstructions = @"
NEXT STEPS:
===========

1. Register Application in Azure AD:
   a. Go to Azure Portal > Azure Active Directory > App registrations
   b. Click "New registration"
   c. Name: $AppName
   d. Supported account types: Accounts in this organizational directory only
   e. Click "Register"

2. Upload Certificate:
   a. In your app registration, go to "Certificates & secrets"
   b. Click "Upload certificate"
   c. Select file: $cerPath
   d. Click "Add"
   e. Note the certificate thumbprint: $($cert.Thumbprint)

3. Configure API Permissions:
   a. Go to "API permissions"
   b. Click "Add a permission" > "Microsoft Graph" > "Application permissions"
   c. Add these permissions:
      - Group.ReadWrite.All
      - EntitlementManagement.ReadWrite.All
      - User.Read.All
      - Directory.Read.All
   d. Click "Grant admin consent"

4. Get Application ID:
   a. Go to "Overview"
   b. Copy the "Application (client) ID"
   c. Update your test scripts with this ID

5. Use in PowerShell:
   \$cert = Get-ChildItem -Path Cert:\\CurrentUser\\My\\$($cert.Thumbprint)
   Connect-MgGraph -ClientId "<YOUR-APP-ID>" -TenantId "$TenantId" -Certificate \$cert

SECURITY NOTES:
===============
- Keep the .pfx file secure - it contains the private key
- Do not commit the .pfx file to version control
- Add .pfx files to .gitignore
- Rotate certificates before expiration
- Use different certificates for different environments
"@
    }

    $configPath = Join-Path $OutputPath "ServicePrincipal.json"
    $config | ConvertTo-Json -Depth 3 | Set-Content -Path $configPath
    Write-Host "📄 Created configuration file: $configPath" -ForegroundColor Green

    # Also create a plain text instructions file
    $instructionsPath = Join-Path $OutputPath "SetupInstructions.txt"
    $config.SetupInstructions | Set-Content -Path $instructionsPath
    Write-Host "📄 Created instructions: $instructionsPath" -ForegroundColor Green

    # Display certificate details
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Certificate Details" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Subject: $($cert.Subject)"
    Write-Host "Issuer: $($cert.Issuer)"
    Write-Host "Thumbprint: $($cert.Thumbprint)"
    Write-Host "Serial Number: $($cert.SerialNumber)"
    Write-Host "Valid From: $($cert.NotBefore)"
    Write-Host "Valid To: $($cert.NotAfter)"
    Write-Host "`nFiles Generated:" -ForegroundColor Yellow
    Write-Host "  📄 $cerPath (Public - Upload to Azure AD)"
    Write-Host "  🔐 $pfxPath (Private - Keep secure)"
    Write-Host "  📄 $base64Path (Base64 encoded)"
    Write-Host "  📄 $configPath (Configuration JSON)"
    Write-Host "  📄 $instructionsPath (Setup instructions)"

    Write-Host "`n⚠️  IMPORTANT SECURITY WARNINGS:" -ForegroundColor Red
    Write-Host "  1. The .pfx file contains the PRIVATE KEY" -ForegroundColor Yellow
    Write-Host "  2. Store it securely and do not share it" -ForegroundColor Yellow
    Write-Host "  3. Add *.pfx to your .gitignore file" -ForegroundColor Yellow
    Write-Host "  4. Use environment variables or Azure Key Vault in production" -ForegroundColor Yellow

    Write-Host "`n✅ Certificate generation complete!" -ForegroundColor Green
    Write-Host "`nNext: Follow the instructions in SetupInstructions.txt" -ForegroundColor Cyan

    # Return certificate info for programmatic use
    return [PSCustomObject]@{
        Thumbprint = $cert.Thumbprint
        Subject = $cert.Subject
        ValidFrom = $cert.NotBefore
        ValidTo = $cert.NotAfter
        CerPath = $cerPath
        PfxPath = $pfxPath
        ConfigPath = $configPath
        Certificate = $cert
    }

} catch {
    Write-Host "`n❌ Error generating certificate: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
