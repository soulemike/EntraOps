# ServiceEM Quick Deployment Video Demo Script

## Overview
This document outlines a suggested video demo script for showcasing the main use case of deploying the ServiceEM solution as quickly as possible. The demo focuses on the primary user model: **Subscription Landing Zone**.

---

## Video Demo Structure (5-7 Minutes)

### Scene 1: Introduction (30 seconds)
**Visual:** Title card with EntraOps/ServiceEM logo

**Narration:**
> "Welcome to this quick deployment demo of ServiceEM, the Service-scoped Enterprise Access Model solution for Microsoft Entra and Azure. In the next few minutes, I'll show you how to deploy a complete, tiered authorization structure for an Azure subscription in under 5 minutes."

---

### Scene 2: Prerequisites Check (45 seconds)
**Visual:** PowerShell terminal with pre-configured environment

**Commands shown:**
```powershell
# Verify module is imported
Get-Module EntraOps

# Check connection status
Get-MgContext | Select-Object Account, TenantId
```

**Narration:**
> "Before we begin, ensure you have the EntraOps module imported and you're connected to Microsoft Graph with appropriate permissions. You'll need Group.ReadWrite.All, User.Read.All, and EntitlementManagement.ReadWrite.All permissions."

---

### Scene 3: Quick Deployment (2 minutes)
**Visual:** PowerShell terminal with command execution

**Command shown:**
```powershell
# Deploy a new subscription landing zone
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "Sub-Production" `
    -AzureRegion "westeurope" `
    -WorkloadPlaneAdmin "admin@contoso.com" `
    -ServiceMembers @("user1@contoso.com", "user2@contoso.com") `
    -AssignOwner
```

**Narration:**
> "With a single command, we're deploying a complete two-tier EAM authorization structure. This creates:
> - Security groups for Control Plane, Management Plane, and Workload Plane
> - Entitlement Management catalogs and access packages
> - PIM policies for just-in-time elevation
> - Azure resource groups with proper RBAC assignments
>
> The DeploymentPrefix parameter names everything consistently. WorkloadPlaneAdmin becomes the owner of all created groups, and ServiceMembers are automatically enrolled in the WorkloadPlane-Members access package."

**Visual:** Show the command output with created object IDs

---

### Scene 4: Governance Model Options (1 minute)
**Visual:** Side-by-side comparison or quick switch

**Command shown:**
```powershell
# Centralized governance model - reuse tenant-wide delegation groups
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "Sub-Shared" `
    -AzureRegion "westeurope" `
    -GovernanceModel "Centralized" `
    -ControlPlaneDelegationGroupId "00000000-0000-0000-0000-000000000001" `
    -ManagementPlaneDelegationGroupId "00000000-0000-0000-0000-000000000002"
```

**Narration:**
> "ServiceEM supports two governance models. The default PerService model creates dedicated admin groups for each landing zone. For enterprise scenarios, use the Centralized model with tenant-wide delegation groups to maintain consistent Control Plane and Management Plane administration across all your landing zones."

---

### Scene 5: Access Package Demo (1 minute)
**Visual:** Microsoft Entra admin center - Identity Governance

**Navigation shown:**
1. Identity Governance → Entitlement Management → Access Packages
2. Show the auto-created "AP-Sub-Production-WorkloadPlane-Members" package
3. Click on "Initial Workload Membership Policy" to show approval settings

**Narration:**
> "The access packages are automatically configured with approval workflows. Members can request access through My Access portal, and designated approvers are notified. All group memberships are managed through these packages, ensuring proper governance and audit trails."

---

### Scene 6: PIM Integration (1 minute)
**Visual:** Microsoft Entra admin center - Privileged Identity Management

**Navigation shown:**
1. Privileged Identity Management → Groups
2. Show eligible assignments for WorkloadPlane-Admins and ControlPlane-Admins groups
3. Demonstrate the activation process

**Narration:**
> "PIM for Groups is automatically configured. WorkloadPlane-Members can elevate to WorkloadPlane-Admins through PIM activation. ControlPlane-Admins get Azure User Access Administrator rights at subscription scope. All activations are logged and can require additional approval or MFA based on your PIM policies."

---

### Scene 7: Azure Resource Verification (30 seconds)
**Visual:** Azure Portal → Resource Groups

**Navigation shown:**
1. Show the created resource groups: "rg-Sub-Production-Sub" and "rg-Sub-Production-Rg"
2. Click on Access Control (IAM) to show role assignments

**Narration:**
> "Azure resource groups are created with proper RBAC assignments. The ControlPlane-Admins group gets User Access Administrator rights, ManagementPlane-Admins get Contributor, and WorkloadPlane-Admins get Contributor on the resource group scope."

---

### Scene 8: Summary (30 seconds)
**Visual:** Return to PowerShell terminal showing summary

**Command shown:**
```powershell
# Get a report of the deployed landing zone
Get-EntraOpsServiceEMReport -DeploymentPrefix "Sub-Production"
```

**Narration:**
> "In just a few minutes, we've deployed a complete, production-ready Enterprise Access Model structure. ServiceEM automates the complex task of setting up tiered administration, ensuring consistent security boundaries between Control Plane, Management Plane, and Workload Plane. To learn more, visit our documentation at GitHub."

---

## Key Messages to Emphasize

1. **Speed**: Complete deployment in a single command
2. **Consistency**: Standardized naming and structure across all landing zones
3. **Security**: Built-in tiered administration following Microsoft's Enterprise Access Model
4. **Governance**: Integrated with Entitlement Management and PIM for proper access control
5. **Flexibility**: Supports both per-service and centralized governance models

## Optional: Advanced Features (For Extended Demo)

If time permits, demonstrate:

### Custom Landing Zone Components
```powershell
$CustomComponents = @(
    [pscustomobject]@{
        Role = "Sub"
        ServiceRole = @(
            [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
            [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
        )
    }
)
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "Sub-Minimal" `
    -AzureRegion "westeurope" `
    -LandingZoneComponents $CustomComponents
```

### Entra-Only Deployment (No Azure Resources)
```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "Sub-Dev" `
    -SkipAzureResourceGroup `
    -NoPimEscalation
```

---

## Production Readiness Checklist

Mention these for production deployments:

- [ ] Configure EntraOpsConfig.json with delegation group IDs
- [ ] Set up authentication contexts for PIM activation
- [ ] Customize access package approval policies
- [ ] Configure monitoring and alerting for privileged access
- [ ] Document emergency access procedures

---

*This demo script was created as part of the ServiceEM feature enhancements for the feature-ElmLz branch.*
