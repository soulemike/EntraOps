# Change Log
All essential changes on EntraOps will be documented in this changelog.

## [0.8.0] - 2026-06-24
### Added
- **BloodHound OpenGraph exporter (`Export-EntraOpsPrivilegedEAMBloodHound`)**: New cmdlet that converts EntraOps Privileged EAM JSON into a BloodHound OpenGraph payload for enriching an AzureHound-ingested tenant graph. Acts as an AzureHound enrichment layer: reuses AzureHound-compatible kinds for principals, devices, groups, and Entra ID role definitions, and adds `EO_`-prefixed node/edge kinds for role assignments, assignment scope, classification evidence, PAW/device ownership, sponsor links, identity parent links, and Intune device permissions.
- **BloodHound OpenGraph extension schema (`Integrations/BloodHound/OpenGraph_EntraOps_Extension_Schema.json`)**: Defines all EntraOps-owned node kinds (`EO_*RoleAssignment`, `EO_*Role`, `EO_AdministrativeUnit`) and relationship kinds used by the exporter, including active/eligible role relationships, assignment-context edges, scope edges, administrative unit membership, PAW/device ownership, sponsorship, identity parentage, and Intune role permission paths.
- **BloodHound Cypher queries (`Integrations/BloodHound/EntraOps-queries.json`)**: Query library for BloodHound UI / queries.specterops.io covering Tier Zero administrative units, PAW usage by Tier Zero principals, Intune role assignments with device-wipe permissions, nested role assignments, PIM-for-Groups edges, sponsor relationships, and EntraOps tier classification edges.
- **BloodHound schema and node/edge documentation (`Integrations/BloodHound/schema.md`, `descriptions/`)**: Graph model rationale, RBAC model Mermaid diagrams, node/edge kind descriptions, and icon assets for the extension.
- **`EO_IntuneRolePermission` edges for DeviceManagement**: The exporter emits traversable edges from both the `EO_IntuneRoleAssignment` node and the assigned principal to scoped `AZDevice` nodes when matched Intune RBAC actions indicate device-impacting administrative capability. This makes cloud-managed PAW tier-boundary paths visible in BloodHound.
- **`MatchedActions` in EAM output**: Tracks which specific RBAC actions matched each classification entry.
- **`ScopedObjects` in Intune EAM output**: Resolves the concrete devices in scope (scope-group members for scoped assignments, all classified devices for tenant-wide assignments). Enables the exporter to create `EO_IntuneRolePermission` edges to concrete `AZDevice` nodes.
- **`DeviceManagement_ScopeGroupDeviceMembers.json` persistence (`Update-EntraOpsClassificationControlPlaneScope`)**: After identifying classified devices, the scope update step now builds a reverse `groupId → deviceMembers` mapping, batch-resolves device display names via Microsoft Graph, and writes this file alongside the DeviceManagement classification output. Consumed by the BloodHound exporter to resolve Intune scope groups into actual device targets.
- **First-Party App Roles (Non-Microsoft Graph APIs)**: Added support for classifying major first-party API permissions from Microsoft APIs (alongside Graph API).
- **Advanced delegated permissions support**: Enhanced support for delegated permission classifications.
- **Admin tier level attributes in `Get-EntraOpsPrivilegedEntraObject`**: New parameters to include admin tier level attributes (e.g., `adminTierLevel`, `adminTierLevelName`) in object resolution output
- **Agent identity subtype normalization in `Get-EntraOpsPrivilegedEntraObject`**: Normalizes `agentIdentity` subtypes and gracefully handles unknown object types instead of failing
- **Enhanced `Get-EntraOpsClassificationControlPlaneObjects`**: Improved function descriptions, detailed parameter documentation, and support for additional classification sources

### Changed
- **Classification templates**: Updated to latest classification templates
- **EntraOps Privileged EAM Overview workbook**: Updated resource path references and query enhancements for improved dashboard accuracy

### Breaking Changes
- **`Classification_ApiPermissions.json` replaces `Classification_AppRoles.json`**: The API permissions classification template has been renamed from `Classification_AppRoles.json` to `Classification_ApiPermissions.json` to reflect support for all first-party Microsoft APIs (not only Microsoft Graph) and delegated/application permissions. The old template file is removed. Update any references to `AppRoles` in `EntraOps.config` or automation that reads or writes `Classification_AppRoles.json` to use `Classification_ApiPermissions.json`.

