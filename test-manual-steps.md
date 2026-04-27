# Manual Testing Steps for ServiceEM

## Prerequisites

You need to manually approve MFA during the test. Have your Microsoft Authenticator app ready.

## Option 1: Run Test Script (Recommended)

### Step 1: Start the Docker container
```bash
cd /home/azureuser/projects/EntraOps
docker run -it --rm -v "$(pwd):/workspace" -w /workspace entraops-test:latest pwsh
```

### Step 2: Inside the container, run:
```powershell
# Connect to Microsoft Graph
$TenantId = "M365x60294116.onmicrosoft.com"
$Scopes = @(
    "Group.ReadWrite.All"
    "EntitlementManagement.ReadWrite.All"
    "User.Read.All"
    "Directory.Read.All"
)

Connect-MgGraph -Scopes $Scopes -TenantId $TenantId -UseDeviceCode
```

### Step 3: When prompted, in your browser:
1. Go to: https://microsoft.com/devicelogin
2. Enter the code shown in the terminal
3. Login with: `alexw@M365x60294116.onmicrosoft.com`
4. Password: `U8v])pi327BRa#s7{~5NPv4$u#CG[J6i`
5. **Approve MFA on your device**

### Step 4: Run the test
```powershell
# Import EntraOps
Import-Module /workspace/EntraOps/EntraOps.psd1 -Force

# Run comprehensive test
/workspace/test-servicem-docker.ps1
```

## Option 2: Quick Manual Test

If the full test script has issues, run these individual commands:

```powershell
# 1. Import module
Import-Module /workspace/EntraOps/EntraOps.psd1 -Force

# 2. Set test variables
$TestPrefix = "Quick$(Get-Random -Minimum 1000 -Maximum 9999)"
$TestOwner = (Get-MgContext).Account

# 3. Test 1: Group Creation
Write-Host "Test 1: Creating test groups..." -ForegroundColor Cyan
$ServiceRoles = @(
    [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
    [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""}
)

try {
    $groups = New-EntraOpsServiceEntraGroup `
        -ServiceName "Test$TestPrefix" `
        -ServiceOwner $TestOwner `
        -ServiceRoles $ServiceRoles `
        -Verbose
    
    Write-Host "✅ SUCCESS: Created $($groups.Count) groups" -ForegroundColor Green
    $groups | Select-Object DisplayName, MailNickname | Format-Table
    
    # Cleanup
    $groups | ForEach-Object { 
        Remove-MgGroup -GroupId $_.Id
        Write-Host "Cleaned up: $($_.DisplayName)" -ForegroundColor Gray
    }
} catch {
    Write-Host "❌ FAILED: $_" -ForegroundColor Red
}

# 4. Test 2: Service Bootstrap (no Azure)
Write-Host "`nTest 2: Service Bootstrap..." -ForegroundColor Cyan
try {
    $result = New-EntraOpsServiceBootstrap `
        -ServiceName "Bootstrap$TestPrefix" `
        -ServiceOwner $TestOwner `
        -ServiceRoles $ServiceRoles `
        -SkipAzureResourceGroup `
        -Verbose
    
    Write-Host "✅ SUCCESS: Bootstrap completed" -ForegroundColor Green
    Write-Host "Catalog ID: $($result.CatalogId)" -ForegroundColor Gray
} catch {
    Write-Host "❌ FAILED: $_" -ForegroundColor Red
}

# 5. Disconnect
Disconnect-MgGraph
```

## Troubleshooting

### Issue: "Authentication timed out"
**Solution:** The device code expires after 2 minutes. Run the command again and enter the code immediately.

### Issue: "Insufficient privileges"
**Solution:** The account needs Global Administrator or the specific Graph API scopes. Check with tenant admin.

### Issue: "Module not found"
**Solution:** Make sure you're in the Docker container and the path is correct:
```powershell
Get-ChildItem /workspace/EntraOps
Import-Module /workspace/EntraOps/EntraOps.psd1 -Force
```

### Issue: "Cannot connect to Graph"
**Solution:** Verify the tenant ID and your network connection:
```powershell
Test-Connection login.microsoftonline.com -Count 2
```

## Expected Results

✅ **Passing tests should show:**
- Groups created with correct names (e.g., "Test1234 Members", "SG-Test1234-WorkloadPlane-Users")
- Unified groups for Members
- Security groups for WorkloadPlane
- Catalogs and access packages created
- Verbose logging showing delegation switch states

❌ **Failing tests might show:**
- Authentication errors (MFA not approved)
- Permission errors (missing Graph scopes)
- Validation errors (invalid parameters)
- API errors (Graph service issues)

## Cleanup

After testing, clean up created objects:

```powershell
# Remove test groups
Get-MgGroup -Filter "startswith(displayName,'Test')" | Remove-MgGroup

# Remove test catalogs  
Get-MgEntitlementManagementCatalog -Filter "startswith(displayName,'Bootstrap')" | Remove-MgEntitlementManagementCatalog
```
