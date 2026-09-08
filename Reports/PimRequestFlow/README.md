# EntraOps PIM Request Flow

Static, self-contained web app that visualizes Entra ID **Privileged Identity Management (PIM)
role settings** from a captured EntraOps Tenant Governance snapshot as a filterable Sankey flow -
no backend, database or web server required. Mirrors the
[Conditional Access Analysis](../ConditionalAccessAnalysis) app's CA Policy Flow and the
[Access Package Flow](../AccessPackageFlow) app.

This app reuses the [Configuration Analyzer](../ConfigurationAnalyzer)'s dataset
(`../ConfigurationAnalyzer/data/configuration-analyzer-data.js`) and shared snapshot/blob parsing
model (`../ConfigurationAnalyzer/js/core.js`) instead of duplicating them - generate the data there
first. That dataset already embeds every captured resource type generically, including
`microsoft.entra.roleSetting` and `microsoft.entra.roleDefinition` (both are included in the
default `TenantGovernanceSnapshot.ResourcesToInclude`), so **no dedicated data generator is needed
for this app**.

## What it shows

Every captured `microsoft.entra.roleSetting` resource (one per Entra ID directory role) is expanded
into up to three **assignment paths** - the three ways a principal ends up holding the role, each
governed by its own slice of PIM role settings:

- **Activate eligible role** - the self-service PIM request: an eligible member activates the role
  for a limited time, optionally requiring MFA, justification, a ticket number, an authentication
  context and/or approval (`ActivationReq*` / `ApprovaltoActivate` / `ActivateApprover` /
  `AuthenticationContext*`).
- **Assign eligible role** - an administrator grants a principal eligibility for the role
  (`ElegibilityAssignmentReq*` / `ExpireEligibleAssignment` /
  `PermanentEligibleAssignmentisExpirationRequired`).
- **Assign active role** - an administrator grants a principal the role directly as an active
  (non-eligible) assignment (`AssignmentReq*` / `ExpireActiveAssignment` /
  `PermanentActiveAssignmentisExpirationRequired`).

The Sankey clusters each of these into **Role &rarr; Assignment path &rarr; Requirement &rarr;
Approval &rarr; Notification**:

- **Role** - colored by access tier (Control Plane / Management Plane / User Access), resolved from
  the generated Classification Explorer role catalog and enriched by the optional [EAM Dashboard](../EamDashboard) dataset. Specifically, every privileged
  object's `roleAssignments[].classification[]` already carries the Enterprise Access Model tier of
  every Entra ID role assignment (computed by the EntraOps classification engine) - reusing that
  avoids re-implementing the role-action classification rule engine
  (`Classification_AadResources.json` matching) client-side. Use the **Role access level** filter to show only roles at a
  given tier.
- **Requirement** - which of MFA, justification, a ticket number or an authentication context is
  required for that path (or "No additional requirement"). Use the **Requirement** filter to find
  every role/path missing a specific control.
- **Approval** - whether activation requires approval, and (in the detail panel) who the configured
  approver(s) are, each resolved to their own access tier (`ActivateApprover` entries are plain
  UPNs, resolved via the same EAM Dashboard cross-reference).
- **Notification** - which audiences (admin, approver, requestor/assignee) are notified for that
  path, derived from the matching `Eligible*`/`EligibleAssignment*`/`Active*Notification*` settings.

Click a node to trace it (filter the whole diagram down to flows touching it); click an **assignment
path** node specifically to open its full detail panel (role description, requirement(s), tiered
approver list, notifications, activation duration/expiration and any risk flags). Click the
background to clear the trace.

### Risk Flags

| Risk flag ID | Detected condition |
| --- | --- |
| `noMfaActivation` | A Control Plane or Management Plane role can be activated without MFA. |
| `noApprovalActivation` | A Control Plane or Management Plane role can be activated without approval. |
| `approverNotEnforced` | `ActivateApprover` has entries while `ApprovaltoActivate` is disabled, so the approver list has no effect. |
| `approverLowerTier` | An activation approver has a lower access tier than the role being activated. |
| `authContextMissing` | An authentication context is required but no context is configured. |
| `permanentEligible` | A permanent, non-expiring eligible assignment is allowed for a privileged role. |
| `permanentActive` | A permanent, non-expiring active assignment is allowed for a privileged role. |
| `noMfaActiveAssign` | A privileged role can be directly assigned as Active without MFA at assignment time. |

Set `ConfigurationAnalyzer.PimRequestFlowExcludedRiskFlags` to an array of these IDs to omit
specific findings. It defaults to `[]`, so all risk flags are reported. The **Configuration
Wizard** exposes the same list under **Reporting & Ingestion**.

## Refresh the data

```powershell
Import-Module ./EntraOps -Force
New-EntraOpsTenantGovernanceConfigurationAnalyzerData
```

Optionally, also generate the EAM Dashboard dataset so roles and approvers are enriched with their
access tier and tier-dependent risk flags can be computed:

```powershell
New-EntraOpsPrivilegedEamDashboardData
```

Both run as part of `New-EntraOpsReportingData`.
