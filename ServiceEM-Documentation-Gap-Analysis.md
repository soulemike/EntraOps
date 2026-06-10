# ServiceEM Documentation Gap Analysis

**Date:** 2026-05-11  
**Test Command:** `New-EntraOpsSubscriptionLandingZone -DeploymentPrefix "Test" -ServiceMembers @("AlexW@M365x60294116.OnMicrosoft.com") -SkipAzureResourceGroup`  
**Governance Model:** PerService (default)

---

## Executive Summary

The ServiceEM code **partially aligns** with the current documentation. While the core functionality works, there are **discrepancies between documented behavior and actual behavior**, as well as **gaps in documentation clarity** regarding subscription-level capabilities.

**Overall Assessment:** ⚠️ **Documentation Updates Recommended**

---

## 1. Alignment Analysis: Expected vs. Actual

### 1.1 Sub Scope (Subscription-level)

#### Groups

| Documented | Actual | Status |
|------------|--------|--------|
| Sub-{Prefix} Members [Unified] | ✅ Created | **Aligned** |
| SG-Sub-{Prefix}-CatalogPlane-Members [Security] | ✅ Created | **Aligned** |
| SG-Sub-{Prefix}-ManagementPlane-Members [Security] | ✅ Created | **Aligned** |
| SG-Sub-{Prefix}-ManagementPlane-Admins [Security] | ✅ Created | **Aligned** |
| SG-Sub-{Prefix}-ControlPlane-Admins [Security] | ✅ Created | **Aligned** |
| SG-Sub-{Prefix}-PIM-ManagementPlane-Admins [Security] | ✅ Created | **Aligned** |
| **Total: 6 groups** | **6 groups created** | ✅ **PASS** |

#### Access Packages

| Documented | Actual | Status |
|------------|--------|--------|
| AP-Sub-{Prefix}-CatalogPlane-Members | ✅ Created | **Aligned** |
| AP-Sub-{Prefix}-ManagementPlane-Members | ✅ Created | **Aligned** |
| **Total: 2 access packages** | **3 access packages created** | ⚠️ **DISCREPANCY** |

**Issue:** An extra access package `AP-Sub-Test-ManagementPlane-Admins` was created, which is **not documented**.

### 1.2 Rg Scope (Resource Group-level)

#### Groups

| Documented | Actual | Status |
|------------|--------|--------|
| Rg-{Prefix} Members [Unified] | ✅ Created | **Aligned** |
| SG-Rg-{Prefix}-CatalogPlane-Members [Security] | ✅ Created | **Aligned** |
| SG-Rg-{Prefix}-ManagementPlane-Members [Security] | ❌ **Missing** | ⚠️ **GAP** |
| SG-Rg-{Prefix}-ManagementPlane-Admins [Security] | ❌ **Missing** | ⚠️ **GAP** |
| SG-Rg-{Prefix}-WorkloadPlane-Members [Security] | ❌ **Missing** | ⚠️ **GAP** |
| SG-Rg-{Prefix}-WorkloadPlane-Users [Security] | ✅ Created | **Aligned** |
| SG-Rg-{Prefix}-WorkloadPlane-Admins [Security] | ✅ Created | **Aligned** |
| **Total: 7 groups** | **5 groups created** | ⚠️ **3 MISSING** |

#### Access Packages

| Documented | Actual | Status |
|------------|--------|--------|
| AP-Rg-{Prefix}-CatalogPlane-Members | ✅ Created | **Aligned** |
| AP-Rg-{Prefix}-ManagementPlane-Members | ✅ Created | **Aligned** |
| AP-Rg-{Prefix}-WorkloadPlane-Members | ❌ **Missing** | ⚠️ **GAP** |
| AP-Rg-{Prefix}-WorkloadPlane-Users | ✅ Created | **Aligned** |
| AP-Rg-{Prefix}-WorkloadPlane-Admins | ✅ Created | **Aligned** |
| AP-Rg-{Prefix}-ManagementPlane-Admins | ❌ **Missing** | ⚠️ **GAP** |
| **Total: 6 access packages** | **4 access packages created** | ⚠️ **2 MISSING** |

