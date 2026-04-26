# ServiceEM - Service-scoped Landing Zones for Enterprise Access Model

**Developed in collaboration with Michael Soule**

## Introduction

ServiceEM is a submodule of EntraOps that automates the provisioning and management of tiered, service-scoped landing zones aligned with Microsoft's Enterprise Access Model. It provides a complete solution for delegated administration with least-privilege access across Azure and Entra ID.

ServiceEM creates and manages:
- **Azure Resource Groups** with tier-specific RBAC assignments
- **Entra ID Security Groups** (role-assignable) for each service and tier
- **PIM for Groups** policies with configurable authentication contexts
- **Entra ID Governance Access Packages** for self-service membership
- **Constrained Delegation** using Azure ABAC conditions to limit role assignment capabilities

### Key Benefits

- **Automated Tier Enforcement**: Implements ControlPlane, ManagementPlane, and WorkloadPlane separation automatically
- **Least-Privilege Delegation**: ABAC conditions prevent escalation (e.g., ManagementPlane cannot assign Owner role)
- **Self-Service Access**: Access packages enable requestor-driven group membership with approval workflows
- **Configuration-Driven**: All settings managed through `EntraOpsConfig.json` for consistent, repeatable deployments
- **Smart Provisioning**: Detects inherited permissions to avoid redundant role assignments

## Quick Start

> **💡 Visual Learner?** See the **[ServiceEM Landing Zone Visualization](./EntraOps/Public/ServiceEM/ServiceEM-LandingZone-Visualization.md)** for interactive Mermaid diagrams showing group structures, access packages, policies, and RBAC assignments for both Centralized and PerService governance models.

### Prerequisites

#### Required (All Deployments)

1. **PowerShell 7+** with the following modules installed:
   ```powershell
   Install-Module Microsoft.Graph -Scope CurrentUser
   Install-Module Az -Scope CurrentUser
   ```

2. **EntraOps PowerShell Module** imported:
   ```powershell
   Import-Module ./EntraOps
   ```

3. **Connected sessions** to both Microsoft Graph and Azure:
   ```powershell
   Connect-MgGraph -Scopes "Group.ReadWrite.All","EntitlementManagement.ReadWrite.All"
   Connect-AzAccount
   ```

#### Required for PerService Model (Default)

The **PerService** governance model is the default and requires **no pre-existing groups**:
- All admin groups are created automatically per service
- Works out-of-the-box with minimal permissions
- Recommended for most use cases

#### Required for Centralized Model (Optional)

The **Centralized** governance model requires pre-existing delegation groups:

1. **Create persona groups** (one-time setup):
   ```powershell
   # Example: Create ControlPlane delegation group
   $controlPlaneGroup = New-MgGroup `
       -DisplayName "PRG-Tenant-ControlPlane-IdentityOps" `
       -MailNickname "PRGControlPlane" `
       -SecurityEnabled `
       -IsAssignableToRole `
       -MailEnabled:$false
   
   # Example: Create ManagementPlane delegation group
   $managementPlaneGroup = New-MgGroup `
       -DisplayName "PRG-Tenant-ManagementPlane-PlatformOps" `
       -MailNickname "PRGManagementPlane" `
       -SecurityEnabled `
       -IsAssignableToRole `
       -MailEnabled:$false
   ```

2. **Add group IDs to EntraOpsConfig.json**:
   ```json
   {
     "ServiceEM": {
       "GovernanceModel": "Centralized",
       "ControlPlaneDelegationGroupId": "<control-plane-group-id>",
       "ManagementPlaneDelegationGroupId": "<management-plane-group-id>"
     }
   }
   ```

3. **Alternative: Auto-create with elevated permissions**:
   - Grant `RoleManagement.ReadWrite.Directory` permission
   - ServiceEM will auto-create groups if they don't exist
   - Groups will be persisted to EntraOpsConfig.json

#### Governance Model Comparison

| Feature | PerService (Default) | Centralized |
|---------|---------------------|-------------|
| **Pre-existing groups** | ❌ Not required | ✅ Required |
| **Permissions needed** | Group.ReadWrite.All | + RoleManagement.ReadWrite.Directory |
| **Group count** | More (per service) | Fewer (shared) |
| **Use case** | 5-10 services, dev/test | 50+ services, production |
| **Isolation** | Higher (dedicated admins) | Lower (shared admins) |

### Basic Landing Zone Deployment

**Simple deployment with defaults (PerService model - no pre-existing groups required):**
```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "MyFirstApp" `
    -AzureRegion "westeurope" `
    -ServiceOwner "alice@contoso.com" `
    -ServiceMembers @("bob@contoso.com") `
    -Verbose
```

**What gets created:**
- **Sub scope**: Subscription-level groups, catalog, access packages, PIM policies
- **Rg scope**: Resource group `RG-Rg-MyFirstApp` with tier-specific groups and RBAC
- **Governance**: PerService model (creates per-service admin groups automatically)

**Explicit Centralized deployment (requires pre-existing groups):**
```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "MyFirstApp" `
    -AzureRegion "westeurope" `
    -ServiceOwner "alice@contoso.com" `
    -ServiceMembers @("bob@contoso.com") `
    -GovernanceModel "Centralized" `
    -Verbose
```

### Understanding Verbose Output

ServiceEM provides detailed verbose logging to help you understand what's being created and why. Key messages to watch for:

**Governance Model Detection:**
```
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Centralized governance model - using tenant-wide delegation groups
VERBOSE: [New-EntraOpsSubscriptionLandingZone] ControlPlane delegation group ID supplied: a6b79e96... — validating
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Validated ControlPlane group: prg - IdentityOps (a6b79e96...)
```
✅ **Meaning**: ServiceEM found `ControlPlaneDelegationGroupId` in config and validated the group exists

**Group Creation:**
```
VERBOSE: [New-EntraOpsServiceEntraGroup] Processing 3 Groups
VERBOSE: [New-EntraOpsServiceEntraGroup] {"DisplayName":"Rg-MyFirstApp Members",...}
VERBOSE: [New-EntraOpsServiceEntraGroup] Graph consistency found confirming
```
✅ **Meaning**: Groups were created and are now indexed by Microsoft Graph

**Delegation Injection:**
```
VERBOSE: [New-EntraOpsServiceBootstrap] Injecting delegated ControlPlane-Admins group (ID: a6b79e96...)
VERBOSE: [New-EntraOpsServiceBootstrap] Delegated ControlPlane-Admins: prg - Contoso - IdentityOps
```
✅ **Meaning**: Tenant-wide persona group was added to the service catalog (Centralized model)

**Access Package Creation:**
```
VERBOSE: [New-EntraOpsServiceEMAccessPackage] Processing 2 Access Package Roles
VERBOSE: [New-EntraOpsServiceEMAccessPackage] Creating Access Package
```
✅ **Meaning**: Access packages for WorkloadPlane-Users and WorkloadPlane-Admins are being created

**Skipped Components (Centralized Model):**
```
VERBOSE: [New-EntraOpsServiceBootstrap] Processing 0 Access Package Roles
VERBOSE: [New-EntraOpsServiceBootstrap] No access packages to configure — skipping resource assignment, policies, and member assignments
```
✅ **Meaning**: Sub scope in Centralized model has no WorkloadPlane groups → zero access packages created (expected)

**Inherited Permission Detection:**
```
VERBOSE: [New-EntraOpsServiceAZContainer] ManagementPlane-Admins already has Contributor eligible at a higher scope — skipping RG assignment
VERBOSE: [New-EntraOpsServiceAZContainer] ControlPlane-Admins already has User Access Administrator eligible at a higher scope — skipping RG assignment
```
✅ **Meaning**: ServiceEM detected subscription-level PIM assignments and skipped redundant RG-level assignments

### Complete Centralized Deployment Example with Annotated Output

Here's a complete example showing how persona-based groups (IdentityOps, PlatformOps) flow through a Centralized governance deployment:

**Command:**
```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "MyEntraOpsApp" `
    -AzureRegion "westeurope" `
    -ServiceOwner "admin@contoso.com" `
    -ServiceMembers @("alice@contoso.com", "bob@contoso.com") `
    -GovernanceModel "Centralized" `
    -Verbose
```

