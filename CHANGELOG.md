# Change Log
All essential changes on EntraOps will be documented in this changelog.

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
