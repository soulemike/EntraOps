# ServiceEM Work Items - Updated Based on Test Run

**Date:** 2026-05-12  
**Test Run:** Test-5-12T0702  
**Status:** Updated with findings from second test

---

## Test Run Results Summary

### Deployment Command
```powershell
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "Test-5-12T0702" `
    -ServiceMembers @("AlexW@M365x60294116.OnMicrosoft.com") `
    -SkipAzureResourceGroup
```

### Results

| Component | Expected | Actual | Status |
|-----------|----------|--------|--------|
| **Sub Scope Groups** | 6 | 6 ✅ | **PASS** |
| **Sub Scope Access Packages** | 2 | 3 ⚠️ | **DISCREPANCY** |
| **Rg Scope Groups** | 7 | 5 ⚠️ | **2 MISSING** |
| **Rg Scope Access Packages** | 6 | 4 ⚠️ | **2 MISSING** |
| **Catalogs** | 2 | 2 ✅ | **PASS** |

### Detailed Findings

#### ✅ Successfully Created

**Sub Scope (6 groups, 3 access packages):**
- Sub-Test-5-12T0702 Members [Unified]
- SG-Sub-Test-5-12T0702-CatalogPlane-Members [Security]
- SG-Sub-Test-5-12T0702-ManagementPlane-Members [Security]
- SG-Sub-Test-5-12T0702-ManagementPlane-Admins [Security]
- SG-Sub-Test-5-12T0702-ControlPlane-Admins [Security]
- SG-PIM-Sub-Test-5-12T0702-ManagementPlane-Admins [Security]
- AP-Sub-Test-5-12T0702-CatalogPlane-Members
- AP-Sub-Test-5-12T0702-ManagementPlane-Members
- AP-Sub-Test-5-12T0702-ManagementPlane-Admins (⚠️ UNDOCUMENTED)

**Rg Scope (5 groups, 4 access packages):**
- Rg-Test-5-12T0702 Members [Unified]
- SG-Rg-Test-5-12T0702-CatalogPlane-Members [Security]
- SG-Rg-Test-5-12T0702-ManagementPlane-Members [Security]
- SG-Rg-Test-5-12T0702-WorkloadPlane-Users [Security]
- SG-Rg-Test-5-12T0702-WorkloadPlane-Admins [Security]
- AP-Rg-Test-5-12T0702-CatalogPlane-Members
- AP-Rg-Test-5-12T0702-ManagementPlane-Members
- AP-Rg-Test-5-12T0702-WorkloadPlane-Users
- AP-Rg-Test-5-12T0702-WorkloadPlane-Admins

#### ❌ Missing Objects

**Rg Scope Groups (2 missing):**
- SG-Rg-{Prefix}-ManagementPlane-Admins
- SG-Rg-{Prefix}-WorkloadPlane-Members

**Rg Scope Access Packages (2 missing):**
- AP-Rg-{Prefix}-WorkloadPlane-Members
- AP-Rg-{Prefix}-ManagementPlane-Admins

#### ⚠️ Issues Observed

1. **Assignment Policy Failures:** Consistent BadRequest errors on assignment policy creation
2. **Resource Request Failures:** BadRequest errors on catalog resource requests
3. **Undocumented Access Package:** AP-Sub-{Prefix}-ManagementPlane-Admins created but not documented
4. **Incomplete Rg Scope:** Pattern of missing ManagementPlane-Admins and WorkloadPlane-Members in Rg scope

---

## Updated Work Items

### 🔴 CRITICAL (Must Complete)

#### WORK-001: Document Subscription-Level Azure RBAC Implementation
**Priority:** CRITICAL  
**Status:** Pending  
**Effort:** 4-6 hours

**Findings from Test:**
- Sub scope groups created successfully
- PIM staging groups created (SG-PIM-Sub-*)
- Unclear what Azure RBAC assignments would be made without `-SkipAzureResourceGroup`