**EntraOpsConfig.json (relevant section):**
```json
{
  "ServiceEM": {
    "ControlPlaneDelegationGroupId": "a6b79e96-8a71-4b22-8946-1bbde6bbe8bd",
    "ManagementPlaneDelegationGroupId": "0463b6cf-de08-46c9-9fc1-48615ef75099",
    "AdministratorGroupId": "7c6eb065-92e0-4c22-9908-7506d022e05b"
  }
}
```

**Annotated Verbose Output:**

```
# 1. ServiceEM reads delegation group IDs from EntraOpsConfig.json
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Reading ControlPlaneDelegationGroupId from EntraOpsConfig
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Reading ManagementPlaneDelegationGroupId from EntraOpsConfig
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Reading AdministratorGroupId from EntraOpsConfig

# 2. Centralized governance model auto-detected
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Centralized governance model - using tenant-wide delegation groups

# 3. ControlPlane group (IdentityOps) validated
VERBOSE: [New-EntraOpsSubscriptionLandingZone] ControlPlane delegation group ID supplied: a6b79e96-8a71-4b22-8946-1bbde6bbe8bd — validating
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Validated ControlPlane group: prg - Contoso - IdentityOps  (a6b79e96-8a71-4b22-8946-1bbde6bbe8bd)

# 4. ManagementPlane group (PlatformOps) validated
VERBOSE: [New-EntraOpsSubscriptionLandingZone] ManagementPlane delegation group ID supplied: 0463b6cf-de08-46c9-9fc1-48615ef75099 — validating
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Validated ManagementPlane group: prg_Lab-Tier1.Azure.1.PlatformOps (0463b6cf-de08-46c9-9fc1-48615ef75099)

# 5. Per-service ControlPlane/ManagementPlane groups removed from ServiceRoles
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Removing ControlPlane/ManagementPlane/CatalogPlane from per-service groups
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Removing ControlPlane components from Sub ServiceRoles

# 6. Processing Sub scope (subscription-level)
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Processing LZ Role: Sub
VERBOSE: [New-EntraOpsServiceBootstrap] ServiceOwner set, looking up admin@contoso.com

# 7. ControlPlane/ManagementPlane creation skipped (centralized model)
VERBOSE: [New-EntraOpsServiceBootstrap] ControlPlaneDelegationGroupId provided — enforcing SkipControlPlaneDelegation
VERBOSE: [New-EntraOpsServiceBootstrap] ManagementPlaneDelegationGroupId provided — enforcing SkipManagementPlaneDelegation

# 8. Only Members group created for Sub scope (no WorkloadPlane at subscription level)
VERBOSE: [New-EntraOpsServiceEntraGroup] Processing 1 Groups
VERBOSE: [New-EntraOpsServiceEntraGroup] {"DisplayName":"Sub-MyEntraOpsApp Members",...}

# 9. Tenant-wide delegation groups injected into service catalog
VERBOSE: [New-EntraOpsServiceBootstrap] Injecting delegated ControlPlane-Admins group (ID: a6b79e96-8a71-4b22-8946-1bbde6bbe8bd)
VERBOSE: [New-EntraOpsServiceBootstrap] Delegated ControlPlane-Admins: prg - Contoso - IdentityOps

VERBOSE: [New-EntraOpsServiceBootstrap] Injecting delegated ManagementPlane-Admins group (ID: 0463b6cf-de08-46c9-9fc1-48615ef75099)
VERBOSE: [New-EntraOpsServiceBootstrap] Delegated ManagementPlane-Admins: prg_Lab-Tier1.Azure.1.PlatformOps

VERBOSE: [New-EntraOpsServiceBootstrap] Injecting delegated CatalogPlane-Members group (ID: 7c6eb065-92e0-4c22-9908-7506d022e05b)
VERBOSE: [New-EntraOpsServiceBootstrap] Delegated CatalogPlane-Members: dug_AAD.PrivilegedAccounts

# 10. Catalog and resources created, but no access packages (Sub scope is Unified-only)
VERBOSE: [New-EntraOpsServiceBootstrap] Service Catalog ID: 812367e5-2e4a-49c8-87a8-ffdaefa823d1
VERBOSE: [New-EntraOpsServiceBootstrap] Service Catalog Resource IDs: "793dc62a-a5fc-4d7f-9182-bd46a6b1e3bc"
VERBOSE: [New-EntraOpsServiceBootstrap] Processing 0 Access Package Roles
VERBOSE: [New-EntraOpsServiceBootstrap] No access packages to configure — skipping resource assignment, policies, and member assignments

# 11. Processing Rg scope (resource group level)
VERBOSE: [New-EntraOpsSubscriptionLandingZone] Processing LZ Role: Rg

# 12. ServiceOwner and ServiceMembers forwarded from parent cmdlet
VERBOSE: [New-EntraOpsServiceBootstrap] ServiceOwner set, looking up admin@contoso.com

# 13. WorkloadPlane groups created for Rg scope
VERBOSE: [New-EntraOpsServiceEntraGroup] Processing 3 Groups
VERBOSE: [New-EntraOpsServiceEntraGroup] {"DisplayName":"Rg-MyEntraOpsApp Members",...}
VERBOSE: [New-EntraOpsServiceEntraGroup] {"DisplayName":"SG-Rg-MyEntraOpsApp-WorkloadPlane-Users",...}
VERBOSE: [New-EntraOpsServiceEntraGroup] {"DisplayName":"SG-Rg-MyEntraOpsApp-WorkloadPlane-Admins",...}

# 14. Tenant-wide delegation groups injected again for Rg catalog
VERBOSE: [New-EntraOpsServiceBootstrap] Injecting delegated ControlPlane-Admins group (ID: a6b79e96-8a71-4b22-8946-1bbde6bbe8bd)
VERBOSE: [New-EntraOpsServiceBootstrap] Delegated ManagementPlane-Admins: prg_Lab-Tier1.Azure.1.PlatformOps

# 15. Access packages created for WorkloadPlane-Users and WorkloadPlane-Admins
VERBOSE: [New-EntraOpsServiceEMAccessPackage] Processing 2 Access Package Roles
VERBOSE: [New-EntraOpsServiceEMAccessPackage] Creating Access Package
VERBOSE: [New-EntraOpsServiceBootstrap] Service Access Package IDs: ["b564d5cf-2d4a-4b82-ba76-2e663687ec8d","691e8983-7ef3-47a2-ab9b-3901978dafd6"]

# 16. Assignment policies created
VERBOSE: [New-EntraOpsServiceEMAssignmentPolicy] Assigning Policy for Access Package ID: b564d5cf-2d4a-4b82-ba76-2e663687ec8d
VERBOSE: [New-EntraOpsServiceEMAssignmentPolicy] Assigning Policy for Access Package ID: 691e8983-7ef3-47a2-ab9b-3901978dafd6

# 17. Service members assigned to WorkloadPlane-Users, owner assigned to WorkloadPlane-Admins
VERBOSE: [New-EntraOpsServiceEMAssignment] Processing Service Member ID: alice-object-id
VERBOSE: [New-EntraOpsServiceEMAssignment] Processing Service Member ID: bob-object-id
VERBOSE: [New-EntraOpsServiceEMAssignment] Creating Assignment Request for Service Owner

# 18. PIM policies updated for WorkloadPlane groups
VERBOSE: [New-EntraOpsServicePIMPolicy] Updating PIM Policy ID: Group_baa5996e-1aee-4422-9473-1900fda1f679_707a26f7-...

# 19. Azure Resource Group created with RBAC assignments
VERBOSE: [New-EntraOpsServiceAZContainer] Azure Resource Group not found, creating
VERBOSE: Created resource group 'RG-Rg-MyEntraOpsApp' in location 'westeurope'

# 20. Inherited subscription-level permissions detected, RG assignments skipped
VERBOSE: [New-EntraOpsServiceAZContainer] ManagementPlane-Admins already has Contributor eligible at a higher scope — skipping RG assignment
VERBOSE: [New-EntraOpsServiceAZContainer] ControlPlane-Admins already has User Access Administrator eligible at a higher scope — skipping RG assignment

# 21. WorkloadPlane groups get new RG-scoped PIM eligible assignments
VERBOSE: [New-EntraOpsServiceAZContainer] Creating PIM Eligible Assignment for PrincipalId: d0daf544-dc42-4a9c-83b9-27e2d3f6c436
VERBOSE: [New-EntraOpsServiceAZContainer] Creating PIM Eligible Assignment for PrincipalId: baa5996e-1aee-4422-9473-1900fda1f679
```