### Fixed
- **`Update-EntraOpsClassificationControlPlaneScope` — missing AU scopes for unprotected devices and groups**: Administrative Units assigned to unprotected devices (no RMAU membership) and unprotected groups were previously ignored when building scope entries. Only RMAU AUs from *protected* objects were collected, so unprotected objects only triggered the directory-level `/` fallback without contributing their own AU scopes. Now, AUs from unprotected devices and unprotected groups are also included in the scope list alongside the `/` fallback.
- **`Get-EntraOpsPrivilegedEntraObject` — Linked Accounts lookup in Defender**: Fixed a bug where the XDR hunting query for associated work accounts (Linked Accounts) returned incorrect results.

## [0.7.0] - 2026-03-25
### Added
- **Tenant Governance Relationship support**: `Get-EntraOpsPrivilegedEntraIdRoles` now fetches active governance relationships from `/beta/directory/tenantGovernance/governanceRelationships` and processes delegated admin role assignments (`policySnapshot.delegatedAdministrationRoleAssignments`) from managing tenants (Tenant Governance Relationship).
- **Cross-tenant object resolution**: New private function `Invoke-EntraOpsCrossTenantObjectResolution` implements a two-phase resolution strategy — Phase 1 resolves objects in the home tenant, Phase 2 switches context to the managing tenant to resolve objects that returned `unknown` type
- **Managing tenant authentication in `Connect-EntraOps`**: New parameters `ManagingTenantId` and `ManagingTenantName` to pre-authenticate to a managing tenant across all authentication types (`UserInteractive`, `DeviceAuthentication`, `FederatedCredentials`, `MSI`, `AlreadyAuthenticated`). Settings are also auto-loaded from the config file. New global variables `ManagingTenantIdContext` and `ManagingTenantNameContext` are set for use across all cmdlets
- **`ObjectTenantId` field in EAM output**: All role assignment objects now include `ObjectTenantId` to identify whether a principal resides in the home tenant or a foreign (managing) tenant
- **Stage 5b in `Get-EntraOpsPrivilegedEAMEntraId`**: New combined processing stage for cross-tenant group expansion and object resolution — connects to the managing tenant once (single auth prompt for interactive flows), expands cross-tenant groups into transitive classification entries, resolves cross-tenant object details, then restores the home-tenant context
- **`ExpandCrossTenantGroupMembers` parameter** in `Get-EntraOpsPrivilegedEntraIdRoles`: Controls whether cross-tenant group members are expanded inline; when a managing tenant is configured, Stage 5b handles expansion instead to avoid redundant auth prompts
- **Foreign principal tracking** in `Get-EntraOpsPrivilegedEntraIdRoles`: Principal IDs sourced from Tenant Governance relationships are marked as foreign (`$ForeignPrincipalIds`) to suppress spurious home-tenant resolution warnings
- **Tenant Governance relationships included in persistent cache**: `TgRelationships` are now stored and restored alongside role definitions, assignments, eligible assignments, and PIM schedules
- **`AuthenticationType` stored in session state**: `Connect-EntraOps` stores the active authentication type in `$__EntraOpsSession['AuthenticationType']` so cross-tenant helper functions can choose the correct token-acquisition and context-restore strategy
- Identification of nesting path/chain for transitive group members in all privileged access reports (`TransitiveByNestingObjectIds`, `TransitiveByNestingObjectDisplayNames`)
- New capabilities to automate parameterization for Device Management by using `Update-EntraOpsClassificationControlPlaneScope`: `Classification_DeviceManagement.Param.json`
- New role classification section with enhanced details on classification category and capabilities in the Privileged EAM Overview workbook

### Changed
- **Device Management classification**: Split and restructured multiple Tier 0 "Global" service definitions to correctly classify Intune role actions that do not support scope tags. These actions always grant Intune tenant-wide permissions regardless of the scope tag assigned to the role assignment and are now correctly classified as ControlPlane (Tier 0) even when assigned to a non-root scope tag (`/*`). The following changes were made:
  - **Global Device Enrollment Management**: Scope-tag-unaware actions (`AppleDeviceSerialNumbers`, `CorporateDeviceIdentifiers`, `DeviceEnrollmentManagers`, `EnrollmentProfiles`, `EnrollmentProgramToken`) now match any scope (`/*`). Scope-tag-aware `AppleEnrollmentProfiles` actions moved to new "Global Apple Enrollment Management" service (root scope `/` only)
  - **Global Application Management**: Scope-tag-unaware `MicrosoftStoreForBusiness/Modify` moved to new "Global Store Management" service (`/*`)
  - **Global Mobile Device Management**: Scope-tag-unaware `AndroidSync/*` actions moved to new "Global Android Sync Management" service (`/*`)
  - **Global Endpoint Security Management**: Scope-tag-unaware `MobileThreatDefense/Modify` moved to new "Global Threat Defense Management" service (`/*`)
  - **Global Remote Assistance**: Scope-tag-unaware `RemoteAssistance/Update` moved to new "Global Remote Assistance Configuration" service (`/*`)
  - **Global Certificate Management**: All actions are scope-tag-unaware — scope updated to `/*`
  - **Organization Management**: All actions are scope-tag-unaware — scope updated to `/*`