**Required Updates:**
- [ ] Document PIM staging groups (SG-PIM-Sub-*)
- [ ] Explain Azure RBAC at subscription scope
- [ ] Document when Azure resources are created
- [ ] Clarify `-SkipAzureResourceGroup` impact

---

#### WORK-002: Document Assignment Policy Configuration
**Priority:** CRITICAL  
**Status:** Pending  
**Effort:** 4-6 hours

**Findings from Test:**
- Consistent BadRequest errors on assignment policy creation
- 4 failures in Sub scope, 2 failures in Rg scope
- This is a recurring issue affecting functionality

**Required Updates:**
- [ ] Document assignment policy defaults
- [ ] Explain common failure scenarios
- [ ] Provide troubleshooting steps
- [ ] Add validation before policy creation

**New Finding:** Assignment policies are partially failing - this needs immediate attention.

---

#### WORK-003: Document Parameter Impact Matrix
**Priority:** CRITICAL  
**Status:** Pending  
**Effort:** 2-3 hours

**Findings from Test:**
- `-SkipAzureResourceGroup` clearly affects Rg scope completeness
- Missing: SG-Rg-*-ManagementPlane-Admins, SG-Rg-*-WorkloadPlane-Members
- Missing: AP-Rg-*-WorkloadPlane-Members, AP-Rg-*-ManagementPlane-Admins

**Required Updates:**
- [ ] Create impact matrix for all parameters
- [ ] Document that `-SkipAzureResourceGroup` causes incomplete Rg scope
- [ ] Explain which objects are skipped and why
- [ ] Provide guidance on when to use each parameter

**New Finding:** `-SkipAzureResourceGroup` causes 2 groups and 2 access packages to be skipped in Rg scope.

---

#### WORK-010: Investigate Rg Scope Creation Logic
**Priority:** CRITICAL  
**Status:** Pending  
**Effort:** 4-8 hours

**Findings from Test:**
- **CONFIRMED:** Rg scope consistently missing 2 groups and 2 access packages
- Missing groups: ManagementPlane-Admins, WorkloadPlane-Members
- Missing access packages: WorkloadPlane-Members, ManagementPlane-Admins
- Pattern is consistent across test runs

**Root Cause Hypothesis:**
1. `-SkipAzureResourceGroup` intentionally skips these objects
2. Code logic has conditional creation that's not documented
3. ServiceRoles configuration differs between Sub and Rg scope

**Required Actions:**
- [ ] Review `New-EntraOpsServiceBootstrap.ps1` ServiceRoles configuration
- [ ] Trace Rg scope execution with Verbose logging
- [ ] Determine if behavior is intentional or bug
- [ ] Document findings or fix code

**Test Evidence:**
```
Rg Scope Expected: 7 groups
Rg Scope Actual:   5 groups
Missing: SG-Rg-*-ManagementPlane-Admins, SG-Rg-*-WorkloadPlane-Members

Rg Scope Expected: 6 access packages
Rg Scope Actual:   4 access packages
Missing: AP-Rg-*-WorkloadPlane-Members, AP-Rg-*-ManagementPlane-Admins
```

---

#### WORK-011: Document or Remove Undocumented Access Package
**Priority:** CRITICAL  
**Status:** Pending  
**Effort:** 1-2 hours

**Findings from Test:**
- **CONFIRMED:** AP-Sub-Test-5-12T0702-ManagementPlane-Admins was created
- This is consistent across test runs (also seen with "Test" prefix)
- Documentation only lists 2 Sub scope access packages

**Required Actions:**
- [ ] Clarify if this access package is intentional
- [ ] Document creation conditions
- [ ] Update "Access Packages Created" section
- [ ] OR: Remove from code if not intentional

**Test Evidence:**
```
Documented Sub Scope Access Packages:
  - AP-Sub-{Prefix}-CatalogPlane-Members
  - AP-Sub-{Prefix}-ManagementPlane-Members

Actual Sub Scope Access Packages (Test-5-12T0702):
  - AP-Sub-Test-5-12T0702-CatalogPlane-Members
  - AP-Sub-Test-5-12T0702-ManagementPlane-Members
  - AP-Sub-Test-5-12T0702-ManagementPlane-Admins  ⚠️ UNDOCUMENTED
```

