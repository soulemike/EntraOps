#!/bin/bash
# Cross-platform certificate generator using OpenSSL

set -e

# Default values
TENANT_ID=""
APP_NAME="EntraOps-Test-Automation"
CERT_NAME="EntraOpsTest"
VALIDITY_DAYS=365
OUTPUT_PATH="./TestCertificates"
CERT_PASSWORD="TestCert123!"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tenant)
            TENANT_ID="$2"
            shift 2
            ;;
        -a|--app)
            APP_NAME="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        -d|--days)
            VALIDITY_DAYS="$2"
            shift 2
            ;;
        -p|--password)
            CERT_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -t, --tenant     Azure AD tenant ID (required)"
            echo "  -a, --app        Application name (default: EntraOps-Test-Automation)"
            echo "  -o, --output     Output directory (default: ./TestCertificates)"
            echo "  -d, --days       Certificate validity in days (default: 365)"
            echo "  -p, --password   Certificate password (default: TestCert123!)"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$TENANT_ID" ]; then
    echo "❌ Error: Tenant ID is required"
    echo "Usage: $0 -t <tenant-id>"
    exit 1
fi

# Check for OpenSSL
if ! command -v openssl &> /dev/null; then
    echo "❌ Error: OpenSSL is required but not installed"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_PATH"
echo "✓ Created output directory: $OUTPUT_PATH"

echo ""
echo "========================================"
echo "Service Principal Certificate Generator"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Tenant ID: $TENANT_ID"
echo "  App Name: $APP_NAME"
echo "  Certificate: $CERT_NAME"
echo "  Validity: $VALIDITY_DAYS days"
echo "  Output: $OUTPUT_PATH"
echo ""

# Generate certificate
echo "🔐 Generating self-signed certificate..."

KEY_FILE="$OUTPUT_PATH/$CERT_NAME.key"
CERT_FILE="$OUTPUT_PATH/$CERT_NAME.crt"
PFX_FILE="$OUTPUT_PATH/$CERT_NAME.pfx"
CER_FILE="$OUTPUT_PATH/$CERT_NAME.cer"
PEM_FILE="$OUTPUT_PATH/$CERT_NAME.pem"

# Generate private key
openssl genrsa -out "$KEY_FILE" 2048 2>/dev/null

# Generate certificate
openssl req -new -x509 -key "$KEY_FILE" -out "$CERT_FILE" -days $VALIDITY_DAYS \
    -subj "/CN=$CERT_NAME" 2>/dev/null

# Create PFX (PKCS#12) with private key
openssl pkcs12 -export -out "$PFX_FILE" -inkey "$KEY_FILE" -in "$CERT_FILE" \
    -password pass:"$CERT_PASSWORD" 2>/dev/null

# Export public certificate in DER format (for Azure AD)
openssl x509 -in "$CERT_FILE" -outform DER -out "$CER_FILE"

# Export public certificate in PEM format
openssl x509 -in "$CERT_FILE" -outform PEM -out "$PEM_FILE"

# Get certificate details
THUMBPRINT=$(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha1 | cut -d'=' -f2 | tr -d ':')
SERIAL=$(openssl x509 -in "$CERT_FILE" -noout -serial | cut -d'=' -f2)
VALID_FROM=$(openssl x509 -in "$CERT_FILE" -noout -startdate | cut -d'=' -f2)
VALID_TO=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d'=' -f2)

echo "✓ Certificate generated successfully"
echo "  Thumbprint: $THUMBPRINT"
echo "  Serial: $SERIAL"
echo "  Valid From: $VALID_FROM"
echo "  Valid To: $VALID_TO"

# Create Base64 version
BASE64_FILE="$OUTPUT_PATH/${CERT_NAME}-base64.txt"
base64 "$CER_FILE" > "$BASE64_FILE"
echo ""
echo "📄 Files generated:"
echo "  🔐 $KEY_FILE (Private key - keep secure)"
echo "  📄 $CERT_FILE (Public certificate)"
echo "  📄 $CER_FILE (DER format for Azure AD)"
echo "  📄 $PEM_FILE (PEM format)"
echo "  🔐 $PFX_FILE (PFX with password - for app use)"
echo "  📄 $BASE64_FILE (Base64 encoded)"

