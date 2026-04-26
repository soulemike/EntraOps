# ServiceEM (feature-ElmLz) Backlog Work Plan

## Overview

This work plan addresses five critical issues identified in the feature-ElmLz branch related to the ServiceEM (Service Enterprise Access Model) functionality. The issues span documentation gaps, configuration handling problems, API payload issues, and parameter inconsistencies.

> **⚠️ IMPORTANT CONTEXT**: This work plan is for the `feature-ElmLz` branch, which contains new ServiceEM functionality not yet in main. The functions `New-EntraOpsSubscriptionLandingZone`, `New-EntraOpsServiceEntraGroup`, and `Resolve-EntraOpsServiceEMDelegationGroup` exist only in this branch.

---

## Issue Summary

| Issue | Description | Severity |
|-------|-------------|----------|
| 1 | Simple deployment with defaults assumes specific named groups exist | High |
| 2 | Skip*PlaneDelegation switches don't change behavior as expected | Medium |
| 3 | Specific group objects in EntraOpsConfig.json are not used | High |
| 4 | New-EntraOpsServiceEntraGroup API payload fails | Critical |
| 5 | GovernanceModel property documented but doesn't exist as parameter | Medium |

---

## Critical Fixes Required (Pre-Implementation)

### Issue 1.0: Change Default Governance Model
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`  
**Priority:** Critical  
**Effort:** 1 hour

**Problem:** The current default governance model is `Centralized`, which requires pre-existing delegation groups. This breaks the "simple deployment" experience.

**Work Items:**
- [ ] Change default governance model from `Centralized` to `PerService`
- [ ] PerService model creates its own groups and works without prerequisites
- [ ] Centralized model should be opt-in for organizations with established operations teams
- [ ] Update all documentation examples to reflect PerService as default
- [ ] Add verbose logging indicating which governance model is being used and why

---

### Issue 3.0: Add Config File Loading Mechanism
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`  
**Priority:** Critical  
**Effort:** 2 hours

**Problem:** The code references `$Global:EntraOpsConfig` but never loads the config file from disk. If the global variable is null, config values are never used.

**Work Items:**
- [ ] Add config loading to `begin` block before any config-dependent logic
- [ ] Search for `EntraOpsConfig.json` in:
  - `$PWD/EntraOpsConfig.json` (current directory)
  - `$PSScriptRoot/EntraOpsConfig.json` (script directory)
  - `$env:ENTRAOPS_CONFIG` (environment variable override)
- [ ] If config file found but not loaded, load it into `$Global:EntraOpsConfig`
- [ ] If config file not found and required values are missing, provide clear error:
  ```
  EntraOpsConfig.json not found. Run New-EntraOpsConfigFile to create one,
  or specify all required parameters explicitly.
  ```
- [ ] Add verbose logging showing config file path and which values were loaded

---

### Issue 4.0: Verify Actual API Failure Cause
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsServiceEntraGroup.ps1`  
**Priority:** Critical (MUST complete before Issue 4.1)  
**Effort:** 2 hours

**Problem:** The root cause analysis in the original work plan incorrectly identified JSON property casing (PascalCase vs camelCase) as the issue. **The actual code already uses camelCase.** The real cause needs investigation.

**Work Items:**
- [ ] Test actual API call with current feature-ElmLz code
- [ ] Capture exact error message from Microsoft Graph API
- [ ] Verify whether the issue is:
  - Invalid `owners@odata.bind` format (most likely)
  - Missing required fields for Unified groups
  - mailNickname uniqueness constraints
  - Other Graph API validation failures
- [ ] Document actual root cause before implementing fix
- [ ] If casing is NOT the issue, update all downstream work items (4.1-4.5) accordingly

**Verification Command:**
```powershell
# Test with verbose logging to capture actual API error
New-EntraOpsServiceEntraGroup `
    -ServiceName "TestService" `
    -ServiceOwner "https://graph.microsoft.com/v1.0/users/{object-id}" `
    -ServiceRoles $roles `
    -Verbose