---

### 🟡 HIGH (Should Complete)

#### WORK-004: Add Troubleshooting Section
**Priority:** HIGH  
**Status:** Pending  
**Effort:** 3-4 hours

**Findings from Test:**
- Assignment policy BadRequest errors are consistent
- Resource request BadRequest errors observed
- Need documented workarounds

**Required Content:**
- [ ] Assignment policy BadRequest troubleshooting
- [ ] Resource request failure troubleshooting
- [ ] Incomplete Rg scope explanation
- [ ] Service principal permission issues

**New Issues to Document:**
1. `Failed to execute .../assignmentPolicies - BadRequest`
2. `Failed to execute .../resourceRequests - BadRequest`
3. Incomplete Rg scope with `-SkipAzureResourceGroup`

---

#### WORK-005: Update Access Package Documentation
**Priority:** HIGH  
**Status:** Pending  
**Effort:** 2 hours

**Findings from Test:**
- Sub scope: 3 access packages (not 2)
- Rg scope: 4 access packages (not 6 when using -SkipAzureResourceGroup)

**Required Updates:**
- [ ] Update Sub scope count from 2 to 3
- [ ] Add AP-Sub-{Prefix}-ManagementPlane-Admins
- [ ] Document conditional Rg scope creation
- [ ] Explain when access packages are skipped

---

### 🟢 MEDIUM (Nice to Have)

#### WORK-012: Investigate Assignment Policy BadRequest Errors
**Priority:** MEDIUM  
**Status:** Pending  
**Effort:** 4-6 hours

**Findings from Test:**
- 6 BadRequest errors total (4 Sub + 2 Rg)
- Errors are consistent across test runs
- Some assignment policies may be partially created

**Required Actions:**
- [ ] Capture full error response
- [ ] Identify which specific policies fail
- [ ] Determine root cause (approvers? scope?)
- [ ] Implement fix or workaround

---

#### WORK-006: Create Architecture Diagrams
**Priority:** MEDIUM  
**Status:** Pending  
**Effort:** 8-12 hours

**Purpose:** Visual documentation of object relationships

---

#### WORK-007: Add Quick Start Guide
**Priority:** MEDIUM  
**Status:** Pending  
**Effort:** 4-6 hours

**Purpose:** Simplified onboarding for new users

---

#### WORK-013: Add Pre-Flight Validation
**Priority:** MEDIUM  
**Status:** Pending  
**Effort:** 6-10 hours

**Purpose:** Catch issues before deployment

---

### 🔵 LOW (Future Enhancement)

#### WORK-008: Document Configuration File Options
**Priority:** LOW  
**Status:** Pending  
**Effort:** 2-3 hours

---

#### WORK-009: Add Video Walkthrough Links
**Priority:** LOW  
**Status:** Pending  
**Effort:** 1 hour

---

#### WORK-014: Create Comprehensive Test Suite
**Priority:** LOW  
**Status:** Pending  
**Effort:** 16-24 hours

---

#### WORK-015: Create Validation Report Template
**Priority:** LOW  
**Status:** Pending  
**Effort:** 2-3 hours

---

## Updated Prioritization Matrix