- **Intune RBAC scope matching aligned with other role systems**: Changed `Get-EntraOpsPrivilegedEAMIntune` scope matching from explicit `if/elseif` branches to `-like` operator, consistent with Defender, Entra ID, and Identity Governance implementations. The wildcard scope `/*` now matches both root (`/`) and scoped assignments, eliminating the need for dual scope entries (`["/*", "/"]`) in classification files. Existing `ExcludedRoleAssignmentScopeName` entries (which already exclude `/` for Tier 1 "User" definitions) ensure no unintended over-classification
- **`Connect-EntraOps`**: Pre-authenticates to the managing tenant for all authentication types before connecting to the target tenant; verifies and corrects Azure/Graph context after auth if it landed on the wrong tenant; displays managing tenant info in the connection summary
- **`Disconnect-EntraOps`**: Resets `AuthenticationType` in session state (`$__EntraOpsSession`) on disconnect and includes the reset in the overall "all cleared" check
- **`Get-EntraOpsPrivilegedEntraIdRoles`**: `TenantId` now defaults to `(Get-AzContext).Tenant.Id` instead of requiring explicit passing; cache path handling is now null-safe (gracefully disables caching when `PersistentCachePath` is not set)
- **`Get-EntraOpsPrivilegedEAMEntraId`**: Batch pre-fetch and parallel object resolution now operate only on local-tenant objects; cross-tenant objects are separated out and handled in Stage 5b; throttle-limit sizing is based on local object count
- **`New-EntraOpsConfigFile`**: Removed redundant configuration file writing logic
- Improved classification transparency by handling tagging properties (`TaggedByObjectIds`, `TaggedByObjectDisplayNames`, `TaggedByRoleSystem`) during processing
- Expanded default list of classifications for automated updates in `New-EntraOpsConfigFile` to include Defender, DeviceManagement, and IdentityGovernance templates
- Refactoring of Intune (Device Management) RBAC
  - Intune AppScopeId will be used as RoleAassignmentScopeName
- Updated Privileged EAM cmdlets (`Get-EntraOpsPrivilegedDeviceRoles`, `Get-EntraOpsPrivilegedEAMDefender`, `Get-EntraOpsPrivilegedEAMIntune`) to align with new classification structures
- **`Update-EntraOpsClassificationFiles`**: Added `-IncludeParamFiles` switch (default: `$true`); when enabled, automatically includes and downloads any `.Param` variant files found in the repository for each entry in `$Classifications` (e.g., `DeviceManagement` also pulls `DeviceManagement.Param`)
- Classification will be stored in separated WatchList to avoid 10KB limit for WatchList, Parser will merge all Role Assignment details in a single view
- Updated parser to support new WatchList `EntraOps_RoleClassifications`
- Updated Privileged EAM Overview workbook: reintroduced `PrincipalDisplayName` parameter, added `SelectedRoleAssignmentIds` parameter, improved KQL queries for clarity and sorting

### Removed
- Capabilities to classify by "AssignedDeviceObjects" (optional parameter: ApplyClassificationByAssignedObjects), use `Update-EntraOpsClassificationControlPlaneScope` to identify scope of devices by Control and Management Plane users

### Security
- **`Save-EntraOpsPrivilegedEAMWatchLists`**: Added path boundary validation for `ImportPath` parameter — the resolved path is now checked against `$EntraOpsBaseFolder` to prevent path traversal attacks that could read arbitrary files and exfiltrate data to Sentinel WatchLists (ZVE-2026-9F15DF)
- **`Save-EntraOpsPrivilegedEAMEnrichmentToWatchLists`**: Applied the same `ImportPath` path boundary validation
- **`Update-EntraOps`**: PAT is no longer embedded in the `git clone` URL (visible in process listings, error messages, and logs); credentials are now passed via `GIT_CONFIG` environment variables with HTTP `extraheader`, and cleaned up in a `finally` block (ZVE-2026-DE86DC)
- **`Save-EntraOpsEAMRbacSystemJson`**: Added validation of `ObjectType` and `ObjectId` against path traversal characters before constructing file paths; added a final resolved-path check in the parallel write block to ensure output stays within the export directory (ZVE-2026-EF0F9A)

