# ServiceEM Work Items - Comprehensive Alignment Plan

**Date:** 2026-05-11  
**Status:** Based on Gap Analysis Findings  
**Goal:** Achieve comprehensive documentation alignment and production readiness

---

## Executive Summary

Based on the gap analysis, **15 work items** have been identified across three categories:

| Category | Count | Priority |
|----------|-------|----------|
| Documentation Updates | 9 | High |
| Code Verification/Fixes | 4 | Medium |
| Testing/Validation | 2 | Medium |

**Critical Finding:** The documentation does not adequately explain subscription-level capabilities or assignment policy configuration, which could lead to misconfigured production deployments.

---

## Category 1: Documentation Updates (9 Work Items)

### 🔴 WORK-001: Document Subscription-Level Azure RBAC Implementation

**Priority:** HIGH  
**Effort:** Medium (4-6 hours)  
**Owner:** Documentation Team

**Description:**
Add comprehensive documentation explaining what Azure RBAC assignments are made at the subscription level and how they relate to Sub scope groups.

**Current Gap:**
Documentation states "subscription-level groups, catalog, access packages, PIM policies" but doesn't explain:
- PIM eligible assignments for ControlPlane-Admins (User Access Administrator)
- PIM eligible assignments for ManagementPlane-Admins (Contributor)
- Azure resource requirements
- Permission prerequisites

**Proposed Content:**
```markdown
### Subscription-Level Azure RBAC

ServiceEM implements the following Azure RBAC assignments at subscription scope:

**PIM Eligible Assignments:**
- ControlPlane-Admins → User Access Administrator (Subscription)
- ManagementPlane-Admins → Contributor (Subscription)

**Prerequisites:**
- Service principal must have `RoleManagement.ReadWrite.Directory`
- Service principal must have Azure RBAC permissions at subscription scope
- Subscription must be specified or default subscription used

**Important:** These assignments are only created when:
1. `-SkipAzureResourceGroup` is NOT used
2. Service principal has sufficient Azure permissions
3. Azure subscription is accessible
```

**Acceptance Criteria:**
- [ ] Section added to ServiceEM.md
- [ ] Prerequisites clearly listed
- [ ] Permission requirements documented
- [ ] Troubleshooting for permission failures added

---

### 🔴 WORK-002: Document Assignment Policy Configuration

**Priority:** HIGH  
**Effort:** Medium (4-6 hours)  
**Owner:** Documentation Team

**Description:**
Add detailed documentation about assignment policies, their default configurations, and guidance for customization.

**Current Gap:**
Access packages are documented but assignment policies (who can request, who approves, expiration) are not explained.

**Proposed Content:**
```markdown
### Assignment Policies

Each access package has an assignment policy that controls:

**Default Configuration:**
| Setting | Default Value | Description |
|---------|--------------|-------------|
| allowedTargetScope | specificDirectoryUsers | Only specific users can request |
| Approvers | Tier-specific admins | ManagementPlane-Admins, etc. |
| Expiration | 5 days | Access expires after 5 days |
| Access Reviews | Not configured | Optional - must be added manually |

**Post-Deployment Actions:**
1. Review assignment policies in Azure Portal
2. Customize approver groups if needed
3. Adjust expiration settings per organizational requirements
4. Configure access reviews for compliance

**PowerShell Commands:**
```powershell
# Get all policies for an access package
Get-MgEntitlementManagementAssignmentPolicy `
    -AccessPackageId $accessPackageId

# Update policy
Update-MgEntitlementManagementAssignmentPolicy `
    -AccessPackageAssignmentPolicyId $policyId `
    -RequestApprovalSettings $newSettings
```
```

**Acceptance Criteria:**
- [ ] Assignment policy section added
- [ ] Default settings documented in table format
- [ ] Post-deployment checklist provided
- [ ] PowerShell examples included

---

### 🔴 WORK-003: Document Parameter Impact Matrix

**Priority:** HIGH  
**Effort:** Small (2-3 hours)  
**Owner:** Documentation Team

**Description:**
Create a comprehensive matrix showing how each parameter affects object creation.

**Current Gap:**
Parameters are documented individually but their interactions and impacts are not clear.

**Proposed Content:**
```markdown
### Parameter Impact Matrix