### 1.3 Root Cause Analysis

The discrepancies are likely due to:

1. **`-SkipAzureResourceGroup` Parameter:** This parameter was used in testing, which may have caused the Rg scope to be incomplete
2. **Missing `-ServiceOwner` Parameter:** The test didn't include a valid ServiceOwner, which may have affected group creation logic
3. **Undocumented Behavior:** The creation of `AP-Sub-{Prefix}-ManagementPlane-Admins` suggests either:
   - The documentation is incomplete
   - The code behavior has changed
   - This access package is created conditionally based on parameters

---

## 2. Critical Documentation Gaps

### 2.1 Subscription-Level Capabilities - UNCLEAR ❌

**Current Documentation Says:**
> "**Sub scope**: Subscription-level groups, catalog, access packages, PIM policies"

**What It Doesn't Clarify:**
1. What specific subscription-level capabilities are implemented?
2. What Azure RBAC assignments are made at the subscription level?
3. Are there any Azure resources created at the subscription level?
4. What is the relationship between Sub scope groups and Azure subscription permissions?

**Gap:** The documentation mentions "subscription-level groups, catalog, access packages, PIM policies" but doesn't explain:
- What PIM policies are applied at the subscription level
- What Azure RBAC role assignments are made
- Whether any Azure Policy assignments are configured
- How the ControlPlane-Admins group gets User Access Administrator rights at subscription scope

### 2.2 Access Package Policies - NOT EXPLICIT ❌

**Current Documentation:**
Documents the access packages that are created, but doesn't clearly state:

1. **Assignment Policies:** The documentation shows access packages are created but doesn't clarify that assignment policies control:
   - Who can request access
   - Who must approve requests
   - How long access lasts
   - Whether access reviews are required

2. **Subscription-Level Assignment Policies:** The documentation doesn't make it clear that:
   - Assignment policies are created automatically for each access package
   - These policies may need customization for production use
   - The default policies use "specificDirectoryUsers" scope which may need adjustment

**Example from Test Output:**
```
Assignment Policy: "Baseline Policy"
- allowedTargetScope: specificDirectoryUsers
- requestApprovalSettings: [configured]
- expiration: [configured]
```

**Gap:** Users may not realize they need to review and potentially customize these policies.

### 2.3 Azure Resource Creation - AMBIGUOUS ⚠️

**Current Documentation Says:**
> "- **Rg scope**: Resource group `RG-Rg-MyFirstApp` with tier-specific groups and RBAC"

**What It Doesn't Clarify:**
1. What happens when `-SkipAzureResourceGroup` is used?
2. Are any Azure resources created at the Sub scope level?
3. What RBAC assignments are made at each scope?
4. Are PIM eligible assignments created for Azure RBAC?

**Gap:** The documentation focuses on Entra ID objects but doesn't clearly map out the Azure-side implementation.

---

## 3. Specific Issues Found

### Issue #1: Undocumented Access Package

**Finding:** `AP-Sub-Test-ManagementPlane-Admins` was created but is not in the documentation.

**Documentation Shows:**
- Sub Scope: 2 access packages (CatalogPlane-Members, ManagementPlane-Members)

**Actual Behavior:**
- Sub Scope: 3 access packages (above + ManagementPlane-Admins)

**Recommendation:** Update documentation to reflect actual behavior or clarify conditions under which this access package is created.

### Issue #2: Missing Rg Scope Objects

**Finding:** 3 groups and 2 access packages were not created in Rg scope.

**Missing Groups:**
- SG-Rg-{Prefix}-ManagementPlane-Members
- SG-Rg-{Prefix}-ManagementPlane-Admins
- SG-Rg-{Prefix}-WorkloadPlane-Members