### Fixed
- Fixed a bug in `Update-EntraOpsPrivilegedAdministrativeUnit` where role-assignable groups and PIM for Groups enabled groups could be added to Restricted Management Administrative Units (RMAU), which is not supported

### Known issues
- In multi-tenant environments using user interactive mode, EntraOps may prompt for sign-in multiple times during execution.

## [0.6.0] - 2026-03-12
### Added
- Support for delegated permissions in RBAC "ResourceApps"
- Support for Agent Identities in RBAC "ResourceApps", including resolution of inherited permissions through Agent Identity Blueprint Principals
- Workbook for Agent Identities
- Identify and classify API permissions as access package resources in catalogs
- Introduction of `Get-EntraOpsCacheStatistics` to get overview of in-memory and persistent cache entries, TTL, hit/miss statistics and cache age
- New private helper functions for shared logic: `Invoke-EntraOpsParallelObjectResolution`, `Invoke-EntraOpsEAMClassificationAggregation`, `New-EntraOpsEAMOutputObject`, `Resolve-EntraOpsClassificationPath`, `Save-EntraOpsEAMRbacSystemJson`, `Show-EntraOpsWarningSummary`, `Import-EntraOpsGlobalExclusions`
- Added `LinkedIdentity` parameter to the Privileged EAM Overview workbook for filtering privileged accounts by linked identity

### Changed
- Performance enhancements by parallelization and adding support for local caching
  - Implementation of `Invoke-EntraOpsParallelObjectResolution` for sharing resolution logic across cmdlets
  - In-memory and persistent (file-based) caching for Graph API responses with configurable TTL
- Define Custom Security Attributes for Privileged Users, Workload Identities and PAWs in EntraOps config (`New-EntraOpsConfigFile`)
- Updated version of Classification Templates from AzurePrivilegedIAM
- Major improvements in UI output (displays phases of analysis) and implementation of progress bars across all EAM cmdlets
- Updated `Update-EntraOpsClassificationControlPlaneScope` to better handle service principals and application objects, including improved logging and error handling
- Improved error handling for access package catalog resolution, providing clearer warnings for invalid or deleted objects
- Enhanced `Save-EntraOpsPrivilegedEAMInsightsCustomTable` with better progress reporting during batch uploads
- `Connect-EntraOps` now displays cache configuration and status (memory cache entries, persistent cache size and age) on connection
- Summary output in `Update-EntraOpsClassificationControlPlaneScope` to display unique object sources
- Enhanced sorting in `Save-EntraOpsEAMRbacSystemJson` to include ObjectId for improved data organization
- Enhanced filtering for linked identities to include primary accounts