**Key Takeaways:**
1. **IdentityOps group** (ControlPlane) was read from config, validated, and injected into both Sub and Rg catalogs
2. **PlatformOps group** (ManagementPlane) was read from config, validated, and injected into both catalogs
3. **No per-service ControlPlane/ManagementPlane groups** were created (Centralized model)
4. **WorkloadPlane groups** created only at Rg scope (Sub has only Unified Members group)
5. **Service members** (alice, bob) assigned to WorkloadPlane-Users access package
6. **Service owner** (admin) assigned to WorkloadPlane-Admins access package (ManagementPlane-Admins not available in Centralized Rg scope)
7. **Inherited permissions** detected at RG level, preventing redundant RBAC assignments

### Common Deployment Scenarios

**Scenario 1: Production Service with Centralized Governance**
```powershell
# 1. Configure delegation groups in EntraOpsConfig.json
$config = Get-Content EntraOpsConfig.json | ConvertFrom-Json
$config.ServiceEM.ControlPlaneDelegationGroupId = (Get-MgGroup -Filter "displayName eq 'IdentityOps'").Id
$config.ServiceEM.ManagementPlaneDelegationGroupId = (Get-MgGroup -Filter "displayName eq 'PlatformOps'").Id
$config.ServiceEM.AdministratorGroupId = (Get-MgGroup -Filter "displayName eq 'Governance-Admins'").Id
$config | ConvertTo-Json -Depth 10 | Set-Content EntraOpsConfig.json

# 2. Deploy landing zone
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "ProdAPI" `
    -AzureRegion "westeurope" `
    -ServiceOwner "api-owner@contoso.com" `
    -ServiceMembers @("dev1@contoso.com", "dev2@contoso.com") `
    -GovernanceModel "Centralized" `
    -Verbose
```

**Scenario 2: Dev/Test Service with PerService Governance**
```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "DevApp" `
    -AzureRegion "northeurope" `
    -ServiceOwner "dev-lead@contoso.com" `
    -ServiceMembers @("dev-team@contoso.com") `
    -GovernanceModel "PerService" `
    -SkipAzureResourceGroup `  # Only create Entra groups, no Azure RG
    -Verbose
```

**Scenario 3: Resource Group Only (No Subscription Scope)**
```powershell
New-EntraOpsServiceBootstrap `
    -ServiceName "Rg-MyMicroservice" `
    -ServiceOwner "owner@contoso.com" `
    -ServiceMembers @("dev@contoso.com") `
    -AzureRegion "westeurope" `
    -ServiceRoles @(
        [PSCustomObject]@{accessLevel=''; name='Members'; groupType='Unified'}
        [PSCustomObject]@{accessLevel='WorkloadPlane'; name='Users'; groupType=''}
        [PSCustomObject]@{accessLevel='WorkloadPlane'; name='Admins'; groupType=''}
    ) `
    -Verbose
