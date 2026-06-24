# Schema
## Metadata

**Name:** EntraOps<br />
**Display Name:** EntraOps<br />
**Version:** v1.0.0<br />
**Namespace:** EO<br />
**Environment Kind:** EO_Tenant<br />
**Source Kind:** EntraOps


## Nodes

| Icon | Node Kind | Display Name |
|------|-----------|--------------|
| ![EO_AdministrativeUnit](icons/eo_administrativeunit.png) | EO_AdministrativeUnit | Administrative Unit |
| ![EO_AppRole](icons/eo_approle.png) | EO_AppRole | App Role |
| ![EO_AppRoleAssignment](icons/eo_approleassignment.png) | EO_AppRoleAssignment | App Role Assignment |
| ![EO_Base](icons/eo_base.png) | EO_Base | EntraOps Base |
| ![EO_DefenderRole](icons/eo_defenderrole.png) | EO_DefenderRole | Defender Role |
| ![EO_DefenderRoleAssignment](icons/eo_defenderroleassignment.png) | EO_DefenderRoleAssignment | Defender Role Assignment |
| ![EO_EntraRoleAssignment](icons/eo_entraroleassignment.png) | EO_EntraRoleAssignment | Entra Role Assignment |
| ![EO_IdGovRole](icons/eo_idgovrole.png) | EO_IdGovRole | Identity Governance Role |
| ![EO_IdGovRoleAssignment](icons/eo_idgovroleassignment.png) | EO_IdGovRoleAssignment | Identity Governance Role Assignment |
| ![EO_IntuneRole](icons/eo_intunerole.png) | EO_IntuneRole | Intune Role |
| ![EO_IntuneRoleAssignment](icons/eo_intuneroleassignment.png) | EO_IntuneRoleAssignment | Intune Role Assignment |
| ![EO_Tenant](icons/eo_tenant.png) | EO_Tenant | EO_Tenant |

## Edges

| Relationship Kind | Traversable | Description |
|-------------------|:-----------:|-------------|
| EO_AppRoleAssigned | ❌ | Resource application API permission role is linked to a concrete role assignment |
| EO_AppRolePermission | ✅ |  |
| EO_AssignedToAdministrativeUnit | ❌ | Principal is a member of an administrative unit |
| EO_ClassifiedViaObject | ❌ | Principal's 'admintierlevel' property was classified because of a tagged object |
| EO_DefenderRoleAssigned | ❌ | Defender RBAC role is linked to a concrete role assignment |
| EO_DeviceOwner | ✅ | Registered device is owned by a principal |
| EO_EligibleForAppRole | ❌ | Principal is PIM-eligible for a resource application API permission role |
| EO_EligibleForDefenderRole | ❌ | Principal is PIM-eligible for a Defender RBAC role |
| EO_EligibleForEntraRole | ❌ | Principal is PIM-eligible for a Entra RBAC role |
| EO_EligibleForIdGovRole | ❌ | Principal is PIM-eligible for an Identity Governance role |
| EO_EligibleForIntuneRole | ❌ | Principal is PIM-eligible for an Intune role |
| EO_EntraRoleAssigned | ❌ | BloodHound-native Entra ID RBAC role is linked to a concrete EntraOps role assignment |
| EO_EntraRolePermission | ✅ |  |
| EO_HasAppRole | ❌ | Principal holds an active resource application API permission role |
| EO_HasAppRoleAssignment | ❌ | Principal has a concrete resource application API permission role assignment |
| EO_HasDefenderRole | ❌ | Principal holds an active Defender RBAC role |
| EO_HasDefenderRoleAssignment | ❌ | Principal has a concrete Defender RBAC role assignment |
| EO_HasEntraRole | ❌ | Principal holds an active Entra RBAC role |
| EO_HasEntraRoleAssignment | ❌ | Principal has a concrete Entra ID RBAC role assignment |
| EO_HasIdentityParent | ❌ | Identity was derived from or linked to a parent identity |
| EO_HasIdGovRole | ❌ | Principal holds an active Identity Governance role |
| EO_HasIdGovRoleAssignment | ❌ | Principal has a concrete Identity Governance role assignment |
| EO_HasIntuneRole | ❌ | Principal holds an active Intune / Device Management role |
| EO_HasIntuneRoleAssignment | ❌ | Principal has a concrete Intune / Device Management role assignment |
| EO_HasWorkAccount | ❌ | Privileged account is linked to a standard work account |
| EO_IdGovRoleAssigned | ❌ | Identity Governance role is linked to a concrete role assignment |
| EO_IdGovRolePermission | ✅ |  |
| EO_IntuneRoleAssigned | ❌ | Intune / Device Management role is linked to a concrete role assignment |
| [EO_IntuneRolePermission](descriptions/edges/EO_IntuneRolePermission.md) | ✅ | Can compromise the Intune device with actions scoped to the device or tenant |
| EO_IsSponsoredBy | ❌ | Guest or external identity is sponsored by another principal |
| EO_OwnsDevice | ✅ | Principal owns or has registered a device |
| EO_PAWFor | ✅ | Device is assigned to a privileged account. Based on the EntraOps-specific CustomSecurityAttribute 'PrivilegedUserPawAttribute' |
| EO_ScopedTo | ❌ | Role assignment is scoped to an administrative unit or tenant |
| EO_UsesPAW | ✅ | Privileged account is assigned a device. Based on the EntraOps-specific CustomSecurityAttribute 'PrivilegedUserPawAttribute' |