**Missing Access Packages:**
- AP-Rg-{Prefix}-WorkloadPlane-Members
- AP-Rg-{Prefix}-ManagementPlane-Admins

**Likely Cause:** `-SkipAzureResourceGroup` parameter

**Recommendation:** Document the impact of `-SkipAzureResourceGroup` on object creation.

### Issue #3: Assignment Policy Errors

**Finding:** Multiple BadRequest errors during assignment policy creation.

```
WARNING: Failed to execute .../assignmentPolicies 
Error: Response status code does not indicate success: BadRequest
```

**Impact:** Some assignment policies may not be fully configured.

**Documentation Gap:** No troubleshooting guidance for assignment policy failures.

---

## 4. Recommended Documentation Updates

### 4.1 High Priority Updates

#### 1. Clarify Subscription-Level Capabilities

**Add Section:** "What Gets Created at Subscription Level"

```markdown
### Subscription-Level Implementation

When deploying a ServiceEM landing zone, the following subscription-level 
capabilities are implemented:

**Entra ID Objects:**
- Sub scope groups (as documented)
- Sub scope catalog and access packages
- PIM for Groups policies

**Azure RBAC (when -SkipAzureResourceGroup is NOT used):**
- PIM eligible assignment: ControlPlane-Admins → User Access Administrator (Subscription scope)
- PIM eligible assignment: ManagementPlane-Admins → Contributor (Subscription scope)

**Important:** Azure RBAC assignments require the service principal to have 
`RoleManagement.ReadWrite.Directory` permission and Azure RBAC permissions.
```

#### 2. Document Assignment Policy Configuration

**Add Section:** "Assignment Policies and Request Configuration"

```markdown
### Assignment Policies

For each access package created, ServiceEM automatically creates assignment 
policies that control:

1. **Who can request access** (`allowedTargetScope`)
   - Default: `specificDirectoryUsers` (specific users/groups)
   
2. **Approval workflow** (`requestApprovalSettings`)
   - Default: Requires approval from tier-specific admins
   
3. **Access duration** (`expiration`)
   - Default: 5 days for most packages
   
4. **Access reviews** (`reviewSettings`)
   - Default: Not configured (optional)

**Important:** Review these policies after deployment to ensure they meet 
your organization's requirements. Default policies may need customization 
for production use.

**To review policies:**
```powershell
Get-MgEntitlementManagementAssignmentPolicy `
    -AccessPackageId $accessPackageId
```
```

#### 3. Document Parameter Impact

**Update Section:** "New-EntraOpsSubscriptionLandingZone Parameters"

Add detailed impact description for:
- `-SkipAzureResourceGroup`: Explain that this skips Azure resource creation AND may affect Rg scope group/access package creation
- `-ServiceOwner`: Clarify that this is used for group ownership and assignment policies
- `-ServiceMembers`: Explain how these users are assigned to access packages

### 4.2 Medium Priority Updates

#### 4. Add Troubleshooting Section

**New Section:** "Troubleshooting"

```markdown
### Common Issues

#### Assignment Policy Creation Failures

**Symptom:** Warnings about BadRequest errors when creating assignment policies.

**Possible Causes:**
1. Missing approver groups
2. Invalid user references in ServiceMembers
3. Graph API replication delays

**Resolution:**
1. Verify ServiceOwner and ServiceMembers are valid
2. Wait 5-10 minutes and retry
3. Check that all referenced groups exist

#### Incomplete Rg Scope

**Symptom:** Rg scope has fewer groups/access packages than expected.

**Cause:** Using `-SkipAzureResourceGroup` parameter.