```

## Overview

This document describes the configuration options for EntraOps ServiceEM landing zones, specifically focusing on constrained delegations and PIM authentication context enforcement.

## Configuration Structure

All ServiceEM configuration is located in `EntraOpsConfig.json` under the `ServiceEM` section.

### Creating Configuration File

Use the `New-EntraOpsConfigFile` cmdlet to create a new configuration file with default values:

```powershell
New-EntraOpsConfigFile -TenantName "contoso.onmicrosoft.com"
```

This will create `EntraOpsConfig.json` with:
- **ConstrainedDelegation** section with default role definitions (includes inline comments with role names)
- **PIMAuthenticationContext** section with `EnableAuthenticationContext: false` and empty authentication context IDs
- All other required ServiceEM parameters

**Default Behavior:**
- Authentication context is **disabled** by default (`EnableAuthenticationContext: false`)
- When disabled, PIM policies enforce **MFA + Business Justification only**
- Constrained delegation is configured with sensible defaults for ManagementPlane and WorkloadPlane tiers

### Basic Settings

```json
{
  "ServiceEM": {
    "ControlPlaneDelegationGroupId": "",
    "ManagementPlaneDelegationGroupId": "",
    "AdministratorGroupId": ""
  }
}
```

## Governance Models and Persona-Based Groups

ServiceEM supports two distinct governance approaches for delegated administration: **Centralized** and **PerService**. The model you choose determines whether high-privilege administrative groups are shared tenant-wide or created per-service.

### Centralized Governance Model (Default)

In the **Centralized** model, ControlPlane and ManagementPlane administrative groups are **shared across all services** in the tenant. This approach is ideal for organizations with dedicated persona-based teams (e.g., IdentityOps, PlatformOps) who manage multiple services.

**Key Characteristics:**
- **Shared delegation groups**: ControlPlane-Admins and ManagementPlane-Admins are tenant-wide groups configured once in `EntraOpsConfig.json`
- **Consistent permissions**: Same administrators have access across all landing zones
- **Reduced complexity**: Fewer groups to manage across multiple services
- **Automatic detection**: When `GovernanceModel = "Centralized"` or delegation group IDs are provided, ServiceEM automatically skips creating per-service ControlPlane/ManagementPlane groups

**Configuration in EntraOpsConfig.json:**

```json
{
  "ServiceEM": {
    "ControlPlaneDelegationGroupId": "a6b79e96-8a71-4b22-8946-1bbde6bbe8bd",
    "ManagementPlaneDelegationGroupId": "0463b6cf-de08-46c9-9fc1-48615ef75099",
    "AdministratorGroupId": "7c6eb065-92e0-4c22-9908-7506d022e05b"
  }
}
```

**Real-World Example:**

Consider an organization with two dedicated operations teams:

1. **IdentityOps Team (ControlPlane)**
   - Group: `prg - Contoso - IdentityOps`
   - Object ID: `a6b79e96-8a71-4b22-8946-1bbde6bbe8bd`
   - Responsible for: User Access Administrator delegation across all Azure subscriptions
   - PIM eligible for: Subscription-level User Access Administrator role
   - Manages: All identity-related privileged access across the tenant

2. **PlatformOps Team (ManagementPlane)**
   - Group: `prg - Contoso - PlatformOps`
   - Object ID: `0463b6cf-de08-46c9-9fc1-48615ef75099`
   - Responsible for: Azure resource management across all subscriptions
   - PIM eligible for: Contributor role on subscriptions and resource groups
   - Manages: Platform infrastructure, networking, monitoring

3. **Administrator Group (CatalogPlane)**
   - Group: `dug_AAD.PrivilegedAccounts`
   - Object ID: `7c6eb065-92e0-4c22-9908-7506d022e05b`
   - Responsible for: Entitlement Management catalog administration
   - Manages: Access package approvals, policy updates

When you run `New-EntraOpsSubscriptionLandingZone` with Centralized governance:

```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "MyApp" `
    -ServiceOwner "alice@contoso.com" `
    -ServiceMembers @("bob@contoso.com", "carol@contoso.com") `
    -GovernanceModel "Centralized"
```

**What happens:**
1. ServiceEM reads `ControlPlaneDelegationGroupId`, `ManagementPlaneDelegationGroupId`, and `AdministratorGroupId` from `EntraOpsConfig.json`
2. Validates each group exists in Entra ID
3. **Skips creating** per-service ControlPlane-Admins and ManagementPlane-Admins groups (Sub and Rg scopes)
4. **Injects** the tenant-wide delegation groups into the service's group catalog
5. Creates only WorkloadPlane-specific groups for the service:
   - `Sub-MyApp Members` (Microsoft 365 group)
   - `Rg-MyApp Members` (Microsoft 365 group)
   - `SG-Rg-MyApp-WorkloadPlane-Users` (Security group)
   - `SG-Rg-MyApp-WorkloadPlane-Admins` (Security group, PIM eligible)
6. Assigns the tenant-wide groups:
   - IdentityOps → PIM eligible User Access Administrator (subscription level)
   - PlatformOps → PIM eligible Contributor (subscription + resource group level)
   - dug_AAD.PrivilegedAccounts → Catalog administrator for access packages

**Benefits in Practice:**
- **Consistency**: The same IdentityOps team manages UAA across all 50 subscriptions in your tenant
- **Efficiency**: One PIM activation for PlatformOps gives Contributor access to work across multiple services
- **Auditability**: All ControlPlane actions trace back to a single, well-governed group
- **Reduced blast radius**: ControlPlane and ManagementPlane groups are managed outside service landing zones

### PerService Governance Model

In the **PerService** model, every service landing zone gets its own dedicated ControlPlane-Admins and ManagementPlane-Admins groups. This approach is ideal for:
- Services with dedicated administrative teams
- Security boundaries requiring fully isolated permissions
- Development/test environments where autonomy is prioritized

**Configuration:**

```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "MyApp" `
    -ServiceOwner "alice@contoso.com" `
    -GovernanceModel "PerService"
```

**What gets created (per service):**

**Sub scope:**
- `SG-Sub-MyApp-ControlPlane-Admins` (PIM eligible for UAA)
- `SG-Sub-MyApp-ManagementPlane-Admins` (PIM eligible for Contributor)
- `SG-Sub-MyApp-ManagementPlane-Members` (access package for non-admin management tasks)
- `SG-Sub-MyApp-CatalogPlane-Members` (catalog administrators)
- `Sub-MyApp Members` (Microsoft 365 group)

**Rg scope:**
- `SG-Rg-MyApp-ManagementPlane-Members`
- `SG-Rg-MyApp-WorkloadPlane-Users`
- `SG-Rg-MyApp-WorkloadPlane-Admins`
- `Rg-MyApp Members`

### How ServiceEM Reads EntraOpsConfig.json

ServiceEM integrates deeply with the `EntraOpsConfig.json` configuration file. Here's what happens during deployment:

1. **Delegation Group Resolution** (`Resolve-EntraOpsServiceEMDelegationGroup`):
   ```powershell
   # When -ControlPlaneDelegationGroupId is NOT provided as a parameter
   Get-Content EntraOpsConfig.json | ConvertFrom-Json | 
       Select-Object -ExpandProperty ServiceEM | 
       Select-Object -ExpandProperty ControlPlaneDelegationGroupId
   ```

2. **Group Validation**:
   - Retrieved ObjectId is validated against `Get-MgGroup`
   - Group DisplayName is logged to verbose output
   - If group doesn't exist, deployment fails with clear error

3. **Automatic Governance Detection**:
   ```
   IF ControlPlaneDelegationGroupId exists in config → GovernanceModel = Centralized
   IF ManagementPlaneDelegationGroupId exists in config → GovernanceModel = Centralized
   ```

**Complete EntraOpsConfig.json Example for Centralized Governance:**

```json
{
  "TenantId": "df8f0d44-5f52-4402-9a26-68566daa9fbe",
  "TenantName": "contoso.onmicrosoft.com",
  "ServiceEM": {
    "ControlPlaneDelegationGroupId": "a6b79e96-8a71-4b22-8946-1bbde6bbe8bd",
    "ManagementPlaneDelegationGroupId": "0463b6cf-de08-46c9-9fc1-48615ef75099",
    "AdministratorGroupId": "7c6eb065-92e0-4c22-9908-7506d022e05b",
    "ConstrainedDelegation": {
      "ManagementPlane": {
        "ExcludedRoleDefinitionIds": [
          "8e3af657-a8ff-443c-a75c-2fe8c4bcb635",
          "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9",
          "f58310d9-a9f6-439a-9e8d-f62e7b41a168"
        ],
        "AllowedTargetGroupFilter": "WorkloadPlane-Admins"
      },
      "WorkloadPlane": {
        "AllowedRoleDefinitionIds": [
          "00482a5a-887f-4fb3-b363-3b7fe8e74483",
          "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
        ],
        "AllowedTargetGroupFilter": "WorkloadPlane-Users"
      }
    },
    "PIMAuthenticationContext": {
      "EnableAuthenticationContext": false
    }
  }
}
```