# Create JSON config
cat > "$OUTPUT_PATH/ServicePrincipal.json" << EOF
{
    "TenantId": "$TENANT_ID",
    "AppName": "$APP_NAME",
    "CertificateThumbprint": "$THUMBPRINT",
    "CertificateSubject": "CN=$CERT_NAME",
    "CertificateSerial": "$SERIAL",
    "CertificateValidFrom": "$VALID_FROM",
    "CertificateValidTo": "$VALID_TO",
    "CerFilePath": "$CER_FILE",
    "PfxFilePath": "$PFX_FILE",
    "PemFilePath": "$PEM_FILE",
    "KeyFilePath": "$KEY_FILE"
}
EOF

echo "  📄 $OUTPUT_PATH/ServicePrincipal.json (Configuration)"

# Create instructions
cat > "$OUTPUT_PATH/SetupInstructions.txt" << EOF
SERVICE PRINCIPAL SETUP INSTRUCTIONS
====================================

Certificate Details:
-------------------
Subject: CN=$CERT_NAME
Thumbprint: $THUMBPRINT
Serial: $SERIAL
Valid From: $VALID_FROM
Valid To: $VALID_TO

NEXT STEPS:
===========

1. Register Application in Azure AD:
   a. Go to Azure Portal (https://portal.azure.com)
   b. Navigate to: Azure Active Directory > App registrations
   c. Click "New registration"
   d. Name: $APP_NAME
   e. Supported account types: "Accounts in this organizational directory only"
   f. Click "Register"

2. Upload Certificate:
   a. In your app registration, go to "Certificates & secrets"
   b. Click "Upload certificate"
   c. Select file: $CER_FILE
   d. Description: "EntraOps Test Certificate"
   e. Click "Add"
   f. Note the certificate thumbprint: $THUMBPRINT

3. Configure API Permissions:
   a. Go to "API permissions"
   b. Click "Add a permission" > "Microsoft Graph" > "Application permissions"
   c. Add these permissions:
      - Group.ReadWrite.All
      - EntitlementManagement.ReadWrite.All
      - User.Read.All
      - Directory.Read.All
   d. Click "Grant admin consent for [tenant]"
   e. Confirm all permissions show "Granted for [tenant]"

4. Get Application ID:
   a. Go to "Overview"
   b. Copy the "Application (client) ID"
   c. You'll need this for testing

5. Test Connection:
   Run the following PowerShell command:

   Connect-MgGraph \\
       -ClientId "<YOUR-APPLICATION-ID>" \\
       -TenantId "$TENANT_ID" \\
       -CertificatePath "$PFX_FILE" \\
       -CertificatePassword (ConvertTo-SecureString "$CERT_PASSWORD" -AsPlainText)

6. Run Automated Tests:
   ./Test-WithServicePrincipal.ps1 \\
       -TenantId "$TENANT_ID" \\
       -ClientId "<YOUR-APPLICATION-ID>" \\
       -CertificatePath "$PFX_FILE" \\
       -CertificatePassword (ConvertTo-SecureString "$CERT_PASSWORD" -AsPlainText)

SECURITY WARNINGS:
==================
⚠️  The .pfx and .key files contain the PRIVATE KEY
⚠️  Keep them secure and do not share
⚠️  Add to .gitignore: *.pfx, *.key
⚠️  Rotate certificates before expiration ($VALID_TO)
⚠️  Use different certificates for different environments

FILES TO SECURE:
================
- $PFX_FILE (Password: $CERT_PASSWORD)
- $KEY_FILE
- This instructions file (contains password)

CLEANUP:
========
When done testing, remove the app registration from Azure AD:
1. Go to Azure AD > App registrations
2. Find "$APP_NAME"
3. Click "Delete"
EOF

echo "  📄 $OUTPUT_PATH/SetupInstructions.txt (Instructions)"

echo ""
echo "========================================"
echo "Certificate Details"
echo "========================================"
echo "Subject: CN=$CERT_NAME"
echo "Thumbprint: $THUMBPRINT"
echo "Serial: $SERIAL"
echo "Valid From: $VALID_FROM"
echo "Valid To: $VALID_TO"
echo ""
echo "⚠️  IMPORTANT SECURITY WARNINGS:"
echo "  1. The .pfx and .key files contain the PRIVATE KEY"
echo "  2. Store them securely and do not share"
echo "  3. Add to .gitignore: *.pfx, *.key"
echo "  4. Certificate password: $CERT_PASSWORD"
echo ""
echo "✅ Certificate generation complete!"
echo ""
echo "Next: Follow the instructions in:"
echo "  $OUTPUT_PATH/SetupInstructions.txt"
echo ""