### Fixed
- Role assignment checks in `Get-EntraOpsPrivilegedEntraObject` for improved accuracy
- Deduplication of object IDs in `Update-EntraOpsPrivilegedConditionalAccessGroup` and `Update-EntraOpsPrivilegedUnprotectedAdministrativeUnit`
- Remove valication on `EntraOpsEamFolder` parameter to allow first-run before `PrivilegedEAM/` directory exists (kudos to @weskroesbergen, [PR #47](https://github.com/Cloud-Architekt/EntraOps/pull/47))
- Use `beta` endpoint for `roleManagement/directory/roleDefinitions` in `Get-EntraOpsPrivilegedEAMEntraId` to include roles only available in beta (kudos to @weskroesbergen, [PR #47](https://github.com/Cloud-Architekt/EntraOps/pull/47))
- Fix exclusion checks in `Get-EntraOpsPrivilegedEAMIntune` and `Get-EntraOpsPrivilegedEAMDefender` (kudos to @weskroesbergen, [PR #47](https://github.com/Cloud-Architekt/EntraOps/pull/47))
- Fix scope classification in `Get-EntraOpsPrivilegedEAMIntune` and `Get-EntraOpsPrivilegedEAMDefender` (kudos to @weskroesbergen, [PR #47](https://github.com/Cloud-Architekt/EntraOps/pull/47))

### Removed
- Support of "Azure PowerShell" only mode because of limited Graph API scope

## [0.5.0] - 2025-12-10
### Added
- [Experimental] GitHub Custom Agents for EntraOps: Report Generation and QA Agent
  - The update workflow covers agent files starting with this release; manual copying of the files is required to upgrade to v0.5
- IdentityAccountInfo will be used for identify "AssociatedWorkAccount" if no CustomSecurityAttributes are defined
  - Correlation between privileged and work account can be made by using [link/unlink an account in Microsoft Defender](https://learn.microsoft.com/en-us/defender-for-identity/link-unlink-account-to-identity)
- Identify and classify Entra roles as access package resources in catalogs
- Essential support for the “Agent ID” principal type (additional enhancements to identify inherited permissions through blueprints are planned)
- Sponsors on supported privileged objects in the PrivilegedIAM reports

### Changed
- Improved logic to expand JSON files for classification
- Updated version of Classification Templates from AzurePrivilegedIAM

### Fixed
- Limitations on identify nested PIM for Groups in role-assignable groups


## [0.4.1] - 2025-09-16
### Fixed
- Improvement in processing WatchList uploads and updates

## [0.4] - 2025-05-30
### Added
- Support for Role Management Provider "Defender" (Unified RBAC for Microsoft Defender XDR)
  - Currently, the API does not include details on Device Groups or Scope. Therefore, the RBAC system is not covered by using default settings (EntraOps.config) to avoid wrong classification by missing consideration of scope.

## [0.3.4] - 2024-12-21
### Fixed
- Type of Owners field is inconsistent [#31](https://github.com/Cloud-Architekt/EntraOps/issues/31)
  - Overall fix for multi-value fields as result of `Get-EntraOpsPrivilegedEntraObjects` to ensure valid and consistency of array type
  
## [0.3.3] - 2024-11-27

### Added
- Status of Restricted Management in Privileged EAM Workbook [#28](https://github.com/Cloud-Architekt/EntraOps/issues/28)
- Added support for EligibilityBy and enhanced PIM for Groups support

### Changed
- Added tenant root group as default for high privileged scopes
- Support for multiple scopes for high privileged 
- Improvement in visualization of Privileged EAM Workbook
- Support to identify Privileged Auth Admin as Control Plane

### Fixed
- Order of ResourceApps by tiered levels
- Improvements to Ingest API processing (fix by [weskroesbergen](https://github.com/weskroesbergen))
  - Process files in batches of 50 to avoid errors hitting the 1Mb file limit for DCRs

## [0.3.2] - 2024-10-26

### Fixed
- Various bug fixes for `Get-EntraOpsClassificationControlPlaneObjects` cmdlet, including
  - Method invocation failed [#27](https://github.com/Cloud-Architekt/EntraOps/pull/27)
  - Avoid duplicated `ObjectAdminTierLevelName` entries
  - Correct scope of high privileged roles from Azure Resource Graph

## [0.3.1] - 2024-10-13

### Fixed
- Correct description of `AdminTierLevel` and `AdminTierLevelName` for classification of Control Plane roles without Role actions (e.g., Directory Synchronization Accounts)

## [0.3] - 2024-09-15
Added support for Intune RBAC (Device Management) and new workbook for (Privileged) Workload Identities

### Added
- Support for Intune (Device Management) as Role System [#16](https://github.com/Cloud-Architekt/EntraOps/issues/16)
- Workbook for Insights on Privileged Workload Identities [#24](https://github.com/Cloud-Architekt/EntraOps/issues/24)

### Changed
- Sensitive Directory Roles without role actions will be particular classified within classification process in `Export-EntraOpsClassificationDirectoryRoles`
 [#12](https://github.com/Cloud-Architekt/EntraOps/issues/12) [#25](https://github.com/Cloud-Architekt/EntraOps/issues/25)
- Introduction of `TaggedBy` for `ControlPlaneRolesWithoutRoleActions` to apply Control Plane classification of Microsoft Entra Connect directory roles 

## [0.2] - 2024-07-31
  
Introduction of capabilities to automate assignment of privileges to Conditional Access Groups and (Restricted Management) Administrative Units but also added WatchLists for Workload IDs.

### Added
- Automated update of Microsoft Sentinel WatchList Templates [#8](https://github.com/Cloud-Architekt/EntraOps/issues/8)
- Automated coverage of privileged assets in CA groups and RMAUs [#15](https://github.com/Cloud-Architekt/EntraOps/issues/15) 
- Advanced WatchLists for Workload Identities [#22](https://github.com/Cloud-Architekt/EntraOps/issues/22) 

### Changed
- Separated cmdlet for get classification for Control Plane scope [#19](https://github.com/Cloud-Architekt/EntraOps/issues/19) 
- Added support for -AsSecureString in Az PowerShell (upcoming breaking change) [#20](https://github.com/Cloud-Architekt/EntraOps/issues/20)
- Added support for granting required permissions for automated assignment to CA and Administrative Unit

### Fixed
- Remove Azure from ValidateSet until it's available [#18](https://github.com/Cloud-Architekt/EntraOps/issues/18) 

## [0.1] - 2024-06-27
  
_Initial release of EntraOps Privileged EAM with features to automate setup for GitHub repository,
classification and ingestion of privileges in Microsoft Entra ID, Identity Governance and Microsoft Graph App Roles._