### Governance Model Comparison

| Aspect | Centralized | PerService |
|--------|-------------|------------|
| **ControlPlane-Admins** | Single tenant-wide group (e.g., IdentityOps) | Dedicated group per service |
| **ManagementPlane-Admins** | Single tenant-wide group (e.g., PlatformOps) | Dedicated group per service |
| **Use Case** | 50+ services, dedicated operations teams | 5-10 services, service-specific teams |
| **PIM Scope** | One activation across all services | Separate activation per service |
| **Complexity** | Low (fewer groups) | High (groups scale with services) |
| **Isolation** | Lower (shared administrators) | Higher (dedicated administrators) |
| **Configuration** | `EntraOpsConfig.json` group IDs | `-GovernanceModel "PerService"` |

### Migration Between Models

**Centralized → PerService:**
1. Remove `ControlPlaneDelegationGroupId` and `ManagementPlaneDelegationGroupId` from `EntraOpsConfig.json`
2. Re-run `New-EntraOpsSubscriptionLandingZone` with `-GovernanceModel "PerService"`
3. ServiceEM will create missing per-service ControlPlane/ManagementPlane groups

**PerService → Centralized:**
1. Create tenant-wide IdentityOps and PlatformOps groups
2. Add their ObjectIds to `EntraOpsConfig.json`
3. Re-run landing zone provisioning
4. Use `Remove-EntraOpsServiceCatalog` with `-ExcludeGroupIds` to clean up old per-service groups

## Constrained Delegation Configuration

Constrained delegations limit which roles can be assigned and to which principals. This implements least-privilege access for delegated administrators.

### Configuration Schema

```json
{
  "ServiceEM": {
    "ConstrainedDelegation": {
      "ManagementPlane": {
        "ExcludedRoleDefinitionIds": [
          "8e3af657-a8ff-443c-a75c-2fe8c4bcb635",
          "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9",
          "f58310d9-a9f6-439a-9e8d-f62e7b41a168"
        ],
        "AllowedTargetGroupFilter": "WorkloadPlane-Admins",
        "_Comment_ExcludedRoles": "Owner, User Access Administrator, Role Based Access Control Administrator"
      },
      "WorkloadPlane": {
        "AllowedRoleDefinitionIds": [
          "00482a5a-887f-4fb3-b363-3b7fe8e74483",
          "..."
        ],
        "AllowedTargetGroupFilter": "WorkloadPlane-Users",
        "_Comment_AllowedRoles": "Key Vault Administrator, Key Vault Certificates Officer, ..."
      }
    }
  }
}
```

**Note:** The `_Comment_` fields are for reference only and are ignored by EntraOps. They provide human-readable role definition names corresponding to the GUIDs.

### ManagementPlane Constrained Delegation

**Scope:** ManagementPlane-Admins group

**Permissions:** Can assign **any** Azure role **EXCEPT** the high-privileged roles listed in `ExcludedRoleDefinitionIds`

**Target:** Can only assign roles to the group matching `AllowedTargetGroupFilter` (default: WorkloadPlane-Admins)

**Default Excluded Roles:**
- `8e3af657-a8ff-443c-a75c-2fe8c4bcb635` - Owner
- `18d7d88d-d35e-4fb5-a5c3-7773c20a72d9` - User Access Administrator
- `f58310d9-a9f6-439a-9e8d-f62e7b41a168` - Role Based Access Control Administrator

**Use Case:** Management-tier administrators can delegate operational roles (Contributor, specific service roles) to workload teams without granting control-plane access.

### WorkloadPlane Constrained Delegation

**Scope:** WorkloadPlane-Admins group

**Permissions:** Can assign **only** the data-plane roles listed in `AllowedRoleDefinitionIds`

**Target:** Can only assign roles to the group matching `AllowedTargetGroupFilter` (default: WorkloadPlane-Users)

**Default Allowed Roles:**
- **Key Vault roles:**
  - `00482a5a-887f-4fb3-b363-3b7fe8e74483` - Key Vault Administrator
  - `a4417e6f-fecd-4de8-b567-7b0420556985` - Key Vault Certificates Officer
  - `14b46e9e-c2b7-41b4-b07b-48a6ebf60603` - Key Vault Crypto Officer
  - `12338af0-0e69-4776-bea7-57ae8d297424` - Key Vault Crypto User
  - `21090545-7ca7-4776-b22c-e363652d74d2` - Key Vault Reader
  - `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` - Key Vault Secrets Officer
  - `4633458b-17de-408a-b874-0445c86b69e6` - Key Vault Secrets User

- **Storage roles:**
  - `ba92f5b4-2d11-453d-a403-e96b0029c9fe` - Storage Blob Data Contributor
  - `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` - Storage Blob Data Owner
  - `2a2b9908-6ea1-4ae2-8e65-a410df84e7d1` - Storage Blob Data Reader
  - `0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3` - Storage Table Data Contributor
  - `76199698-9eea-4c19-bc75-cec21354c6b6` - Storage Table Data Reader
  - `974c5e8b-45b9-4653-ba55-5f855dd0fb88` - Storage Queue Data Contributor
  - `19e7f393-937e-4f77-808e-94535e297925` - Storage Queue Data Reader
  - `8a0f0c08-91a1-4084-bc3d-661d67233fed` - Storage Queue Data Message Processor
  - `c6a89b2d-59bc-44d0-9896-0f6e12d7b80a` - Storage Queue Data Message Sender

**Use Case:** Workload administrators can grant data-plane permissions to workload users for key management and storage operations without granting management-plane access.

## PIM Authentication Context Configuration

Authentication context enforcement requires users to meet additional Conditional Access requirements when activating PIM-eligible roles.

### Configuration Schema

```json
{
  "ServiceEM": {
    "PIMAuthenticationContext": {
      "EnableAuthenticationContext": true,
      "ControlPlane": {
        "AuthenticationContextClassReferenceId": "c1",
        "AuthenticationContextDisplayName": "Require compliant device + MFA + Phishing-resistant MFA"
      },
      "ManagementPlane": {
        "AuthenticationContextClassReferenceId": "c2",
        "AuthenticationContextDisplayName": "Require compliant device + MFA"
      },
      "WorkloadPlane": {
        "AuthenticationContextClassReferenceId": "c3",
        "AuthenticationContextDisplayName": "Require MFA"
      }
    }
  }
}
```

### Settings Explained

**EnableAuthenticationContext:** `true` or `false`
- When `true`, PIM policies will require authentication context for role activation
- When `false` or not defined, PIM policies enforce **MFA + Business Justification only** (default behavior)

**Default Enforcement (when authentication context is disabled):**
The following requirements are always enforced for PIM role activation:
- **Multi-Factor Authentication (MFA):** Required for all role activations
- **Business Justification:** Required for all role activations
- **Maximum Duration:** 10 hours for role activation
- **Expiration:** Time-bounded activations required