```

---

## Detailed Work Items

### Issue 1: Simple Deployment Assumes Pre-existing Groups

**Problem Statement:**
The documentation shows a "simple deployment" example that doesn't mention prerequisites, but the code defaults to `GovernanceModel = "Centralized"` which requires pre-existing delegation groups (`PRG-Tenant-ControlPlane-IdentityOps` and `PRG-Tenant-ManagementPlane-PlatformOps`). When these don't exist, the function either fails or attempts to create them (requiring elevated permissions).

**Root Cause Analysis:**
- `New-EntraOpsSubscriptionLandingZone` defaults to Centralized governance model
- `Resolve-EntraOpsServiceEMDelegationGroup` is called which looks for groups by name
- If not found, it attempts auto-creation requiring `RoleManagement.ReadWrite.Directory`
- No clear error message guides users to create groups manually or switch to PerService model

**Work Items:**

#### 1.1 Update Documentation Prerequisites
**File:** `ServiceEM.md`  
**Priority:** High  
**Effort:** 1 hour

- [ ] Add explicit prerequisites section before "Basic Landing Zone Deployment"
- [ ] Document that Centralized model requires pre-existing groups
- [ ] List the default group names that will be searched/created
- [ ] Document required permissions for auto-creation vs. manual creation
- [ ] Add decision tree: When to use Centralized vs PerService model

#### 1.2 Improve Error Handling and User Guidance
**File:** `EntraOps/Private/Resolve-EntraOpsServiceEMDelegationGroup.ps1`  
**Priority:** High  
**Effort:** 2 hours

- [ ] Enhance error messages to clearly state which group was not found
- [ ] Provide actionable next steps in error messages:
  - Option A: Create the group manually with specific settings
  - Option B: Switch to PerService governance model (add `-GovernanceModel "PerService"` once parameter exists)
  - Option C: Run with appropriate permissions for auto-creation
- [ ] Add link to documentation in error messages

#### 1.3 Add Governance Model Validation
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`  
**Priority:** Medium  
**Effort:** 2 hours

- [ ] Add validation in `begin` block to check if required groups exist before processing
- [ ] Provide early failure with clear message rather than failing mid-execution
- [ ] Add `-WhatIf` support to preview what would be created/used

#### 1.4 Create Quick Start for PerService Model
**File:** `ServiceEM.md`  
**Priority:** Medium  
**Effort:** 1 hour

- [ ] Add "Quick Start - PerService Model (No Pre-existing Groups Required)" section
- [ ] Show example with explicit governance model (once parameter is implemented)
- [ ] Explain trade-offs between Centralized and PerService models

#### 1.5 Add Graceful Fallback to PerService Model
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`  
**Priority:** High  
**Effort:** 2 hours

- [ ] When GovernanceModel=Centralized and delegation groups don't exist
- [ ] Log clear warning: "Centralized delegation groups not found, falling back to PerService model"
- [ ] Auto-switch to PerService model instead of failing
- [ ] Document this behavior in both code comments and user documentation
- [ ] Add verbose logging showing the fallback decision

---

### Issue 2: Skip*PlaneDelegation Switches Not Working

**Problem Statement:**
The switches `-SkipControlPlaneDelegation` and `-SkipManagementPlaneDelegation` don't seem to change behavior. Users expect these to explicitly skip delegation, but the auto-detection logic may be overriding them.

**Root Cause Analysis:**
- In `New-EntraOpsSubscriptionLandingZone`, the switches are auto-set when delegation Group IDs are provided:
  ```powershell
  if (-not [string]::IsNullOrWhiteSpace($ControlPlaneDelegationGroupId)) {
      $SkipControlPlaneDelegation = $true
  }
  ```
- In `New-EntraOpsServiceBootstrap`, similar auto-setting occurs
- The switches work correctly when NO delegation Group IDs are provided, but the interaction is confusing

**Work Items:**

#### 2.1 Clarify Switch Behavior in Documentation
**File:** `ServiceEM.md`  
**Priority:** Medium  
**Effort:** 1 hour

- [ ] Document that these switches are auto-applied when delegation Group IDs are provided
- [ ] Explain the hierarchy: Explicit Group ID > Switch > Default behavior
- [ ] Add examples showing when switches are needed vs. when they're auto-applied

#### 2.2 Add Verbose Logging for Switch State
**Files:**
- `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`
- `EntraOps/Public/ServiceEM/New-EntraOpsServiceBootstrap.ps1`  
**Priority:** Medium  
**Effort:** 1 hour

- [ ] Add verbose logging showing the final state of skip flags after all logic
- [ ] Log when switches are auto-set due to Group ID presence
- [ ] Log when switches are explicitly set by user

#### 2.3 Consider Switch Renaming or Deprecation
**Priority:** Low  
**Effort:** Discussion needed

- [ ] Evaluate if switches should be renamed to `-ForceSkipControlPlaneDelegation` for clarity
- [ ] OR evaluate if switches should be deprecated in favor of explicit Group ID parameters only
- [ ] Document decision and migration path

---

### Issue 3: Config File Group Objects Not Used

**Problem Statement:**
When specific group objects are specified in `EntraOpsConfig.json`, they are not used. The function still attempts to use the specific named objects or defaults.

**Root Cause Analysis:**
- `New-EntraOpsSubscriptionLandingZone` reads from `$Global:EntraOpsConfig.ServiceEM.*`
- However, the config might not be loaded into the global variable (see Issue 3.0)
- The fallback logic may be overwriting user-specified values
- Looking at the code:
  ```powershell
  if ([string]::IsNullOrWhiteSpace($ControlPlaneDelegationGroupId) -and
      $null -ne $Global:EntraOpsConfig -and
      $Global:EntraOpsConfig.ContainsKey('ServiceEM') -and
      -not [string]::IsNullOrWhiteSpace($Global:EntraOpsConfig.ServiceEM.ControlPlaneDelegationGroupId)) {
      $ControlPlaneDelegationGroupId = $Global:EntraOpsConfig.ServiceEM.ControlPlaneDelegationGroupId
  }
  ```
- The issue may be that `$Global:EntraOpsConfig` is null or doesn't contain the ServiceEM key

**Work Items:**

#### 3.1 Add Config Loading Verification
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`  
**Priority:** High  
**Effort:** 2 hours