| Parameter | Sub Scope Groups | Rg Scope Groups | Azure Resources | Access Packages |
|-----------|-----------------|-----------------|-----------------|-----------------|
| -SkipAzureResourceGroup | ✅ Created | ⚠️ Partial | ❌ Skipped | ⚠️ Partial |
| -ServiceOwner | ✅ Owned | ✅ Owned | N/A | ✅ Approver |
| -ServiceMembers | ✅ Assigned | ✅ Assigned | N/A | ✅ Requestors |
| -GovernanceModel Centralized | ⚠️ Delegated | ⚠️ Delegated | N/A | ⚠️ Reduced |
| -ProhibitDirectElevation | ✅ No PIM staging | ✅ No PIM staging | N/A | N/A |

**Notes:**
- `-SkipAzureResourceGroup` may cause incomplete Rg scope
- Without `-ServiceOwner`, groups may have no owner
```

**Acceptance Criteria:**
- [ ] Impact matrix created
- [ ] All major parameters covered
- [ ] Visual indicator system (✅/⚠️/❌) used
- [ ] Notes/exceptions documented

---

### 🟡 WORK-004: Add Troubleshooting Section

**Priority:** MEDIUM  
**Effort:** Medium (3-4 hours)  
**Owner:** Documentation Team

**Description:**
Add a comprehensive troubleshooting section covering common issues and resolutions.

**Issues to Document:**
1. Assignment policy BadRequest errors
2. Incomplete Rg scope creation
3. Service principal permission issues
4. Graph API replication delays
5. User lookup failures

**Proposed Content:**
```markdown
## Troubleshooting

### Issue: Assignment Policy Creation Fails

**Symptom:**
```
WARNING: Failed to execute .../assignmentPolicies
Error: Response status code does not indicate success: BadRequest
```

**Causes:**
1. Invalid approver group references
2. Missing ServiceOwner
3. Graph replication delay

**Resolution:**
1. Verify ServiceOwner parameter is valid user
2. Wait 5-10 minutes for group replication
3. Check that all referenced groups exist
4. Retry deployment

### Issue: Incomplete Rg Scope

**Symptom:** Rg scope missing groups or access packages

**Cause:** Using `-SkipAzureResourceGroup`

