# EntraOps Access Package Flow

Static, self-contained web app that visualizes Entra ID Governance **entitlement management**
(access packages) from a captured EntraOps Tenant Governance snapshot as a filterable Sankey flow
- no backend, database or web server required. Mirrors the
[Conditional Access Analysis](../ConditionalAccessAnalysis) app's CA Policy Flow.

This app reuses the [Configuration Analyzer](../ConfigurationAnalyzer)'s dataset
(`../ConfigurationAnalyzer/data/configuration-analyzer-data.js`) and shared snapshot/blob parsing
model (`../ConfigurationAnalyzer/js/core.js`) instead of duplicating them - generate the data
there first (the entitlement management resource types must be included in
`TenantGovernanceSnapshot.ResourcesToInclude`).

## What it shows

- **Access Package Flow** - `Requestor scope → Assignment policy → Access package → Target
  resource role`. Every requestor, approver and target resource that resolves to a known object id
  is cross-referenced against the optional [EAM Dashboard](../EamDashboard) dataset to show its
  access tier (Control Plane / Management Plane / User Access), the same tier coloring used across
  EntraOps Reporting.
  - A requestor/approver group not itself classified by EntraOps is resolved via its transitive
    membership instead (same mechanism as the Configuration Analyzer's Privileged Assets section) -
    a member without any EntraOps classification defaults to User Access, and a group with zero
    resolvable members is User Access overall.
  - A broad "any directory member can request" requestor scope is classified as User Access too
    (rather than left unclassified), since it isn't a specific privileged identity.
  - Hover a requestor/approver/target chip (in the policy detail panel) or a Sankey node for a
    tooltip explaining *why* it got that tier (direct EntraOps classification, resolved via group
    membership, defaulted, or broad self-service scope). Use the **Requestor access level** filter
    to show only policies whose requestor scope resolves to a given tier.
  - A group-resolved entry additionally shows a **View members** button/node click that opens a
    panel listing every resolved member and its individual access tier.
- **Risk Flags** - policies where:
  - approval is **not required** to obtain a Control Plane / Management Plane resource;
  - **any directory member** (or external user) can request a Control Plane / Management Plane
    resource without a narrower requestor scope;
  - the **approver(s)** are classified at a *lower* privilege tier than the resource being
    approved;
  - (when the optional assignment dataset below is generated) a **currently assigned** principal
    is classified at a *higher* privilege tier than the policy's own approver(s).
- Click a policy node in the Sankey to open its full detail: applicable (requestor) scope,
  approver(s), target resource role(s), currently assigned principals (if generated) and
  duration/extension/access-review settings.
- Filter policies by catalog, target resource type (Groups, Azure RBAC, API permissions, Directory
  roles or Other), approval requirement and fixed expiration. Use Search for individual access packages or
  target resource names instead of loading high-cardinality selectors.

### Risk flag exclusions

Set `ConfigurationAnalyzer.AccessPackageFlowExcludedRiskFlags` to an array containing any of
`noApproval`, `broadRequestor`, `approverLowerTier`, or `assignedMorePrivileged` to omit those
findings. It defaults to `[]`, which reports every Access Package Flow risk flag.

## Requestor/approver group resolution ("access package cannot be resolved")

The Tenant Governance Snapshot's captured `AADEntitlementManagementAccessPackageAssignmentPolicy`
resource never serializes the object `id` of a `groupMembers` requestor/approver subject (only
`odataType`/`IsBackup`) - a M365DSC/UTCM capture limitation, not something fixable client-side.
`New-EntraOpsAccessPackageFlowData` recovers the real id with a small live Microsoft Graph query
against the assignment policies themselves and, when `-ResolveRequestorApproverTiers` is enabled
(defaults to the same `ConfigurationAnalyzer.ResolveGroupMembersForPrivilegedAssets` setting as the
Configuration Analyzer), resolves that group's tier and member breakdown too. Without this, a
`groupMembers` subject whose id was never captured shows as "Group members (id not captured by
snapshot)".

The same enrichment also restores a requestor scope type that a snapshot serialized as `Unknown`.
For example, `AllExistingDirectorySubjects` is shown as users, service principals, and agent
identities in the directory being eligible to request access.

## Refresh the data

The Sankey itself (requestor/policy/package/target) needs only the Configuration Analyzer dataset:

```powershell
Import-Module ./EntraOps -Force
New-EntraOpsTenantGovernanceConfigurationAnalyzerData
```

Complete target resource names and resource-role classifications, the optional "currently
assigned" enrichment, the "assigned principal more privileged than approver" flag, and
requestor/approver group id recovery + tier resolution additionally need live Microsoft Graph
queries (the Tenant Governance Snapshot has no resource type for actual assignments, never
captures a `groupMembers` subject's group id, and can serialize a target's root scope instead of
its resource name):

```powershell
New-EntraOpsAccessPackageFlowData -ResolveRequestorApproverTiers $true
```

Both run as part of `New-EntraOpsReportingData`. The generated
`data/access-package-assignments-data.js` is tenant-specific and ignored by git, same as the other
generated reporting datasets - run `Remove-EntraOpsReportingData` to remove it.