**Per-Tier Configuration:**

Each access tier (ControlPlane, ManagementPlane, WorkloadPlane) can have different authentication contexts:

- **AuthenticationContextClassReferenceId**: The ID of the authentication context in Entra ID (e.g., "c1", "c2", "c3")
  - These must be pre-configured in **Entra ID > Protection > Conditional Access > Authentication context**
  
- **AuthenticationContextDisplayName**: Descriptive name for documentation purposes

### Example Authentication Context Strategy

**ControlPlane (Tier 0):**
- Requires phishing-resistant MFA (FIDO2/Windows Hello for Business)
- Requires compliant device (Intune managed)
- Requires MFA

**ManagementPlane (Tier 1):**
- Requires compliant device
- Requires MFA

**WorkloadPlane (Tier 2):**
- Requires MFA only

### Prerequisites

Before enabling authentication context:

1. **Create Authentication Contexts in Entra ID:**
   - Navigate to: Entra ID > Protection > Conditional Access > Authentication context
   - Create contexts with IDs matching your configuration (c1, c2, c3, etc.)

2. **Create Conditional Access Policies:**
   - Create CA policies targeting each authentication context
   - Configure required controls (MFA, device compliance, etc.)

3. **Test Authentication Contexts:**
   - Verify users can successfully authenticate with each context
   - Test PIM activation with authentication context requirements

## How It Works

### Constrained Delegation Flow

1. **User requests role activation** in PIM for Groups
2. **PIM validates** the request meets policy requirements
3. **Upon activation**, Azure RBAC enforces the condition:
   - Checks if the role being assigned is allowed/excluded
   - Checks if the target principal matches the allowed filter
4. **Role assignment succeeds** only if conditions are met

### Authentication Context Flow

1. **User activates eligible role** in PIM
2. **PIM checks** if authentication context is required
3. **User is prompted** to satisfy authentication context requirements
4. **Conditional Access evaluates** the authentication context policy
5. **Role is activated** only after successful authentication context validation

## Customization Examples

### Example 1: Add SQL Data Plane Roles to WorkloadPlane

```json
{
  "ServiceEM": {
    "ConstrainedDelegation": {
      "WorkloadPlane": {
        "AllowedRoleDefinitionIds": [
          "00482a5a-887f-4fb3-b363-3b7fe8e74483",
          "...",
          "b24988ac-6180-42a0-ab88-20f7382dd24c",
          "9b7fa17d-e63e-47b0-bb0a-15c516ac86ec"
        ],
        "AllowedTargetGroupFilter": "WorkloadPlane-Users"
      }
    }
  }
}
```

Role IDs added:
- `b24988ac-6180-42a0-ab88-20f7382dd24c` - SQL DB Contributor
- `9b7fa17d-e63e-47b0-bb0a-15c516ac86ec` - SQL Security Manager

### Example 2: Different Authentication Contexts per Environment

Development environment (relaxed):
```json
{
  "PIMAuthenticationContext": {
    "EnableAuthenticationContext": true,
    "WorkloadPlane": {
      "AuthenticationContextClassReferenceId": "c5",
      "AuthenticationContextDisplayName": "Require MFA only"
    }
  }
}
```

Production environment (strict):
```json
{
  "PIMAuthenticationContext": {
    "EnableAuthenticationContext": true,
    "WorkloadPlane": {
      "AuthenticationContextClassReferenceId": "c6",
      "AuthenticationContextDisplayName": "Require MFA + Compliant Device + Terms of Use"
    }
  }
}
```

### Example 3: Disable Authentication Context

```json
{
  "ServiceEM": {
    "PIMAuthenticationContext": {
      "EnableAuthenticationContext": false
    }
  }
}
```

When disabled, PIM policies will still require MFA and Justification (as defined in the base policy), but will not enforce authentication context.

## Troubleshooting

### Authentication Context Not Applied

**Symptom:** Users can activate roles without being prompted for authentication context

**Possible Causes:**
1. `EnableAuthenticationContext` is set to `false`
2. Authentication context ID doesn't exist in Entra ID
3. No Conditional Access policy targets the authentication context
4. User's session already satisfies the authentication context requirements

**Resolution:**
1. Verify configuration in `EntraOpsConfig.json`
2. Check authentication contexts exist: Entra ID > Protection > Conditional Access > Authentication context
3. Verify CA policies are enabled and properly scoped
4. Test with a fresh browser session

### Constrained Delegation Not Working

**Symptom:** Users can assign roles they shouldn't be able to

**Possible Causes:**
1. Configuration not loaded from `EntraOpsConfig.json`
2. Role assignment conditions not applied correctly
3. User has a direct (non-constrained) role assignment

**Resolution:**
1. Check verbose logs during ServiceEM deployment
2. Verify role assignment conditions in Azure Portal: Resource > Access Control (IAM) > Role assignments > View conditions
3. Review all role assignments for the user/group

## Security Considerations

### ProhibitDirectElevation Parameter

By default, ServiceEM creates **PIM staging groups** (`*-PIM-Staging`) that allow emergency direct member additions for break-glass scenarios. When you want to enforce **strict PIM-only access** with no bypass mechanism, use the `-ProhibitDirectElevation` parameter:

```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "ProdCritical" `
    -ServiceOwner "owner@contoso.com" `
    -ProhibitDirectElevation `  # No PIM staging groups = no emergency bypass
    -Verbose
```

**What changes:**
- **Without** `-ProhibitDirectElevation`:
  - Creates groups like `SG-Rg-MyApp-ManagementPlane-Admins-PIM-Staging`
  - Admins can be added directly to staging groups for emergency access
  - PIM policies still enforce MFA + Justification for eligible activations
  
- **With** `-ProhibitDirectElevation`:
  - No staging groups created
  - **Only** PIM-eligible assignments allowed
  - No mechanism for emergency bypass (stricter, but requires functioning PIM service)

**When to use:**
- ✅ Production environments with mature PIM governance
- ✅ Services handling highly sensitive data
- ✅ Compliance requirements mandating zero standing access
- ❌ Services requiring emergency break-glass access paths
- ❌ Environments new to PIM (limited operational maturity)

### Service Owner and Member Assignment

**Owner vs. Members:**
- **ServiceOwner**: Assigned to ManagementPlane-Admins access package (or WorkloadPlane-Admins in Centralized Rg scope)
- **ServiceMembers**: Assigned to WorkloadPlane-Members access package (or WorkloadPlane-Users in Centralized Rg scope)

By default, the owner is also added to the members list. Use `-OwnerIsNotMember` to exclude:

```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "MyApp" `
    -ServiceOwner "manager@contoso.com" `
    -ServiceMembers @("dev1@contoso.com", "dev2@contoso.com") `
    -OwnerIsNotMember  # Manager only gets admin access, not member access
```

## Security Considerations (General)