**Resolution:** Remove `-SkipAzureResourceGroup` for full deployment
```

**Acceptance Criteria:**
- [ ] Common issues documented
- [ ] Symptoms clearly described
- [ ] Root causes explained
- [ ] Step-by-step resolutions provided

---

### 🟡 WORK-005: Update Access Package Documentation

**Priority:** MEDIUM  
**Effort:** Small (2 hours)  
**Owner:** Documentation Team

**Description:**
Update the "Access Packages Created" section to reflect actual behavior, including the undocumented ManagementPlane-Admins access package.

**Changes Needed:**
1. Add AP-Sub-{Prefix}-ManagementPlane-Admins to Sub Scope table
2. Clarify conditions under which each access package is created
3. Add note about undocumented access package

**Acceptance Criteria:**
- [ ] Sub Scope access package count updated (3 instead of 2)
- [ ] ManagementPlane-Admins access package documented
- [ ] Conditional creation logic explained

---

### 🟡 WORK-006: Create Architecture Diagrams

**Priority:** MEDIUM  
**Effort:** Large (8-12 hours)  
**Owner:** Documentation Team / Technical Illustrator

**Description:**
Create visual diagrams showing:
1. Sub scope vs. Rg scope architecture
2. Azure RBAC assignment flow
3. PIM relationships
4. Access package request flow
5. Centralized vs. PerService comparison

**Diagrams Needed:**
- High-level architecture overview
- Object relationship diagram
- Request/approval workflow
- Azure RBAC assignment visualization

**Acceptance Criteria:**
- [ ] Mermaid diagrams created (for markdown compatibility)
- [ ] PNG/SVG exports for presentations
- [ ] All scopes and relationships shown
- [ ] Legend/explanation included

---

### 🟡 WORK-007: Add Quick Start Guide

**Priority:** MEDIUM  
**Effort:** Medium (4-6 hours)  
**Owner:** Documentation Team

**Description:**
Create a separate quick start guide for new users, distinct from the comprehensive reference.

**Content:**
1. Prerequisites checklist
2. Minimal working example
3. Verification steps
4. Next steps / customization guide

**Acceptance Criteria:**
- [ ] QuickStart.md created
- [ ] Prerequisites checklist format
- [ ] Copy-paste ready examples
- [ ] Common pitfalls highlighted

---

### 🟢 WORK-008: Document Configuration File Options

**Priority:** LOW  
**Effort:** Small (2-3 hours)  
**Owner:** Documentation Team

**Description:**
Expand EntraOpsConfig.json documentation with all available options and examples.

**Content:**
- Complete configuration schema
- Example configurations for common scenarios
- Parameter descriptions
- Default values

**Acceptance Criteria:**
- [ ] JSON schema documented
- [ ] 3+ example configurations provided
- [ ] All parameters described

---

### 🟢 WORK-009: Add Video Walkthrough Links

**Priority:** LOW  
**Effort:** Small (1 hour)  
**Owner:** Documentation Team / DevRel

**Description:**
Add links to video walkthroughs or create placeholder for future videos.

**Content:**
- Quick start video
- Architecture deep dive
- Troubleshooting guide

**Acceptance Criteria:**
- [ ] Video section added to README
- [ ] Placeholder links or actual video links
- [ ] Brief description of each video

---

## Category 2: Code Verification/Fixes (4 Work Items)

### 🔴 WORK-010: Verify Rg Scope Creation Logic

**Priority:** HIGH  
**Effort:** Medium (4-8 hours)  
**Owner:** Development Team

**Description:**
Investigate why Rg scope was incomplete (missing 3 groups, 2 access packages) and determine if this is expected behavior with `-SkipAzureResourceGroup` or a bug.

**Questions to Answer:**
1. Does `-SkipAzureResourceGroup` intentionally skip some Entra ID objects?
2. Why were ManagementPlane-Members, ManagementPlane-Admins, and WorkloadPlane-Members not created?
3. Is the code logic correct for PerService model?

**Investigation Steps:**
1. Review `New-EntraOpsSubscriptionLandingZone.ps1` Rg scope logic
2. Check `New-EntraOpsServiceBootstrap.ps1` for ServiceRoles configuration
3. Trace execution with `-Verbose` to identify decision points
4. Compare Centralized vs. PerService code paths

**Acceptance Criteria:**
- [ ] Root cause identified
- [ ] Behavior documented (expected vs. bug)
- [ ] If bug: fix implemented and tested
- [ ] If expected: documented in WORK-003

---

### 🟡 WORK-011: Document or Remove Undocumented Access Package

**Priority:** MEDIUM  
**Effort:** Small (1-2 hours)  
**Owner:** Development Team

**Description:**
Clarify the purpose of `AP-Sub-{Prefix}-ManagementPlane-Admins` access package which was created but is not in documentation.

**Questions to Answer:**
1. Is this access package intentionally created?
2. Under what conditions is it created?
3. Should it be documented or removed?

**Acceptance Criteria:**
- [ ] Purpose clarified
- [ ] Creation conditions documented
- [ ] Either added to docs (WORK-005) or removed from code

---

### 🟡 WORK-012: Investigate Assignment Policy BadRequest Errors

**Priority:** MEDIUM  
**Effort:** Medium (4-6 hours)  
**Owner:** Development Team

**Description:**
Investigate and resolve (or document) the BadRequest errors during assignment policy creation.

**Error Pattern:**
```
WARNING: Failed to execute .../assignmentPolicies
Error: Response status code does not indicate success: BadRequest
```

**Investigation Steps:**
1. Capture full error response body
2. Identify which policies fail and why
3. Check if approver groups exist
4. Verify ServiceOwner is valid

**Potential Fixes:**
- Add validation before policy creation
- Implement retry logic
- Better error messages
- Pre-flight checks

**Acceptance Criteria:**
- [ ] Root cause identified
- [ ] Fix implemented OR documented workaround
- [ ] Better error messages added

---

### 🟢 WORK-013: Add Pre-Flight Validation

**Priority:** LOW  
**Effort:** Medium (6-10 hours)  
**Owner:** Development Team

**Description:**
Add pre-flight validation to check prerequisites before deployment begins.

**Validations to Add:**
1. Service principal permissions check
2. ServiceOwner exists and is valid
3. ServiceMembers exist
4. Azure subscription access (if not skipping)
5. Graph API connectivity

**Example:**
```powershell
Test-EntraOpsServiceEMPrerequisites `
    -ServiceOwner $ServiceOwner `
    -ServiceMembers $ServiceMembers `
    -AzureRegion $AzureRegion
```

**Acceptance Criteria:**
- [ ] Validation function created
- [ ] All critical prerequisites checked
- [ ] Clear error messages for failures
- [ ] Optional: -WhatIf parameter support

---