- [ ] Add check at start of function to verify `$Global:EntraOpsConfig` is loaded
- [ ] If not loaded, attempt to load from default location (`$PWD/EntraOpsConfig.json`)
- [ ] Provide clear error if config cannot be loaded and is required
- [ ] Add verbose logging showing which config values are being used

#### 3.2 Fix Config Value Precedence Logic
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`  
**Priority:** High  
**Effort:** 3 hours

- [ ] Review and fix precedence: Parameter > Config > Default
- [ ] Ensure user-specified config values are not overwritten by defaults
- [ ] Add unit tests for config precedence scenarios
- [ ] Test scenarios:
  - Parameter provided (should use parameter)
  - Config value provided, no parameter (should use config)
  - Neither provided (should use default/resolve)

#### 3.3 Add Config Validation
**File:** `EntraOps/Public/Configuration/New-EntraOpsConfigFile.ps1` (or new validation function)  
**Priority:** Medium  
**Effort:** 3 hours

- [ ] Create `Test-EntraOpsServiceEMConfig` function to validate config structure
- [ ] Validate that specified Group IDs are valid GUIDs
- [ ] Validate that specified Group names don't contain invalid characters
- [ ] Provide warnings for missing optional values

#### 3.4 Document Config Loading Behavior
**File:** `ServiceEM.md`  
**Priority:** Medium  
**Effort:** 1 hour

- [ ] Document when and how config is loaded
- [ ] Explain the precedence: Parameter > Config > Default
- [ ] Show example of verifying config is loaded before running commands

---

### Issue 4: New-EntraOpsServiceEntraGroup API Payload Fails

**Problem Statement:**
When named objects do exist, the function calls into `New-EntraOpsServiceEntraGroup`, but the constructed payload fails to succeed against the Microsoft Graph API.

**Root Cause Analysis:**
> **⚠️ CORRECTION**: The original work plan incorrectly identified JSON property casing as the root cause. **The actual code already uses camelCase.** The real issue needs investigation (see Issue 4.0).
>
> Likely actual causes:
> 1. Invalid `owners@odata.bind` format - should be full OData URL
> 2. Missing required fields for Unified groups
> 3. mailNickname uniqueness constraints

**Work Items:**

#### 4.1 Fix owners@odata.bind Format
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsServiceEntraGroup.ps1`  
**Priority:** Critical  
**Effort:** 2 hours