| Work Item | Priority | Effort | Impact | Test Finding |
|-----------|----------|--------|--------|--------------|
| WORK-010: Rg Scope Logic | 🔴 Critical | Medium | High | **CONFIRMED** - 2 groups + 2 AP missing |
| WORK-011: Undocumented AP | 🔴 Critical | Small | Medium | **CONFIRMED** - AP-Sub-*-ManagementPlane-Admins created |
| WORK-003: Parameter Impact | 🔴 Critical | Small | High | **CONFIRMED** - -SkipAzureResourceGroup causes incomplete Rg scope |
| WORK-002: Assignment Policies | 🔴 Critical | Medium | High | **CONFIRMED** - BadRequest errors recurring |
| WORK-001: Subscription RBAC | 🔴 Critical | Medium | High | PIM staging groups need documentation |
| WORK-004: Troubleshooting | 🟡 High | Medium | Medium | BadRequest errors need documented workarounds |
| WORK-005: Access Package Docs | 🟡 High | Small | Medium | Count discrepancies confirmed |
| WORK-012: BadRequest Investigation | 🟢 Medium | Medium | Medium | Root cause needed |
| Others | 🟢/🔵 Low | Various | Low | Nice to have |

---

## Key Insights from Test Run

### 1. Consistent Behavior
The test with "Test-5-12T0702" shows **identical patterns** to the previous "Test" deployment:
- Same missing objects in Rg scope
- Same undocumented access package created
- Same BadRequest errors on assignment policies

**Conclusion:** These are systematic behaviors, not one-off issues.

### 2. Impact of `-SkipAzureResourceGroup`
**CONFIRMED:** This parameter causes incomplete Rg scope:
- Missing: SG-Rg-*-ManagementPlane-Admins, SG-Rg-*-WorkloadPlane-Members
- Missing: AP-Rg-*-WorkloadPlane-Members, AP-Rg-*-ManagementPlane-Admins

**Recommendation:** Document this behavior clearly or fix if unintentional.

### 3. Assignment Policy Failures
**CONFIRMED:** Recurring issue across test runs:
- 6 BadRequest errors per deployment
- Affects both Sub and Rg scopes
- Needs investigation and resolution

### 4. Documentation Gaps
**CONFIRMED:** Multiple discrepancies:
- Access package count incorrect (3 vs 2 in Sub scope)
- Rg scope groups incomplete (5 vs 7)
- PIM staging groups not documented
- Assignment policies not explained

---

## Recommended Implementation Order

### Phase 1: Critical Fixes (Week 1)
1. **WORK-010:** Investigate Rg scope logic - Determine if behavior is intentional
2. **WORK-011:** Clarify undocumented access package - Add to docs or remove
3. **WORK-003:** Document parameter impact - Explain -SkipAzureResourceGroup effects

### Phase 2: Critical Documentation (Week 2)
4. **WORK-002:** Document assignment policies - Explain defaults and failures
5. **WORK-001:** Document subscription RBAC - Explain PIM staging and Azure integration
6. **WORK-004:** Add troubleshooting - Document known issues and workarounds

### Phase 3: Documentation Updates (Week 3)
7. **WORK-005:** Update access package counts - Align docs with actual behavior
8. **WORK-012:** Investigate BadRequest errors - Root cause analysis
9. **WORK-006:** Create architecture diagrams - Visual documentation

### Phase 4: Enhancements (Week 4)
10. Remaining work items (Quick Start, Pre-flight validation, etc.)

---

## Success Criteria Updated

ServiceEM will be considered **comprehensive and aligned** when:

1. ✅ **Rg scope completeness resolved** - Either documented as intentional or fixed
2. ✅ **Undocumented access package explained** - Added to docs or removed from code
3. ✅ **Parameter impact documented** - Users understand what objects will be created
4. ✅ **Assignment policy failures addressed** - Either fixed or documented with workarounds
5. ✅ **Subscription RBAC explained** - PIM staging and Azure integration clear
6. ✅ **Troubleshooting guide available** - Common issues have documented resolutions
7. ✅ **Access package counts accurate** - Documentation matches actual behavior
8. ✅ **No undocumented objects created** - All created objects are documented

---

**Total Estimated Effort:** 60-80 hours (reduced from 80-120 based on findings)  
**Recommended Team:** 1 Developer + 1 Technical Writer  
**Timeline:** 4 weeks (part-time) or 2 weeks (full-time)  
**Updated:** 2026-05-12 based on Test-5-12T0702 results