## Category 3: Testing/Validation (2 Work Items)

### 🟡 WORK-014: Create Comprehensive Test Suite

**Priority:** MEDIUM  
**Effort:** Large (16-24 hours)  
**Owner:** QA/Development Team

**Description:**
Create a comprehensive test suite that validates all documented behavior.

**Test Scenarios:**
1. PerService model - Full deployment
2. PerService model - SkipAzureResourceGroup
3. Centralized model - Full deployment
4. Centralized model - With delegation groups
5. Error conditions (missing permissions, invalid users)
6. Parameter combinations

**Test Types:**
- Unit tests for individual functions
- Integration tests for full deployment
- Validation tests for created objects
- Cleanup tests

**Acceptance Criteria:**
- [ ] Test script created
- [ ] All scenarios covered
- [ ] Object validation logic implemented
- [ ] Test results report generated

---

### 🟢 WORK-015: Create Validation Report Template

**Priority:** LOW  
**Effort:** Small (2-3 hours)  
**Owner:** Documentation Team

**Description:**
Create a standardized validation report template for users to verify their deployments.

**Template Sections:**
1. Deployment parameters used
2. Expected vs. actual objects
3. Configuration verification
4. Issues encountered
5. Remediation steps

**Acceptance Criteria:**
- [ ] Markdown template created
- [ ] Example completed report provided
- [ ] Instructions for use included

---

## Work Item Prioritization Matrix

| Work Item | Priority | Effort | Impact | Recommended Order |
|-----------|----------|--------|--------|-------------------|
| WORK-001: Subscription RBAC | 🔴 High | Medium | High | 1 |
| WORK-002: Assignment Policies | 🔴 High | Medium | High | 2 |
| WORK-003: Parameter Impact | 🔴 High | Small | High | 3 |
| WORK-010: Rg Scope Logic | 🔴 High | Medium | High | 4 |
| WORK-004: Troubleshooting | 🟡 Medium | Medium | Medium | 5 |
| WORK-005: Access Package Docs | 🟡 Medium | Small | Medium | 6 |
| WORK-014: Test Suite | 🟡 Medium | Large | High | 7 |
| WORK-006: Architecture Diagrams | 🟡 Medium | Large | Medium | 8 |
| WORK-011: Undocumented AP | 🟡 Medium | Small | Low | 9 |
| WORK-012: BadRequest Errors | 🟡 Medium | Medium | Medium | 10 |
| WORK-007: Quick Start | 🟡 Medium | Medium | Medium | 11 |
| WORK-013: Pre-Flight Validation | 🟢 Low | Medium | Medium | 12 |
| WORK-008: Config File Docs | 🟢 Low | Small | Low | 13 |
| WORK-009: Video Links | 🟢 Low | Small | Low | 14 |
| WORK-015: Validation Template | 🟢 Low | Small | Low | 15 |

---

## Implementation Roadmap

### Phase 1: Critical Documentation (Weeks 1-2)
- WORK-001: Subscription RBAC documentation
- WORK-002: Assignment policies documentation
- WORK-003: Parameter impact matrix
- WORK-010: Rg scope logic investigation

### Phase 2: User Experience (Weeks 3-4)
- WORK-004: Troubleshooting section
- WORK-005: Access package documentation update
- WORK-007: Quick start guide
- WORK-011: Undocumented access package clarification

### Phase 3: Quality Assurance (Weeks 5-6)
- WORK-014: Comprehensive test suite
- WORK-012: BadRequest error investigation
- WORK-006: Architecture diagrams

### Phase 4: Enhancement (Weeks 7-8)
- WORK-013: Pre-flight validation
- WORK-008: Configuration file documentation
- WORK-009: Video walkthroughs
- WORK-015: Validation report template

---

## Success Criteria

The ServiceEM documentation and implementation will be considered **comprehensive and aligned** when:

1. ✅ All documented objects match actual behavior
2. ✅ Subscription-level capabilities are fully explained
3. ✅ Assignment policies are documented with customization guidance
4. ✅ Parameter impacts are clearly described
5. ✅ Troubleshooting guide resolves common issues
6. ✅ Test suite validates all documented behavior
7. ✅ No undocumented objects are created
8. ✅ Users can successfully deploy without guessing

---

**Total Estimated Effort:** 80-120 hours  
**Recommended Team:** 1 Developer + 1 Technical Writer  
**Timeline:** 8 weeks (part-time) or 4 weeks (full-time)