- [ ] Verify `$ServiceOwner` parameter is in correct OData bind URL format
- [ ] If `$ServiceOwner` is just an ObjectId, construct proper URL: `"https://graph.microsoft.com/v1.0/users/$ServiceOwner"`
- [ ] Add validation that owner exists before group creation
- [ ] Test with actual Graph API calls

#### 4.2 Add Payload Validation
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsServiceEntraGroup.ps1`  
**Priority:** High  
**Effort:** 2 hours

- [ ] Add validation that `ServiceOwner` is in correct OData bind format
- [ ] Validate required fields are present before API call
- [ ] Validate `mailNickname` is unique and follows naming conventions
- [ ] Add max length checks for displayName (256 chars) and mailNickname (64 chars)

#### 4.3 Improve Error Handling and Logging
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsServiceEntraGroup.ps1`  
**Priority:** High  
**Effort:** 2 hours

- [ ] Capture and log full API error response details
- [ ] Include request payload in error output for debugging
- [ ] Distinguish between different failure types (auth, validation, conflict, etc.)
- [ ] Add request/response logging in verbose mode

#### 4.4 Add Unit Tests for Group Creation
**Priority:** High  
**Effort:** 4 hours

- [ ] Create mock tests for `New-EntraOpsServiceEntraGroup`
- [ ] Test both Unified and Security group creation
- [ ] Test PIM staging group creation
- [ ] Test error scenarios (duplicate names, invalid owners, etc.)
- [ ] Test idempotency (re-running should not fail)

#### 4.5 Verify Microsoft 365 Group Creation
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsServiceEntraGroup.ps1`  
**Priority:** Medium  
**Effort:** 2 hours

- [ ] Verify Microsoft 365 (Unified) groups can be created with current payload
- [ ] Check if additional properties are required for Unified groups
- [ ] Test with and without owners
- [ ] Document any additional requirements for Unified groups

#### 4.6 Create Mock Testing Framework
**Priority:** High  
**Files:** `Tests/ServiceEM/`  
**Effort:** 3 hours

- [ ] Create Pester tests with Microsoft.Graph mock responses
- [ ] Mock `Invoke-EntraOpsMsGraphQuery` for offline testing
- [ ] Test payload construction without actual API calls
- [ ] Add CI/CD pipeline step to run ServiceEM tests

---

### Issue 5: GovernanceModel Property Documentation Mismatch

**Problem Statement:**
The documentation shows `-GovernanceModel` as a parameter for `New-EntraOpsSubscriptionLandingZone`, but this parameter does not exist in the function. The governance model is only read from config.

**Root Cause Analysis:**
- Documentation example shows: `New-EntraOpsSubscriptionLandingZone ... -GovernanceModel "Centralized"`
- Function signature does NOT include `-GovernanceModel` parameter
- Code reads: `$governanceModel = $Global:EntraOpsConfig.ServiceEM.GovernanceModel` with fallback to "Centralized"
- Users cannot override governance model via parameter, only via config file

**Work Items:**

#### 5.1 Add GovernanceModel Parameter
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`  
**Priority:** High  
**Effort:** 2 hours

- [ ] Add `[string]$GovernanceModel` parameter with `[ValidateSet("Centralized", "PerService")]`
- [ ] Update parameter precedence logic: Parameter > Config > Default
- [ ] Ensure parameter value is used instead of config value when provided
- [ ] Add verbose logging showing which governance model is being used and why

#### 5.2 Update Parameter Documentation
**File:** `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`  
**Priority:** Medium  
**Effort:** 1 hour

- [ ] Add `.PARAMETER GovernanceModel` documentation block
- [ ] Document valid values: "Centralized", "PerService"
- [ ] Document default behavior (reads from config, falls back to "PerService" after Issue 1.0)
- [ ] Add example showing explicit GovernanceModel usage

#### 5.3 Verify Documentation Alignment
**File:** `ServiceEM.md`  
**Priority:** Medium  
**Effort:** 1 hour

- [ ] Review all code examples in documentation
- [ ] Ensure all shown parameters actually exist
- [ ] Update any examples that use non-existent parameters
- [ ] Add note about which parameters are required vs. optional

---

## Implementation Phases

### Phase 0: Critical Pre-Implementation (MUST COMPLETE FIRST)
**Timeline:** 2-3 days  
**Focus:** Fix fundamental issues before other work