1. **Regular Review:** Periodically review and update allowed/excluded role lists
2. **Least Privilege:** Start with minimal permissions and expand as needed
3. **Monitoring:** Monitor PIM activations and role assignments through Azure Monitor
4. **Authentication Context Updates:** Ensure CA policies remain effective as threats evolve
5. **Break-Glass Accounts:** Maintain emergency access accounts that bypass authentication context for critical scenarios

---

## Reference

### Cmdlet Inventory

ServiceEM provides 17 cmdlets for automated landing zone provisioning and management:

| # | Cmdlet | Purpose |
|---|---|---|
| 1 | `New-EntraOpsServiceBootstrap` | **Orchestrator** — calls all other cmdlets in correct sequence for complete service provisioning |
| 2 | `New-EntraOpsServiceEntraGroup` | Creates Entra ID security groups and unified (M365) groups with correct naming and role-assignable flags |
| 3 | `New-EntraOpsServiceEMCatalog` | Creates Entitlement Management catalog (e.g., `Catalog-Sub-MyApp`) with idempotent lookup |
| 4 | `New-EntraOpsServiceEMCatalogResource` | Registers service groups as catalog resources (required before creating access packages) |
| 5 | `New-EntraOpsServiceEMCatalogResourceRole` | Assigns catalog roles: Owner (ControlPlane), Reader (CatalogPlane), ApAssignmentManager (ManagementPlane) |
| 6 | `New-EntraOpsServiceEMAccessPackage` | Creates access packages for WorkloadPlane and ManagementPlane roles (excludes ControlPlane) |
| 7 | `New-EntraOpsServiceEMAccessPackageResourceAssignment` | Maps group Member roles into access packages as resource role scopes |
| 8 | `New-EntraOpsServiceEMAssignmentPolicy` | Creates approval policies: requestor scopes, approvers, expiration, review schedules |
| 9 | `New-EntraOpsServiceEMAssignment` | Initial `adminAdd` assignments: service members → WorkloadPlane-Users/Members; owner → WorkloadPlane-Admins/ManagementPlane-Admins |
| 10 | `New-EntraOpsServicePIMPolicy` | Configures PIM activation policies: MFA, justification, authentication context, max duration (10 hours) |
| 11 | `New-EntraOpsServicePIMAssignment` | Creates PIM eligibility assignments: `{ServiceName} Members` group → eligible member of WorkloadPlane/ManagementPlane groups |
| 12 | `New-EntraOpsServiceAZContainer` | Creates Azure Resource Group with PIM-eligible RBAC (Contributor, UAA) and constrained delegation conditions |
| 13 | `New-EntraOpsSubscriptionLandingZone` | **Landing Zone** — Sub + Rg split variant; orchestrates Bootstrap for both subscription and resource group scopes |
| 14 | `New-EntraOpsSubscriptionLandingZoneAlt` | **Landing Zone** — Alternative flat single-call variant (deprecated in favor of `New-EntraOpsSubscriptionLandingZone`) |
| 15 | `New-EntraOpsTenantLandingZone` | **Landing Zone** — Multi-component tenant-wide deployment (Billing, Mgs, Subs, Rg scopes) |
| 16 | `Get-EntraOpsServiceEMReport` | Read-only reporting cmdlet for auditing existing service configurations |
| 17 | `Remove-EntraOpsServiceCatalog` | Cleanup cmdlet — removes catalog, access packages, assignments, and optionally groups (use `-ExcludeGroupIds` to preserve delegation groups) |

### Naming Conventions

ServiceEM follows consistent naming patterns for all created resources:

| Resource Type | Pattern | Example |
|---|---|---|
| **Unified Group** | `{ServiceName} Members` | `Sub-MyApp Members` |
| **Security Group** | `SG-{ServiceName}-{AccessLevel}-{Name}` | `SG-Rg-MyApp-WorkloadPlane-Admins` |
| **PIM Proxy Group** | `SG-{ServiceName}-PIM-{AccessLevel}-{Name}` | `SG-Sub-MyApp-PIM-ManagementPlane-Admins` |
| **Delegation Group (ControlPlane)** | `PRG-{Scope}-{AccessLevel}-{Persona}` | `PRG-Tenant-ControlPlane-IdentityOps` |
| **Delegation Group (ManagementPlane)** | `PRG-{Scope}-{AccessLevel}-Persona}` | `PRG-Tenant-ManagementPlane-PlatformOps` |
| **EM Catalog** | `Catalog-{ServiceName}` | `Catalog-Rg-MyApp` |
| **Access Package** | `AP-{ServiceName}-{AccessLevel}-{Name}` | `AP-Rg-MyApp-WorkloadPlane-Users` |
| **Resource Group** | `RG-{ServiceName}` | `RG-Rg-MyApp` |

**Scope Prefixes:**
- `Sub-{DeploymentPrefix}` — Subscription-level resources
- `Rg-{DeploymentPrefix}` — Resource group-level resources
- `Billing-{DeploymentPrefix}` — Billing scope (TenantLandingZone)
- `Mgs-{DeploymentPrefix}` — Management group scope (TenantLandingZone)

### Groups Created per Service

Groups created depend on the **governance model** and **scope**. Below shows what gets created in each scenario:

#### Centralized Governance Model (Default)

**Sub Scope:**
| Group | Type | Purpose |
|---|---|---|
| `Sub-{Prefix} Members` | Unified (M365) | Team collaboration group; PIM eligibility principal |

**Rg Scope:**
| Group | Type | Purpose |
|---|---|---|
| `Rg-{Prefix} Members` | Unified (M365) | Team collaboration group |
| `SG-Rg-{Prefix}-WorkloadPlane-Users` | Security | End-user data-plane access; PIM eligible for data-plane roles |
| `SG-Rg-{Prefix}-WorkloadPlane-Admins` | Security | Workload admin elevation; PIM eligible for Contributor + constrained RBAC Administrator |

**NOT Created (Centralized):**
- ❌ ControlPlane-Admins (delegated from `EntraOpsConfig.ControlPlaneDelegationGroupId`)
- ❌ ManagementPlane-Admins (delegated from `EntraOpsConfig.ManagementPlaneDelegationGroupId`)
- ❌ ManagementPlane-Members (replaced by delegation group)
- ❌ CatalogPlane-Members (delegated from `EntraOpsConfig.AdministratorGroupId`)
- ❌ WorkloadPlane-Members (not used in Centralized model; WorkloadPlane-Users replaces it)
- ❌ PIM staging groups for delegated groups

#### PerService Governance Model

**Sub Scope:**
| Group | Type | Purpose |
|---|---|---|
| `Sub-{Prefix} Members` | Unified (M365) | Team collaboration group; PIM eligibility principal |
| `SG-Sub-{Prefix}-CatalogPlane-Members` | Security | Catalog administrators; access package approvers |
| `SG-Sub-{Prefix}-ManagementPlane-Members` | Security | Management tier membership |
| `SG-Sub-{Prefix}-ManagementPlane-Admins` | Security | Management tier elevation; PIM eligible for Contributor + constrained RBAC Administrator |
| `SG-Sub-{Prefix}-ControlPlane-Admins` | Security | Catalog owner; PIM eligible for User Access Administrator |
| `SG-Sub-{Prefix}-PIM-ManagementPlane-Admins` | Security (optional) | PIM proxy group (created unless `-ProhibitDirectElevation` used) |

