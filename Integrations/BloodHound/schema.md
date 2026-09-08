# Schema

This page summarizes the schema for readers. Use
[`OpenGraph_EntraOps_Extension_Schema.json`](OpenGraph_EntraOps_Extension_Schema.json) when installing
the extension; that JSON file is the authoritative definition.

## Metadata

**Name:** EntraOps<br />
**Display Name:** EntraOps<br />
**Version:** v0.0.7<br />
**Namespace:** EO<br />
**Environment Kind:** EO_Tenant<br />
**Source Kind:** EntraOps

## Nodes

| Icon | Node Kind | Display Name |
|------|-----------|--------------|
| ![EO_AdministrativeUnit](icons/eo_administrativeunit.png) | `EO_AdministrativeUnit` | Administrative Unit |
| ![EO_AppRole](icons/eo_approle.png) | `EO_AppRole` | App Role |
| ![EO_AppRoleAssignment](icons/eo_approleassignment.png) | `EO_AppRoleAssignment` | App Role Assignment |
| ![EO_Base](icons/eo_base.png) | `EO_Base` | EntraOps Base |
| ![EO_DefenderRole](icons/eo_defenderrole.png) | `EO_DefenderRole` | Defender Role |
| ![EO_DefenderRoleAssignment](icons/eo_defenderroleassignment.png) | `EO_DefenderRoleAssignment` | Defender Role Assignment |
| ![EO_EntraRoleAssignment](icons/eo_entraroleassignment.png) | `EO_EntraRoleAssignment` | Entra Role Assignment |
| ![EO_IdGovRole](icons/eo_idgovrole.png) | `EO_IdGovRole` | Identity Governance Role |
| ![EO_IdGovRoleAssignment](icons/eo_idgovroleassignment.png) | `EO_IdGovRoleAssignment` | Identity Governance Role Assignment |
| ![EO_IntuneRole](icons/eo_intunerole.png) | `EO_IntuneRole` | Intune Role |
| ![EO_IntuneRoleAssignment](icons/eo_intuneroleassignment.png) | `EO_IntuneRoleAssignment` | Intune Role Assignment |
| ![EO_Tenant](icons/eo_tenant.png) | `EO_Tenant` | EntraOps tenant |

## Edges

| Relationship Kind | Traversable | Description |
|-------------------|:-----------:|-------------|
| `EO_AppRoleAssigned` | No | Resource application API permission role is linked to a concrete role assignment. |
| `EO_AppRolePermission` | Yes | Connects an app role to a resource affected by the permission. |
| `EO_AssignedToAdministrativeUnit` | No | Principal is a member of an administrative unit. |
| `EO_ClassifiedViaObject` | No | Principal classification was derived from a tagged object. |
| `EO_DefenderRoleAssigned` | No | Defender RBAC role is linked to a concrete role assignment. |
| `EO_DeviceOwner` | Yes | Registered device is owned by a principal. |
| `EO_EligibleForAppRole` | No | Principal is PIM-eligible for a resource application API permission role. |
| `EO_EligibleForDefenderRole` | No | Principal is PIM-eligible for a Defender RBAC role. |
| `EO_EligibleForEntraRole` | No | Principal is PIM-eligible for a Microsoft Entra RBAC role. |
| `EO_EligibleForIdGovRole` | No | Principal is PIM-eligible for an Identity Governance role. |
| `EO_EligibleForIntuneRole` | No | Principal is PIM-eligible for an Intune role. |
| `EO_EntraRoleAssigned` | No | BloodHound-native Entra ID RBAC role is linked to an EntraOps role assignment. |
| `EO_EntraRolePermission` | Yes | Connects an Entra role to a resource affected by the permission. |
| `EO_HasAppRole` | No | Principal holds an active resource application API permission role. |
| `EO_HasAppRoleAssignment` | No | Principal has a concrete resource application API permission role assignment. |
| `EO_HasDefenderRole` | No | Principal holds an active Defender RBAC role. |
| `EO_HasDefenderRoleAssignment` | No | Principal has a concrete Defender RBAC role assignment. |
| `EO_HasEntraRole` | No | Principal holds an active Microsoft Entra RBAC role. |
| `EO_HasEntraRoleAssignment` | No | Principal has a concrete Microsoft Entra RBAC role assignment. |
| `EO_HasIdentityParent` | No | Identity was derived from or linked to a parent identity. |
| `EO_HasIdGovRole` | No | Principal holds an active Identity Governance role. |
| `EO_HasIdGovRoleAssignment` | No | Principal has a concrete Identity Governance role assignment. |
| `EO_HasIntuneRole` | No | Principal holds an active Intune role. |
| `EO_HasIntuneRoleAssignment` | No | Principal has a concrete Intune role assignment. |
| `EO_HasWorkAccount` | No | Privileged account is linked to a standard work account. |
| `EO_IdGovRoleAssigned` | No | Identity Governance role is linked to a concrete role assignment. |
| `EO_IdGovRolePermission` | Yes | Connects an Identity Governance role to a resource affected by the permission. |
| `EO_IntuneRoleAssigned` | No | Intune role is linked to a concrete role assignment. |
| `EO_IntuneRolePermission` | Yes | Can compromise an Intune device with actions scoped to the device or tenant. |
| `EO_IsSponsoredBy` | No | Guest or external identity is sponsored by another principal. |
| `EO_OwnsDevice` | Yes | Principal owns or has registered a device. |
| `EO_PAWFor` | Yes | Device is assigned to a privileged account using the configured PAW attribute. |
| `EO_ScopedTo` | No | Role assignment is scoped to an administrative unit or tenant. |
| `EO_UsesPAW` | Yes | Privileged account is assigned a device using the configured PAW attribute. |