1. **Issue 1.0** - Change default governance model to PerService (Critical)
2. **Issue 3.0** - Add config file loading mechanism (Critical)
3. **Issue 4.0** - Verify actual API failure cause (Critical)
4. **Issue 4.1** - Fix owners@odata.bind format (Critical)

### Phase 1: Critical Fixes (Issues 4, 1, 3)
**Timeline:** Week 1  
**Focus:** Fix broken functionality and config handling

1. **Issue 4.2** - Add payload validation (Critical)
2. **Issue 4.3** - Improve error handling (Critical)
3. **Issue 3.1** - Add config loading verification (High)
4. **Issue 3.2** - Fix config value precedence (High)
5. **Issue 1.2** - Improve error handling and guidance (High)
6. **Issue 1.5** - Add graceful fallback to PerService (High)

### Phase 2: Parameter and Documentation Fixes (Issues 5, 2)
**Timeline:** Week 2  
**Focus:** Align documentation with implementation

1. **Issue 5.1** - Add GovernanceModel parameter (High)
2. **Issue 5.2** - Update parameter documentation (Medium)
3. **Issue 5.3** - Verify documentation alignment (Medium)
4. **Issue 2.1** - Clarify switch behavior in docs (Medium)
5. **Issue 2.2** - Add verbose logging for switches (Medium)

### Phase 3: Documentation and Polish (Issues 1, 3)
**Timeline:** Week 3  
**Focus:** Documentation and user experience

1. **Issue 1.1** - Update documentation prerequisites (High)
2. **Issue 1.3** - Add governance model validation (Medium)
3. **Issue 1.4** - Create PerService quick start (Medium)
4. **Issue 3.3** - Add config validation (Medium)
5. **Issue 3.4** - Document config loading behavior (Medium)

### Phase 4: Testing and Validation
**Timeline:** Week 4  
**Focus:** Comprehensive testing

1. **Issue 4.4** - Add unit tests (High)
2. **Issue 4.5** - Verify Microsoft 365 group creation (Medium)
3. **Issue 4.6** - Create mock testing framework (High)
4. End-to-end testing of all scenarios
5. Documentation review and final updates

---

## Testing Scenarios

### Scenario 1: Simple Deployment (Issue 1)
```powershell
# Should work without pre-existing groups (PerService default)
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "TestApp" `
    -AzureRegion "westeurope" `
    -ServiceOwner "admin@contoso.com" `
    -Verbose
```

### Scenario 2: Skip Switches (Issue 2)
```powershell
# Should explicitly skip even when no Group IDs provided
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "TestApp" `
    -AzureRegion "westeurope" `
    -SkipControlPlaneDelegation `
    -SkipManagementPlaneDelegation
```

### Scenario 3: Config Values (Issue 3)
```powershell
# Should use Group IDs from config
# EntraOpsConfig.json contains:
# {
#   "ServiceEM": {
#     "ControlPlaneDelegationGroupId": "guid-here",
#     "ManagementPlaneDelegationGroupId": "guid-here"
#   }
# }
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "TestApp" `
    -AzureRegion "westeurope"
```

### Scenario 4: Group Creation (Issue 4)
```powershell
# Should successfully create groups without API errors
New-EntraOpsServiceEntraGroup `
    -ServiceName "TestService" `
    -ServiceOwner "https://graph.microsoft.com/v1.0/users/user-guid" `
    -ServiceRoles $roles
```

### Scenario 5: GovernanceModel Parameter (Issue 5)
```powershell
# Should work with explicit parameter
New-EntraOpsSubscriptionLandingZone `
    -DeploymentPrefix "TestApp" `
    -AzureRegion "westeurope" `
    -GovernanceModel "Centralized"