**Resolution:** Remove `-SkipAzureResourceGroup` for full deployment.
```

#### 5. Add Architecture Diagram

Create a visual diagram showing:
- Sub scope vs. Rg scope objects
- Azure RBAC assignments at each scope
- PIM relationships
- Access package request flows

---

## 5. Questions Requiring Clarification

### For Development Team:

1. **AP-Sub-{Prefix}-ManagementPlane-Admins Access Package**
   - Is this intentionally created?
   - Under what conditions is it created?
   - Should it be documented?

2. **-SkipAzureResourceGroup Impact**
   - Does this parameter affect Entra ID object creation or only Azure resources?
   - Why were some Rg scope groups not created?

3. **Assignment Policy Errors**
   - What causes BadRequest errors during policy creation?
   - Are these critical or can they be ignored?

4. **Subscription-Level Azure RBAC**
   - Are PIM eligible assignments created at subscription scope?
   - What permissions are required for this?
   - What happens if the service principal lacks Azure permissions?

### For Documentation Team:

1. **Target Audience**
   - Is this documentation for administrators or developers?
   - Should there be separate "Quick Start" vs. "Detailed Reference" docs?

2. **Configuration Examples**
   - Should there be more complete configuration examples?
   - Should EntraOpsConfig.json examples be provided?

---

## 6. Conclusion

### Current State: ⚠️ **NEEDS IMPROVEMENT**

The ServiceEM documentation provides a good foundation but has gaps that could confuse users:

**Strengths:**
- ✅ Good overview of governance models
- ✅ Clear naming conventions documented
- ✅ Comprehensive cmdlet reference

**Weaknesses:**
- ❌ Subscription-level capabilities not clearly explained
- ❌ Assignment policies not adequately documented
- ❌ Parameter impact not fully described
- ❌ Discrepancies between documented and actual behavior

### Recommended Actions:

1. **Immediate (High Priority):**
   - Clarify what subscription-level capabilities are implemented
   - Document assignment policies and their configuration
   - Explain the impact of `-SkipAzureResourceGroup`

2. **Short-term (Medium Priority):**
   - Add troubleshooting section
   - Create architecture diagrams
   - Document Azure RBAC integration

3. **Long-term (Low Priority):**
   - Separate quick start from detailed reference
   - Add more configuration examples
   - Create video walkthroughs

---

## Appendix: Test Evidence

### Objects Created in Test

**Sub Scope:**
- ✅ Sub-Test Members (Unified)
- ✅ SG-Sub-Test-CatalogPlane-Members
- ✅ SG-Sub-Test-ManagementPlane-Members
- ✅ SG-Sub-Test-ManagementPlane-Admins
- ✅ SG-Sub-Test-ControlPlane-Admins
- ✅ SG-PIM-Sub-Test-ManagementPlane-Admins
- ✅ Catalog-Sub-Test
- ✅ AP-Sub-Test-CatalogPlane-Members
- ✅ AP-Sub-Test-ManagementPlane-Members
- ⚠️ AP-Sub-Test-ManagementPlane-Admins (undocumented)

**Rg Scope:**
- ✅ Rg-Test Members (Unified)
- ✅ SG-Rg-Test-CatalogPlane-Members
- ✅ SG-Rg-Test-ManagementPlane-Members
- ❌ SG-Rg-Test-ManagementPlane-Admins (missing)
- ❌ SG-Rg-Test-WorkloadPlane-Members (missing)
- ✅ SG-Rg-Test-WorkloadPlane-Users
- ✅ SG-Rg-Test-WorkloadPlane-Admins
- ✅ Catalog-Rg-Test
- ✅ AP-Rg-Test-CatalogPlane-Members
- ✅ AP-Rg-Test-ManagementPlane-Members
- ❌ AP-Rg-Test-WorkloadPlane-Members (missing)
- ✅ AP-Rg-Test-WorkloadPlane-Users
- ✅ AP-Rg-Test-WorkloadPlane-Admins
- ❌ AP-Rg-Test-ManagementPlane-Admins (missing)

---

**Analysis Completed:** 2026-05-11  
**Status:** Documentation updates recommended  
**Priority:** High