**Rg Scope:**
| Group | Type | Purpose |
|---|---|---|
| `Rg-{Prefix} Members` | Unified (M365) | Team collaboration group |
| `SG-Rg-{Prefix}-CatalogPlane-Members` | Security | Catalog administrators |
| `SG-Rg-{Prefix}-ManagementPlane-Members` | Security | Management tier membership |
| `SG-Rg-{Prefix}-ManagementPlane-Admins` | Security | Management tier elevation |
| `SG-Rg-{Prefix}-WorkloadPlane-Members` | Security | Workload tier membership |
| `SG-Rg-{Prefix}-WorkloadPlane-Users` | Security | End-user data-plane access |
| `SG-Rg-{Prefix}-WorkloadPlane-Admins` | Security | Workload admin elevation |

### Access Packages Created

Access packages are **only created for groups**, not for delegated groups. The number and type depend on governance model and scope:

#### Centralized Governance — Rg Scope Only

| Access Package | Grants Membership To | Requestors | Approver | Expiration |
|---|---|---|---|---|
| `AP-Rg-{Prefix}-WorkloadPlane-Users` | `SG-Rg-{Prefix}-WorkloadPlane-Users` | CatalogPlane-Members | WorkloadPlane-Admins (or CatalogPlane fallback) | 5 days |
| `AP-Rg-{Prefix}-WorkloadPlane-Admins` | `SG-Rg-{Prefix}-WorkloadPlane-Admins` | WorkloadPlane-Members (or CatalogPlane fallback) | ManagementPlane-Admins (delegated group) | 5 days |

**Sub Scope**: No access packages created (only Unified Members group exists).

#### PerService Governance

**Sub Scope:**
| Access Package | Grants Membership To | Requestors | Approver | Expiration |
|---|---|---|---|---|
| `AP-Sub-{Prefix}-CatalogPlane-Members` | `SG-Sub-{Prefix}-CatalogPlane-Members` | CatalogPlane-Members | CatalogPlane-Members | 5 days |
| `AP-Sub-{Prefix}-ManagementPlane-Members` | `SG-Sub-{Prefix}-ManagementPlane-Members` | WorkloadPlane-Members | ManagementPlane-Admins | None |

**Rg Scope:**
| Access Package | Grants Membership To | Requestors | Approver | Expiration |
|---|---|---|---|---|
| `AP-Rg-{Prefix}-CatalogPlane-Members` | `SG-Rg-{Prefix}-CatalogPlane-Members` | CatalogPlane-Members | CatalogPlane-Members | 5 days |
| `AP-Rg-{Prefix}-ManagementPlane-Members` | `SG-Rg-{Prefix}-ManagementPlane-Members` | WorkloadPlane-Members | ManagementPlane-Admins | None |
| `AP-Rg-{Prefix}-WorkloadPlane-Members` | `SG-Rg-{Prefix}-WorkloadPlane-Members` | All directory members | Org-chart manager (L1), fallback CatalogPlane-Members | None |
| `AP-Rg-{Prefix}-WorkloadPlane-Users` | `SG-Rg-{Prefix}-WorkloadPlane-Users` | CatalogPlane-Members | WorkloadPlane-Admins | 5 days |
| `AP-Rg-{Prefix}-WorkloadPlane-Admins` | `SG-Rg-{Prefix}-WorkloadPlane-Admins` | WorkloadPlane-Members | ManagementPlane-Admins | 5 days |
| `AP-Rg-{Prefix}-ManagementPlane-Admins` | `SG-Rg-{Prefix}-ManagementPlane-Admins` | ManagementPlane-Members | ManagementPlane-Admins | 5 days |

> **Note**: No access packages are created for ControlPlane-Admins or ManagementPlane-Admins in PerService model either — membership is managed directly by ControlPlane admins.

### Module Dependencies

ServiceEM requires the following PowerShell modules:

| Module | Minimum Version | Used By Cmdlets |
|---|---|---|
| **Microsoft.Graph.Groups** | 2.0+ | `New-EntraOpsServiceEntraGroup`, `New-EntraOpsServicePIMAssignment` |
| **Microsoft.Graph.Identity.Governance** | 2.0+ | All EM cmdlets (Catalog, AccessPackage, AssignmentPolicy, Assignment), PIM cmdlets (Policy, Assignment) |
| **Microsoft.Graph.Users** | 2.0+ | `New-EntraOpsServiceBootstrap` (ServiceOwner/ServiceMembers lookup) |
| **Microsoft.Graph.Authentication** | 2.0+ | `New-EntraOpsServiceBootstrap` (context validation) |
| **Az.Resources** | 6.0+ | `New-EntraOpsServiceAZContainer` (Resource Group creation, RBAC assignments, PIM policies) |

**Installation:**
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module Az -Scope CurrentUser -Force
```

**Required Scopes:**
```powershell
Connect-MgGraph -Scopes @(
    "Group.ReadWrite.All",
    "EntitlementManagement.ReadWrite.All",
    "RoleManagement.ReadWrite.Directory",
    "User.Read.All"
)
Connect-AzAccount
```

### Delegation Behavior Summary

When a delegation Group ID is provided (via `EntraOpsConfig.json` or parameter), the following behavior applies:

| Behavior | ControlPlane | ManagementPlane | CatalogPlane |
|---|---|---|---|
| **Group created** | No | No | No |
| **Synthetic entry injected** | Yes (with DisplayName) | Yes (with DisplayName) | Yes (with DisplayName) |
| **Catalog role assigned** | Yes (Owner) | Yes (ApAssignmentManager) | Yes (Reader) |
| **Referenced as AP approver** | — | Yes | Yes |
| **Azure RBAC assigned** | Yes (UAA, PIM-eligible) | Yes (Contributor, PIM-eligible; Reader, permanent) | — |
| **PIM policy applied to group** | No (managed externally) | No (managed externally) | No (managed externally) |
| **PIM eligibility created** | No (managed externally) | No (managed externally) | No (managed externally) |
| **Access package created** | No | No | No |

The delegated groups are **read-only** from ServiceEM's perspective — they receive role assignments and policy references but are never modified (no PIM policies, no eligibility assignments).

## References

### Documentation

- **[ServiceEM Landing Zone Visualization](./EntraOps/Public/ServiceEM/ServiceEM-LandingZone-Visualization.md)** - Comprehensive Mermaid diagrams showing:
  - Group structure by EAM plane (ControlPlane, ManagementPlane, WorkloadPlane, CatalogPlane)
  - Access package → group resource role scopes
  - Assignment policies with requestor scopes and approvers
  - Azure Resource Group RBAC assignments
  - Catalog role assignments
  - Centralized vs. PerService governance model differences
  - Initial user/owner assignment flows

### Microsoft Documentation

- [Azure ABAC Conditions](https://learn.microsoft.com/en-us/azure/role-based-access-control/conditions-format)
- [Authentication Context in Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-cloud-apps#authentication-context)
- [PIM for Groups](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/concept-pim-for-groups)
- [Azure Built-in Roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)