```

---

## Verification Checklist

Before marking each phase complete, verify:

### Phase 0 Verification
- [ ] Simple deployment works without pre-existing groups (Issue 1.0)
- [ ] Config file is automatically loaded if present (Issue 3.0)
- [ ] Actual API error cause is identified (Issue 4.0)
- [ ] Group creation succeeds with correct owner format (Issue 4.1)

### Phase 1 Verification
- [ ] Clear error messages when groups don't exist (Issue 1.2)
- [ ] Graceful fallback to PerService when Centralized groups missing (Issue 1.5)
- [ ] Config values take precedence over defaults (Issue 3.2)
- [ ] All API calls succeed with proper payload (Issue 4.2, 4.3)

### Phase 2 Verification
- [ ] GovernanceModel parameter exists and works (Issue 5.1)
- [ ] Documentation examples match actual parameters (Issue 5.3)
- [ ] Skip switch behavior is clear from verbose logs (Issue 2.2)

### Phase 3 Verification
- [ ] Prerequisites clearly documented (Issue 1.1)
- [ ] PerService quick start guide exists (Issue 1.4)
- [ ] Config validation catches invalid values (Issue 3.3)

### Phase 4 Verification
- [ ] Unit tests pass for group creation (Issue 4.4)
- [ ] Mock testing framework works offline (Issue 4.6)
- [ ] All 5 original issues are resolved

---

## Success Criteria

- [ ] Simple deployment provides clear error message when prerequisites not met
- [ ] Skip switches work consistently and are well-documented
- [ ] Config file values are properly loaded and used
- [ ] Group creation succeeds against Graph API without payload errors
- [ ] GovernanceModel parameter exists and works as documented
- [ ] All documentation examples are accurate and tested
- [ ] Unit tests cover all critical paths
- [ ] **NEW:** Default governance model is PerService (no pre-existing groups required)
- [ ] **NEW:** Config file is automatically loaded if present
- [ ] **NEW:** Actual API failure cause is verified and fixed

---

## Related Files

### Core Implementation Files
- `EntraOps/Public/ServiceEM/New-EntraOpsSubscriptionLandingZone.ps1`
- `EntraOps/Public/ServiceEM/New-EntraOpsServiceBootstrap.ps1`
- `EntraOps/Public/ServiceEM/New-EntraOpsServiceEntraGroup.ps1`
- `EntraOps/Private/Resolve-EntraOpsServiceEMDelegationGroup.ps1`
- `EntraOps/Public/Configuration/New-EntraOpsConfigFile.ps1`

### Documentation Files
- `ServiceEM.md`
- `ServiceEM-LandingZone-Visualization.md`
- `README.md`

### Test Files (to be created)
- `Tests/ServiceEM/New-EntraOpsServiceEntraGroup.Tests.ps1`
- `Tests/ServiceEM/New-EntraOpsSubscriptionLandingZone.Tests.ps1`

---

## Notes

- All changes should be made on the `feature-ElmLz` branch
- Consider creating feature sub-branches for each issue (e.g., `feature/ServiceEM-issue-1`, `feature/ServiceEM-issue-4`)
- Ensure backward compatibility where possible
- Add verbose logging to aid troubleshooting
- Update CHANGELOG.md with each fix
- **CRITICAL:** Complete Phase 0 (Issues 1.0, 3.0, 4.0, 4.1) before other work to avoid wasted effort on incorrect assumptions

---

## Appendix: Current Code References

### Config Structure (from New-EntraOpsConfigFile.ps1)
```powershell
ServiceEM = [ordered]@{
    GovernanceModel                  = "Centralized"
    ControlPlaneDelegationGroupId    = ""
    ControlPlaneGroupName            = "PRG-Tenant-ControlPlane-IdentityOps"
    ManagementPlaneDelegationGroupId = ""
    ManagementPlaneGroupName         = "PRG-Tenant-ManagementPlane-PlatformOps"
    AdministratorGroupId             = ""
    # ... additional settings
}
```

### Default Landing Zone Components
```powershell
[pscustomobject[]]$LandingZoneComponents = @(
    [pscustomobject]@{
        Role = "Sub"
        ServiceRole = @(
            [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
            [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
            [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
            [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
        )
    },
    [pscustomobject]@{
        Role = "Rg"
        ServiceRole = @(
            [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"},
            [pscustomobject]@{accessLevel = "CatalogPlane"; name = "Members"; groupType = ""},
            [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Members"; groupType = ""},
            [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Users"; groupType = ""},
            [pscustomobject]@{accessLevel = "WorkloadPlane"; name = "Admins"; groupType = ""}
        )
    }
)
```

### Known Issues (Corrected)
The original work plan incorrectly identified JSON casing as the root cause for Issue 4. **The actual code already uses camelCase.** The real issue is likely the `owners@odata.bind` format or other payload validation issues. See Issue 4.0 for verification steps.
