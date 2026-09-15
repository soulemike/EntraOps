# ServiceEM Landing Zone - Resource & Dependency Visualization

> **Note**: This visualization represents a **PerService governance model** deployment where all groups are created per-service. For **Centralized governance** (using tenant-wide delegation groups), see the [Centralized Model Notes](#centralized-governance-model-notes) section below.

> Replace `{Prefix}` with your `-DeploymentPrefix` parameter value (e.g., `Sub-MyApp` or `Rg-MyApp`).  
> Nodes marked *(optional)* are skipped when using `-SkipControlPlaneDelegation`.  
> Nodes marked *(delegated)* are replaced by an existing group when a delegation Group ID is configured.

## Delegation Overview

ControlPlane-Admins and ManagementPlane-Admins groups can be **delegated** to existing groups instead of
creating new ones. This is useful when a central platform team already manages these groups across multiple
landing zones.

**How to configure delegation** (pick one):

| Method | ControlPlane-Admins | ManagementPlane-Admins |
|---|---|---|
| Parameter | `-ControlPlaneDelegationGroupId <ObjectId>` | `-ManagementPlaneDelegationGroupId <ObjectId>` |
| EntraOpsConfig | `ServiceEM.ControlPlaneDelegationGroupId` | `ServiceEM.ManagementPlaneDelegationGroupId` |
| Skip flag (no delegation, no creation) | `-SkipControlPlaneDelegation` | `-SkipManagementPlaneDelegation` |

When a delegation Group ID is set (via parameter **or** config), the skip flag is **automatically applied**:
no new group is created, and the provided group is used for all catalog role, policy approver, and Azure RBAC
assignments that would otherwise reference the landing-zone-owned group.

**What still uses the delegated group:**
- Catalog Owner role (`ControlPlaneDelegationGroupId`)
- AP Assignment Manager catalog role (`ManagementPlaneDelegationGroupId`)
- Access package approver in Workload Plane Policy, Management Plane Policy, Initial Management Membership Policy
- PIM-eligible Azure UAA on RG (`ControlPlaneDelegationGroupId`)
- PIM-eligible Azure Contributor on RG (`ManagementPlaneDelegationGroupId`)

**What is NOT applied to the delegated group:**
- PIM policy configuration (group is managed by its owning service)
- PIM eligibility assignments into the group

---

## 1. Full Dependency Overview

Shows all groups, the EM catalog with access packages, approver/requestor dependencies, and Azure RBAC in one picture.

```mermaid
flowchart TD
    %% ── Actors ──────────────────────────────────────────────────────────────
    SvcMembers(["👥 Service Members\n(Initial Users)"])
    SvcOwner(["👤 Service Owner\n(Initial Admin)"])

    %% ── Entra Groups ─────────────────────────────────────────────────────────
    subgraph GROUPS["Entra ID Groups"]
        G_Unified["{Prefix} Members\nUnified M365 Group"]

        subgraph CP_PL["Catalog Plane"]
            G_CP["SG-{Prefix}-CatalogPlane-Members"]
        end

        subgraph WP_PL["Workload Plane"]
            G_WP_Mbr["SG-{Prefix}-WorkloadPlane-Members"]
            G_WP_Usr["SG-{Prefix}-WorkloadPlane-Users"]
            G_WP_Adm["SG-{Prefix}-WorkloadPlane-Admins"]
        end

        subgraph MP_PL["Management Plane"]
            G_MP_Mbr["SG-{Prefix}-ManagementPlane-Members"]
            G_MP_Adm["SG-{Prefix}-ManagementPlane-Admins"]
            G_PIM["SG-PIM-{Prefix}-ManagementPlane-Admins\n(PIM nested group)"]
        end

        subgraph CTRL_PL["Control Plane (optional)"]
            G_Ctrl["SG-{Prefix}-ControlPlane-Admins"]
        end
    end

    %% ── EM Catalog ───────────────────────────────────────────────────────────
    subgraph CATALOG["EM Catalog · Catalog-{Prefix}"]

        subgraph CAT_ROLES["Catalog Role Assignments"]
            CR_Owner["Catalog Owner"]
            CR_Reader["Catalog Reader"]
            CR_ApMgr["AP Assignment Manager"]
        end

        subgraph AP_WP_MBR["AP-{Prefix}-WorkloadPlane-Members"]
            POL_IWP["Initial Workload Membership Policy\nRequestors: All Member Users\nStage 1 Approver: Manager L1\nFallback / Stage 2: CatalogPlane-Members\nExpiry: None · Review: Quarterly"]
        end

        subgraph AP_WP_USR["AP-{Prefix}-WorkloadPlane-Users"]
            POL_BASE_WPU["Baseline Policy\nRequestors: CatalogPlane-Members\nApprover: CatalogPlane-Members\nExpiry: 5 days · Review: Quarterly"]
        end

        subgraph AP_WP_ADM["AP-{Prefix}-WorkloadPlane-Admins"]
            POL_WP["Workload Plane Policy\nRequestors: WorkloadPlane-Members\nApprover: ManagementPlane-Admins\nExpiry: 5 days · Review: Quarterly"]
        end

        subgraph AP_CP_MBR["AP-{Prefix}-CatalogPlane-Members"]
            POL_BASE_CP["Baseline Policy\nRequestors: CatalogPlane-Members\nApprover: CatalogPlane-Members\nExpiry: 5 days · Review: Quarterly"]
        end

        subgraph AP_MP_MBR["AP-{Prefix}-ManagementPlane-Members"]
            POL_IMP["Initial Management Membership Policy\nRequestors: WorkloadPlane-Members\nApprover: ManagementPlane-Admins\nExpiry: None · Review: Quarterly"]
        end

        subgraph AP_MP_ADM["AP-{Prefix}-ManagementPlane-Admins"]
            POL_MP["Management Plane Policy\nRequestors: ManagementPlane-Members\nApprover: ManagementPlane-Admins\nExpiry: 5 days · Review: Quarterly"]
            POL_IMA["Initial Management Admin Policy\nRequestors: CatalogPlane-Members\nApprover: None (admin-driven)\nExpiry: None · Review: Quarterly"]
        end

        subgraph AP_CTRL_ADM["AP-{Prefix}-ControlPlane-Admins (optional)"]
            POL_BASE_CTRL["Baseline Policy\nRequestors: CatalogPlane-Members\nApprover: CatalogPlane-Members\nExpiry: 5 days · Review: Quarterly"]
        end

    end

    %% ── Azure ────────────────────────────────────────────────────────────────
    subgraph AZURE["Azure Resource Group"]
        AZ_RG["RG-{Prefix}"]
    end

    %% ── Catalog Role Assignments (group → catalog role) ──────────────────────
    G_Ctrl  -->|"Catalog Owner\n(EM role)"| CR_Owner
    G_CP    -->|"Catalog Reader\n(EM role)"| CR_Reader
    G_MP_Adm -->|"AP Assignment Manager\n(EM role)"| CR_ApMgr

    %% ── Access Package Resource Role Scopes (AP → group membership) ──────────
    AP_CP_MBR   -->|"grants Member role"| G_CP
    AP_WP_MBR   -->|"grants Member role"| G_WP_Mbr
    AP_WP_USR   -->|"grants Member role"| G_WP_Usr
    AP_WP_ADM   -->|"grants Member role"| G_WP_Adm
    AP_MP_MBR   -->|"grants Member role"| G_MP_Mbr
    AP_MP_ADM   -->|"grants Member role"| G_MP_Adm
    AP_CTRL_ADM -->|"grants Member role"| G_Ctrl

    %% ── Policy Approvers (dashed) ────────────────────────────────────────────
    G_CP -.->|"Approver / Fallback"| POL_IWP
    G_CP -.->|"Approver"| POL_BASE_CP
    G_CP -.->|"Approver"| POL_BASE_WPU
    G_CP -.->|"Approver"| POL_BASE_CTRL
    G_MP_Adm -.->|"Approver"| POL_WP
    G_MP_Adm -.->|"Approver"| POL_IMP
    G_MP_Adm -.->|"Approver"| POL_MP

    %% ── Policy Requestor Scopes (dashed) ────────────────────────────────────
    G_WP_Mbr -.->|"Eligible requestors"| POL_WP
    G_WP_Mbr -.->|"Eligible requestors"| POL_IMP
    G_MP_Mbr -.->|"Eligible requestors"| POL_MP
    G_CP     -.->|"Eligible requestors"| POL_IMA

    %% ── Initial Assignments (actors → packages) ──────────────────────────────
    %% Note: In Centralized governance Rg scope, members → WorkloadPlane-Users
    %%       and owner → WorkloadPlane-Admins (no ManagementPlane-Admins package)
    SvcMembers ==>|"adminAdd via\nInitial Workload Membership Policy\n(or Workload Plane Users Policy in Centralized Rg)"| AP_WP_MBR
    SvcOwner   ==>|"adminAdd via\nInitial Management Admin Policy\n(or Workload Plane Policy in Centralized Rg)"| AP_MP_ADM

    %% ── Azure RBAC ───────────────────────────────────────────────────────────
    G_MP_Mbr  -->|"PIM Eligible: Reader"| AZ_RG
    G_MP_Adm  -->|"PIM Eligible: Contributor"| AZ_RG
    G_Ctrl    -->|"PIM Eligible: User Access Administrator"| AZ_RG
    G_PIM     -->|"Direct: Owner\n(requires -pimForGroups)"| AZ_RG
```

---

## 2. Group Structure by EAM Plane

Which groups are created and how they map to the Enterprise Access Model planes.

```mermaid
flowchart LR
    subgraph UNIFIED["Unified / M365"]
        G_Unified["{Prefix} Members\nType: Unified M365 Group\nMail enabled"]
    end

    subgraph CP_PL["Catalog Plane"]
        G_CP["SG-{Prefix}-CatalogPlane-Members\nType: Security Group\nPurpose: Catalog governance audience"]
    end

    subgraph WP_PL["Workload Plane"]
        G_WP_Mbr["SG-{Prefix}-WorkloadPlane-Members\nType: Security Group\nPurpose: Standard service access"]
        G_WP_Usr["SG-{Prefix}-WorkloadPlane-Users\nType: Security Group\nPurpose: End-user workload access"]
        G_WP_Adm["SG-{Prefix}-WorkloadPlane-Admins\nType: Security Group\nPurpose: Workload admin elevation"]
    end

    subgraph MP_PL["Management Plane"]
        G_MP_Mbr["SG-{Prefix}-ManagementPlane-Members\nType: Security Group\nPurpose: Service management membership"]
        G_MP_Adm["SG-{Prefix}-ManagementPlane-Admins\nType: Security Group\nPurpose: Service management admin elevation"]
        G_PIM["SG-PIM-{Prefix}-ManagementPlane-Admins\nType: Security Group\nPurpose: PIM-activated admin nesting"]
    end

    subgraph CTRL_PL["Control Plane (optional)"]
        G_Ctrl["SG-{Prefix}-ControlPlane-Admins\nType: Security Group\nPurpose: Catalog owner + Azure UAA"]
    end

    %% PIM nesting
    G_PIM -->|"PIM eligible member of"| G_MP_Adm
```

---

## 3. Access Package → Group Resource Role Scopes

Each access package grants membership of exactly one group. Requesting and receiving approval for an AP automatically adds the user to the corresponding group.

```mermaid
flowchart LR
    subgraph APS["Access Packages\n(inside Catalog-{Prefix})"]
        AP1["AP-{Prefix}-CatalogPlane-Members"]
        AP2["AP-{Prefix}-WorkloadPlane-Members"]
        AP3["AP-{Prefix}-WorkloadPlane-Users"]
        AP4["AP-{Prefix}-WorkloadPlane-Admins"]
        AP5["AP-{Prefix}-ManagementPlane-Members"]
        AP6["AP-{Prefix}-ManagementPlane-Admins"]
        AP7["AP-{Prefix}-ControlPlane-Admins\n(optional)"]
    end

    subgraph GRP["Entra Groups"]
        G_CP["SG-{Prefix}-CatalogPlane-Members"]
        G_WP_Mbr["SG-{Prefix}-WorkloadPlane-Members"]
        G_WP_Usr["SG-{Prefix}-WorkloadPlane-Users"]
        G_WP_Adm["SG-{Prefix}-WorkloadPlane-Admins"]
        G_MP_Mbr["SG-{Prefix}-ManagementPlane-Members"]
        G_MP_Adm["SG-{Prefix}-ManagementPlane-Admins"]
        G_Ctrl["SG-{Prefix}-ControlPlane-Admins"]
    end

    AP1 -->|"Member role · no expiry scope"| G_CP
    AP2 -->|"Member role · no expiry scope"| G_WP_Mbr
    AP3 -->|"Member role · no expiry scope"| G_WP_Usr
    AP4 -->|"Member role · no expiry scope"| G_WP_Adm
    AP5 -->|"Member role · no expiry scope"| G_MP_Mbr
    AP6 -->|"Member role · no expiry scope"| G_MP_Adm
    AP7 -->|"Member role · no expiry scope"| G_Ctrl
```

---

## 4. Assignment Policies — Requestors, Approvers & Expiry

Who can request each access package and who approves it.

```mermaid
flowchart TD
    %% Groups referenced as requestor scopes or approvers
    AllUsers(["All Member Users\n(Tenant)"])
    Manager(["Requestor's Manager\n(L1 - Graph)"])
    G_CP["SG-{Prefix}-CatalogPlane-Members"]
    G_WP_Mbr["SG-{Prefix}-WorkloadPlane-Members"]
    G_MP_Mbr["SG-{Prefix}-ManagementPlane-Members"]
    G_MP_Adm["SG-{Prefix}-ManagementPlane-Admins"]

    %% ── AP-Members-WorkloadPlane ─────────────────────────────────────────────
    subgraph AP_WP_MBR["AP-{Prefix}-WorkloadPlane-Members"]
        POL_IWP["Initial Workload Membership Policy\nExpiry: None"]
    end
    AllUsers  -->|"can request"| POL_IWP
    Manager   -->|"Stage 1 Approver"| POL_IWP
    G_CP      -->|"Fallback + Stage 2 Approver"| POL_IWP

    %% ── AP-Members-ManagementPlane ───────────────────────────────────────────
    subgraph AP_MP_MBR["AP-{Prefix}-ManagementPlane-Members"]
        POL_IMP["Initial Management Membership Policy\nExpiry: None"]
    end
    G_WP_Mbr  -->|"can request"| POL_IMP
    G_MP_Adm  -->|"Approver"| POL_IMP

    %% ── AP-Admins-WorkloadPlane ──────────────────────────────────────────────
    subgraph AP_WP_ADM["AP-{Prefix}-WorkloadPlane-Admins"]
        POL_WP["Workload Plane Policy\nExpiry: 5 days"]
    end
    G_WP_Mbr  -->|"can request"| POL_WP
    G_MP_Adm  -->|"Approver"| POL_WP

    %% ── AP-Admins-ManagementPlane ────────────────────────────────────────────
    subgraph AP_MP_ADM["AP-{Prefix}-ManagementPlane-Admins"]
        POL_MP["Management Plane Policy\nExpiry: 5 days"]
        POL_IMA["Initial Management Admin Policy\nExpiry: None"]
    end
    G_MP_Mbr  -->|"can request"| POL_MP
    G_MP_Adm  -->|"Approver"| POL_MP
    G_CP      -->|"can request\n(admin-driven, no approval)"| POL_IMA

    %% ── Baseline Policy packages ─────────────────────────────────────────────
    subgraph AP_BASELINE["AP-Members-CatalogPlane  ·  AP-Users-WorkloadPlane  ·  AP-Admins-ControlPlane"]
        POL_BASE["Baseline Policy\nExpiry: 5 days"]
    end
    G_CP      -->|"can request"| POL_BASE
    G_CP      -->|"Approver"| POL_BASE

    %% ── Reviewer for all policies (dashed) ───────────────────────────────────
    G_CP -.->|"Access reviewer\n(Quarterly, 25-day window)"| POL_IWP
    G_CP -.->|"Access reviewer"| POL_IMP
    G_CP -.->|"Access reviewer"| POL_WP
    G_CP -.->|"Access reviewer"| POL_MP
    G_CP -.->|"Access reviewer"| POL_IMA
    G_CP -.->|"Access reviewer"| POL_BASE
```

---

## 5. Azure Resource Group RBAC

How groups are assigned to the Azure resource group created for the landing zone.

```mermaid
flowchart LR
    subgraph GRP["Entra Groups"]
        G_MP_Mbr["SG-{Prefix}-ManagementPlane-Members"]
        G_MP_Adm["SG-{Prefix}-ManagementPlane-Admins"]
        G_Ctrl["SG-{Prefix}-ControlPlane-Admins\n(optional)"]
        G_PIM["SG-PIM-{Prefix}-ManagementPlane-Admins"]
    end

    subgraph AZ["Azure"]
        RG["RG-{Prefix}\nResource Group"]
    end

    G_MP_Mbr  -->|"PIM Eligible\nReader"| RG
    G_MP_Adm  -->|"PIM Eligible\nContributor"| RG
    G_Ctrl    -->|"PIM Eligible\nUser Access Administrator"| RG
    G_MP_Mbr  -->|"Direct assignment\nReader\n(requires rbacModel: Azure or Both)"| RG
    G_PIM     -->|"Direct assignment\nOwner\n(requires -pimForGroups)"| RG
```

---

## 6. Catalog Role Assignments

Which groups hold governance roles in the EM Catalog itself.

```mermaid
flowchart LR
    subgraph CAT["Catalog: Catalog-{Prefix}"]
        CR_Owner["Role: Owner\n(manages catalog resources)"]
        CR_Reader["Role: Reader\n(reads catalog content)"]
        CR_ApMgr["Role: AP Assignment Manager\n(assigns access packages on behalf of others)"]
    end

    G_Ctrl["SG-{Prefix}-ControlPlane-Admins\n(optional)"]  -->|"Catalog Owner"| CR_Owner
    G_CP["SG-{Prefix}-CatalogPlane-Members"]                -->|"Catalog Reader"| CR_Reader
    G_MP_Adm["SG-{Prefix}-ManagementPlane-Admins"]          -->|"AP Assignment Manager"| CR_ApMgr
```

---

## Summary Table

| Resource | Name | Depends on |
|---|---|---|
| Unified Group | `{Prefix} Members` | — |
| Security Group | `SG-{Prefix}-CatalogPlane-Members` | — |
| Security Group | `SG-{Prefix}-WorkloadPlane-Members` | — |
| Security Group | `SG-{Prefix}-WorkloadPlane-Users` | — |
| Security Group | `SG-{Prefix}-WorkloadPlane-Admins` | — |
| Security Group | `SG-{Prefix}-ManagementPlane-Members` | — |
| Security Group | `SG-{Prefix}-ManagementPlane-Admins` | *(delegated)* |
| Security Group | `SG-PIM-{Prefix}-ManagementPlane-Admins` | ManagementPlane-Admins (PIM nesting) — skipped when delegated |
| Security Group | `SG-{Prefix}-ControlPlane-Admins` | *(optional / delegated)* |
| EM Catalog | `Catalog-{Prefix}` | All groups above (registered as resources) |
| Catalog Role | Owner | ControlPlane-Admins as principal (own or delegated group) |
| Catalog Role | Reader | CatalogPlane-Members as principal |
| Catalog Role | ApAssignmentManager | ManagementPlane-Admins as principal (own or delegated group) |
| Access Package | `AP-{Prefix}-CatalogPlane-Members` | Catalog · CatalogPlane-Members group |
| Access Package | `AP-{Prefix}-WorkloadPlane-Members` | Catalog · WorkloadPlane-Members group |
| Access Package | `AP-{Prefix}-WorkloadPlane-Users` | Catalog · WorkloadPlane-Users group |
| Access Package | `AP-{Prefix}-WorkloadPlane-Admins` | Catalog · WorkloadPlane-Admins group |
| Access Package | `AP-{Prefix}-ManagementPlane-Members` | Catalog · ManagementPlane-Members group |
| Access Package | `AP-{Prefix}-ManagementPlane-Admins` | Catalog · ManagementPlane-Admins group |
| Access Package | `AP-{Prefix}-ControlPlane-Admins` | *(optional / delegated)* Catalog · ControlPlane-Admins group |
| Assignment Policy | Initial Workload Membership Policy | WorkloadPlane-Members AP · CatalogPlane-Members (approver) |
| Assignment Policy | Initial Management Membership Policy | ManagementPlane-Members AP · ManagementPlane-Admins (approver) |
| Assignment Policy | Workload Plane Policy | WorkloadPlane-Admins AP · ManagementPlane-Admins (approver) |
| Assignment Policy | Management Plane Policy | ManagementPlane-Admins AP · ManagementPlane-Admins (approver) |
| Assignment Policy | Initial Management Admin Policy | ManagementPlane-Admins AP · CatalogPlane-Members (requestors) |
| Assignment Policy | Baseline Policy | Three APs · CatalogPlane-Members (requestors & approver) |
| Initial Assignment | Service Members → WorkloadPlane-Members AP (PerService) or WorkloadPlane-Users AP (Centralized Rg) | Initial Workload Membership Policy or Workload Plane Users Policy |
| Initial Assignment | Service Owner → ManagementPlane-Admins AP (PerService) or WorkloadPlane-Admins AP (Centralized Rg) | Initial Management Admin Policy or Workload Plane Policy |
| Azure Resource Group | `RG-{Prefix}` | ManagementPlane-Members (Reader), ManagementPlane-Admins / delegated group (Contributor), ControlPlane-Admins / delegated group (UAA) |

---

## Centralized Governance Model Notes

When deploying with `-GovernanceModel "Centralized"` or when delegation group IDs are configured in `EntraOpsConfig.json`, the landing zone structure differs significantly:

### Key Differences

**Tenant-Wide Delegation Groups:**
- ControlPlane-Admins → Shared group (e.g., `prg - Contoso - IdentityOps`)
- ManagementPlane-Admins → Shared group (e.g., `prg - Contoso - PlatformOps`)
- AdministratorGroup (CatalogPlane-Members) → Shared group (e.g., `dug - PrivilegedAccounts`)

**Sub Scope Groups:**
| Group Created | Purpose |
|---|---|
| `Sub-{Prefix} Members` | Unified M365 group only |

**Sub Scope Access Packages:**
- **NONE** — No WorkloadPlane groups exist at subscription level → zero access packages created

**Rg Scope Groups:**
| Group Created | Purpose |
|---|---|
| `Rg-{Prefix} Members` | Unified M365 group |
| `SG-Rg-{Prefix}-WorkloadPlane-Users` | Security group for data-plane access |
| `SG-Rg-{Prefix}-WorkloadPlane-Admins` | Security group for workload admin elevation |

**Rg Scope Access Packages:**
| Access Package | Grants Membership To | Policy | Initial Assignment |
|---|---|---|---|
| `AP-Rg-{Prefix}-WorkloadPlane-Users` | `SG-Rg-{Prefix}-WorkloadPlane-Users` | Workload Plane Users Policy | Service Members |
| `AP-Rg-{Prefix}-WorkloadPlane-Admins` | `SG-Rg-{Prefix}-WorkloadPlane-Admins` | Workload Plane Policy | Service Owner |

**What's NOT Created (Centralized):**
- ❌ Per-service ControlPlane-Admins groups
- ❌ Per-service ManagementPlane-Admins groups
- ❌ Per-service ManagementPlane-Members groups
- ❌ Per-service CatalogPlane-Members groups
- ❌ WorkloadPlane-Members groups (neither Sub nor Rg scope)
- ❌ PIM staging groups for delegated groups

**What STILL Happens:**
- ✅ Tenant-wide delegation groups are added to each service's catalog as resources
- ✅ Catalog role assignments use the delegated groups (Owner, AP Assignment Manager)
- ✅ Azure RBAC assignments use the delegated groups (UAA, Contributor)
- ✅ Access package policies reference delegated groups as approvers

### Centralized Model Simplified Diagram

```mermaid
flowchart TD
    %% ─── Actors ───────────────────────────────────────────────────────────
    SvcMembers(["👥 Service Members"])
    SvcOwner(["👤 Service Owner"])

    %% ─── Tenant-Wide Delegation Groups ────────────────────────────────────
    subgraph DELEGATED["Tenant-Wide Groups\n(from EntraOpsConfig.json)"]
        G_Ctrl_Global["prg - IdentityOps\n(ControlPlane delegation)"]
        G_MP_Global["prg - PlatformOps\n(ManagementPlane delegation)"]
        G_Admin_Global["dug - PrivilegedAccounts\n(Administrator / CatalogPlane)"]
    end

    %% ─── Sub Scope ────────────────────────────────────────────────────────
    subgraph SUB["Sub Scope"]
        G_Sub_Members["Sub-{Prefix} Members\n(Unified M365)"]
        CAT_Sub["Catalog-Sub-{Prefix}\n(NO access packages)"]
    end

    %% ─── Rg Scope ─────────────────────────────────────────────────────────
    subgraph RG["Rg Scope"]
        G_Rg_Members["Rg-{Prefix} Members\n(Unified M365)"]
        G_WP_Usr["SG-Rg-{Prefix}-WorkloadPlane-Users"]
        G_WP_Adm["SG-Rg-{Prefix}-WorkloadPlane-Admins"]
        
        subgraph CAT_Rg["Catalog-Rg-{Prefix}"]
            AP_WP_Usr["AP-Rg-{Prefix}-WorkloadPlane-Users\nApprover: WorkloadPlane-Admins"]
            AP_WP_Adm["AP-Rg-{Prefix}-WorkloadPlane-Admins\nApprover: ManagementPlane (delegated)"]
        end
    end

    %% ─── Azure ────────────────────────────────────────────────────────────
    subgraph AZURE["Azure"]
        AZ_RG["RG-Rg-{Prefix}"]
    end

    %% ─── Delegation groups injected into catalogs ─────────────────────────
    G_Ctrl_Global -.->|"Catalog Owner"| CAT_Sub
    G_MP_Global -.->|"AP Assignment Manager"| CAT_Sub
    G_Admin_Global -.->|"Catalog Reader"| CAT_Sub

    G_Ctrl_Global -.->|"Catalog Owner"| CAT_Rg
    G_MP_Global -.->|"AP Assignment Manager"| CAT_Rg
    G_Admin_Global -.->|"Catalog Reader"| CAT_Rg

    %% ─── Access packages grant membership ─────────────────────────────────
    AP_WP_Usr -->|"grants Member role"| G_WP_Usr
    AP_WP_Adm -->|"grants Member role"| G_WP_Adm

    %% ─── Initial assignments ──────────────────────────────────────────────
    SvcMembers ==>|"adminAdd"| AP_WP_Usr
    SvcOwner ==>|"adminAdd"| AP_WP_Adm

    %% ─── Azure RBAC ───────────────────────────────────────────────────────
    G_Ctrl_Global -->|"PIM Eligible: UAA\n(inherited from subscription)"| AZ_RG
    G_MP_Global -->|"PIM Eligible: Contributor\n(inherited from subscription)"| AZ_RG
    G_WP_Adm -->|"PIM Eligible: Contributor"| AZ_RG
```

**Benefits of Centralized Model:**
- **Reduced group sprawl**: 3 tenant-wide groups instead of 5-7 per service
- **Consistent administrators**: Same IdentityOps team manages UAA across all services
- **Simplified PIM**: One activation for PlatformOps grants Contributor across multiple services
- **Clearer separation**: ControlPlane/ManagementPlane managed outside service landing zones

**When to Use Centralized:**
- ✅ 10+ services with dedicated operations teams (IdentityOps, PlatformOps)
- ✅ Organization has mature persona-based administration model
- ✅ Consistent delegation across all landing zones preferred

**When to Use PerService:**
- ✅ 1-5 services with dedicated service-specific teams
- ✅ Need full isolation between service administrative domains
- ✅ Dev/test environments where autonomy is prioritized
