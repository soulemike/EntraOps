<#
.SYNOPSIS
    Export EntraOps Privileged EAM data as a BloodHound OpenGraph JSON file.

.DESCRIPTION
    Reads the existing EAM JSON export files and converts them into a BloodHound
    OpenGraph-compatible JSON payload (graph.nodes + graph.edges) that can be
    uploaded directly to BloodHound CE or Enterprise via the standard UI upload
    or the BloodHound API. The payload is intended to enrich an existing
    AzureHound-ingested tenant graph.

    Node kinds emitted:
        AzureHound-native principals:
            AZUser, AZGroup, AZServicePrincipal, AZDevice
        AzureHound-native Entra ID role nodes:
            AZRole
        EntraOps role nodes:
            EO_DefenderRole, EO_IntuneRole, EO_IdGovRole, EO_AppRole
        EntraOps role-assignment nodes:
            EO_EntraRoleAssignment, EO_DefenderRoleAssignment, EO_IntuneRoleAssignment,
            EO_IdGovRoleAssignment, EO_AppRoleAssignment
        EntraOps other nodes:
            EO_AdministrativeUnit, EO_Base

    Edge kinds emitted:
        EO_HasEntraRole                 - principal holds an active Entra ID directory role
        EO_HasDefenderRole              - principal holds an active Defender RBAC role
        EO_HasIntuneRole                - principal holds an active Intune / Device Management role
        EO_HasIdGovRole                 - principal holds an active Identity Governance role
        EO_HasAppRole                   - principal holds an active Resource App API permission role
        EO_EligibleForEntraRole         - principal is PIM-eligible for an Entra ID directory role
        EO_EligibleForDefenderRole      - principal is PIM-eligible for a Defender RBAC role
        EO_EligibleForIntuneRole        - principal is PIM-eligible for an Intune role
        EO_EligibleForIdGovRole         - principal is PIM-eligible for an Identity Governance role
        EO_EligibleForAppRole           - principal is PIM-eligible for a Resource App role
        EO_Has*RoleAssignment           - principal has a concrete EntraOps role-assignment node
        EO_*RoleAssigned                - role definition is linked to its role-assignment node
        EO_ClassifiedViaObject          - principal or role assignment was tier-classified because of a tagged object
        EO_ScopedTo                     - role assignment is scoped to an administrative unit or tenant
        EO_AssignedToAdministrativeUnit - principal is a member of an administrative unit
        EO_HasWorkAccount               - privileged account is linked to a standard work account
        EO_UsesPAW                      - privileged account is assigned a PAW/SAW device
        EO_PAWFor                       - PAW/SAW device is assigned to a privileged account
        EO_OwnsDevice                   - principal owns / has registered a device
        EO_DeviceOwner                  - registered device is owned by a principal
        EO_IsSponsoredBy                - guest or external identity is sponsored by another principal
        EO_HasIdentityParent            - identity was derived from / linked to a parent identity
        EO_IntuneRolePermission         - Intune role assignment/principal has matched actions scoped to a device

    Entra ID role definitions use the AzureHound-native AZRole kind so EntraOps
    enriches the canonical BloodHound node instead of trying to change its kind.
    EntraOps-owned EO_HasEntraRole, EO_EligibleForEntraRole,
    EO_EntraRoleAssignment, EO_HasEntraRoleAssignment, and EO_EntraRoleAssigned
    preserve the additional assignment and classification context.

    Top-level EntraOps tier/name properties are stored on nodes;
    per-assignment classification details travel as edge properties.

.PARAMETER ImportPath
    Root folder that holds the per-RBAC-system export sub-folders produced by
    Save-EntraOpsPrivilegedEAMJson. Defaults to $DefaultFolderClassifiedEam.

.PARAMETER RbacSystems
    Which RBAC systems to include. Defaults to all five supported systems.

.PARAMETER OutputPath
    Where to write the resulting JSON file. Defaults to
    <ImportPath>/BloodHound/EntraOps_OpenGraph.json.

.PARAMETER IncludeClassifiedViaObjectEdges
    When $true (default), emit EO_ClassifiedViaObject edges from principals to the
    objects referenced in TaggedByObjectIds. Set to $false to reduce graph size
    when you only need the role-assignment edges.

.PARAMETER IncludeAdministrativeUnitEdges
    When $true (default), emit EO_ScopedTo edges for administrative unit and
    tenant-wide role assignment scopes, and EO_AdministrativeUnit nodes for AU scopes.
    Set to $false to omit scope edges and AU scope nodes.

.PARAMETER IncludeAdministrativeUnitMembershipEdges
    When $true (default), emit EO_AssignedToAdministrativeUnit edges from each principal to
    the administrative units it is a direct member of (from AssignedAdministrativeUnits).
    Set to $false to omit these edges.

.PARAMETER IncludeWorkAccountEdges
    When $true (default), emit EO_HasWorkAccount edges from a privileged account to its associated
    standard work account (AssociatedWorkAccount) and EO_UsesPAW edges to assigned PAW/SAW
    devices (AssociatedPawDevice). Both are populated from custom security attributes.
    Set to $false to omit these edges.

.PARAMETER IncludeDeviceOwnershipEdges
    When $true (default), emit EO_OwnsDevice edges from a principal to each device it has registered
    or owns (OwnedDevices), plus inverse EO_DeviceOwner edges from the device to the principal.
    Set to $false to omit these edges.

.PARAMETER IncludeSponsorEdges
    When $true (default), emit EO_IsSponsoredBy edges from a guest or external identity to each of
    its sponsors (Sponsors). Set to $false to omit these edges.

.PARAMETER IncludeIdentityParentEdges
    When $true (default), emit EO_HasIdentityParent edges from an identity to its parent identity
    (IdentityParent), e.g. an agent service principal linked back to the originating application.
    Set to $false to omit these edges.

.PARAMETER IncludeDeviceActionEdges
    When $true (default), emit EO_IntuneRolePermission edges for DeviceManagement assignments
    where classification matched Intune actions to scoped devices. Edges are emitted from both the
    role-assignment node and the principal to the target device. Set to $false to omit these edges.

.EXAMPLE
    Export-EntraOpsPrivilegedEAMBloodHound
    # Writes EntraOps_OpenGraph.json to the default BloodHound sub-folder.

.EXAMPLE
    Export-EntraOpsPrivilegedEAMBloodHound -RbacSystems @("EntraID","ResourceApps") -OutputPath "C:\Temp\entraops.json"

.EXAMPLE
    Export-EntraOpsPrivilegedEAMBloodHound -IncludeClassifiedViaObjectEdges $false
#>
function Export-EntraOpsPrivilegedEAMBloodHound {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.String]$TenantId
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$ImportPath = $DefaultFolderClassifiedEam
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("EntraID", "IdentityGovernance", "DeviceManagement", "ResourceApps", "Defender")]
        [Array]$RbacSystems = @("EntraID", "IdentityGovernance", "DeviceManagement", "ResourceApps", "Defender")
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$OutputPath = ""
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$IncludeClassifiedViaObjectEdges = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$IncludeAdministrativeUnitEdges = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$IncludeAdministrativeUnitMembershipEdges = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$IncludeWorkAccountEdges = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$IncludeDeviceOwnershipEdges = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$IncludeSponsorEdges = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$IncludeIdentityParentEdges = $true
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$IncludeDeviceActionEdges = $true
    )

    # ── Default output path ────────────────────────────────────────────────────
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $OutputDir = Join-Path $ImportPath "BloodHound"
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        $OutputPath = Join-Path $OutputDir "EntraOps_OpenGraph.json"
    }

    # ── Lookup tables ──────────────────────────────────────────────────────────
    $HasRoleEdgeKindMap = @{
        'EntraID'            = 'EO_HasEntraRole'
        'Defender'           = 'EO_HasDefenderRole'
        'DeviceManagement'   = 'EO_HasIntuneRole'
        'IdentityGovernance' = 'EO_HasIdGovRole'
        'ResourceApps'       = 'EO_HasAppRole'
    }

    $HasRoleAssignmentEdgeKindMap = @{
        'EntraID'            = 'EO_HasEntraRoleAssignment'
        'Defender'           = 'EO_HasDefenderRoleAssignment'
        'DeviceManagement'   = 'EO_HasIntuneRoleAssignment'
        'IdentityGovernance' = 'EO_HasIdGovRoleAssignment'
        'ResourceApps'       = 'EO_HasAppRoleAssignment'
    }

    $RoleAssignedEdgeKindMap = @{
        'EntraID'            = 'EO_EntraRoleAssigned'
        'Defender'           = 'EO_DefenderRoleAssigned'
        'DeviceManagement'   = 'EO_IntuneRoleAssigned'
        'IdentityGovernance' = 'EO_IdGovRoleAssigned'
        'ResourceApps'       = 'EO_AppRoleAssigned'
    }

    # Eligible edge kinds (PIM-eligible assignments)
    $EligibleEdgeKindMap = @{
        'EntraID'            = 'EO_EligibleForEntraRole'
        'Defender'           = 'EO_EligibleForDefenderRole'
        'DeviceManagement'   = 'EO_EligibleForIntuneRole'
        'IdentityGovernance' = 'EO_EligibleForIdGovRole'
        'ResourceApps'       = 'EO_EligibleForAppRole'
    }

    $RoleNodeKindMap = @{
        'EntraID'            = @('AZRole')
        'Defender'           = @('EO_DefenderRole')
        'DeviceManagement'   = @('EO_IntuneRole')
        'IdentityGovernance' = @('EO_IdGovRole')
        'ResourceApps'       = @('EO_AppRole')
    }

    $RoleAssignmentNodeKindMap = @{
        'EntraID'            = @('EO_EntraRoleAssignment')
        'Defender'           = @('EO_DefenderRoleAssignment')
        'DeviceManagement'   = @('EO_IntuneRoleAssignment')
        'IdentityGovernance' = @('EO_IdGovRoleAssignment')
        'ResourceApps'       = @('EO_AppRoleAssignment')
    }

    # Node kinds
    $NodeKind = @{
        Base               = 'EO_Base'
        AdministrativeUnit = 'EO_AdministrativeUnit'
    }

    # Edge kinds
    $EdgeKind = @{
        MemberOf            = 'AZMemberOf'
        ScopedTo            = 'EO_ScopedTo'
        AssignedToAU        = 'EO_AssignedToAdministrativeUnit'
        ClassifiedViaObject = 'EO_ClassifiedViaObject'
        HasWorkAccount      = 'EO_HasWorkAccount'
        UsesPAW             = 'EO_UsesPAW'
        PAWFor              = 'EO_PAWFor'
        OwnsDevice          = 'EO_OwnsDevice'
        DeviceOwner         = 'EO_DeviceOwner'
        IsSponsoredBy       = 'EO_IsSponsoredBy'
        HasIdentityParent   = 'EO_HasIdentityParent'
        IntuneRolePermission    = 'EO_IntuneRolePermission'
    }

    # ObjectType → primary node kind
    $PrincipalKindMap = @{
        'user'             = @('AZUser')
        'group'            = @('AZGroup')
        'serviceprincipal' = @('AZServicePrincipal')
        'device'           = @('AZDevice')
    }

    # ── Graph data structures ──────────────────────────────────────────────────
    # $NodesIndex  : id (string) → node hashtable (deduplicated)
    # $EdgesIndex  : "startId|endId|kind" → $true  (deduplicated)
    # $EdgesList   : ordered list of edge objects
    $NodesIndex = @{}
    $EdgesIndex = @{}
    $EdgesList = [System.Collections.Generic.List[object]]::new()

    # ── Precomputed edge kind unions for Cypher queries in node properties ──────
    $AllActiveRoleEdgeKinds   = ($HasRoleEdgeKindMap.Values)              -join '|'
    $AllEligibleRoleEdgeKinds = ($EligibleEdgeKindMap.Values)             -join '|'
    $AllRoleAssignmentEdges   = ($HasRoleAssignmentEdgeKindMap.Values)    -join '|'
    $AllRoleAssignedEdges     = ($RoleAssignedEdgeKindMap.Values)         -join '|'

    # ── Helper: upsert a node  ─────────────────────────────────────────────────
    # Keeps the first-seen properties; later calls can update only if the existing
    # node lacks admintierlevel (i.e. it was a stub created for a referenced object).
    function Upsert-Node {
        param(
            [string]$Id,
            [string[]]$Kinds,
            [hashtable]$Properties
        )
        $Id = $Id.ToUpper()
        if (-not $NodesIndex.ContainsKey($Id)) {
            $NodesIndex[$Id] = @{
                id         = $Id
                kinds      = $Kinds
                properties = $Properties
            }
        } else {
            $existing = $NodesIndex[$Id]
            # Upgrade a stub node when:
            #  - existing is EO_Base only and new data has a more specific kind, OR
            #  - existing lacks admintierlevel and new data provides it
            $existingIsBaseOnly = ($existing.kinds.Count -eq 1 -and $existing.kinds[0] -eq $NodeKind.Base)
            $newIsMoreSpecific  = ($Kinds.Count -gt 0 -and $Kinds[0] -ne $NodeKind.Base)
            $upgradeByTier      = ($null -eq $existing.properties['admintierlevel']) -and
                                  ($null -ne $Properties['admintierlevel'])
            if (($existingIsBaseOnly -and $newIsMoreSpecific) -or $upgradeByTier) {
                $NodesIndex[$Id] = @{
                    id         = $Id
                    kinds      = $Kinds
                    properties = $Properties
                }
            }
        }
    }

    function Ensure-AZDeviceNode {
        param([string]$Id)
        if ([string]::IsNullOrEmpty($Id)) { return }

        Upsert-Node -Id $Id -Kinds @('AZDevice') -Properties @{}
    }

    # ── Helper: append a deduplicated edge ─────────────────────────────────────
    function Add-Edge {
        param(
            [string]$StartId,
            [string]$EndId,
            [string]$Kind,
            [hashtable]$Properties = $null
        )
        if ([string]::IsNullOrEmpty($StartId) -or [string]::IsNullOrEmpty($EndId)) { return }
        $StartId = $StartId.ToUpper()
        $EndId = $EndId.ToUpper()
        $dedupeKey = "${StartId}|${EndId}|${Kind}"
        if (-not $EdgesIndex.ContainsKey($dedupeKey)) {
            $EdgesIndex[$dedupeKey] = $true
            $edge = @{
                kind  = $Kind
                start = @{ match_by = "id"; value = $StartId }
                end   = @{ match_by = "id"; value = $EndId }
            }
            if ($null -ne $Properties -and $Properties.Count -gt 0) {
                $edge['properties'] = $Properties
            }
            $EdgesList.Add($edge) | Out-Null
        }
    }

    function Add-EdgeByEndpoint {
        param(
            [System.Collections.IDictionary]$StartEndpoint,
            [System.Collections.IDictionary]$EndEndpoint,
            [string]$Kind,
            [hashtable]$Properties = $null
        )
        if ($null -eq $StartEndpoint -or $null -eq $EndEndpoint) { return }

        $startKey = $StartEndpoint | ConvertTo-Json -Compress -Depth 5
        $endKey = $EndEndpoint | ConvertTo-Json -Compress -Depth 5
        $dedupeKey = "${startKey}|${endKey}|${Kind}"
        if (-not $EdgesIndex.ContainsKey($dedupeKey)) {
            $EdgesIndex[$dedupeKey] = $true
            $edge = @{
                kind  = $Kind
                start = $StartEndpoint
                end   = $EndEndpoint
            }
            if ($null -ne $Properties -and $Properties.Count -gt 0) {
                $edge['properties'] = $Properties
            }
            $EdgesList.Add($edge) | Out-Null
        }
    }

    function ConvertTo-PimMemberOfEdgeProperties {
        param(
            [object]$RoleAssignment,
            [string]$RbacSystem
        )

        return @{
            rbacsystem              = [string]$RbacSystem
            roleassignmenttype      = [string]($RoleAssignment.RoleAssignmentType ?? '')
            roleassignmentsubtype   = [string]($RoleAssignment.RoleAssignmentSubType ?? '')
            pimassignmenttype       = [string]($RoleAssignment.PIMAssignmentType ?? '')
            roleassignmentid        = [string]($RoleAssignment.RoleAssignmentId ?? '')
            roleassignmentscopeid   = [string]($RoleAssignment.RoleAssignmentScopeId ?? '')
            roleassignmentscopename = [string]($RoleAssignment.RoleAssignmentScopeName ?? '')
        }
    }

    function Get-PrimitiveStringArray {
        param([object]$Value)

        if ($null -eq $Value) { return @() }

        return @(
            $Value |
            Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { [string]$_ }
        )
    }

    function Add-PimEligibleMemberOfEdges {
        param(
            [string]$PrincipalId,
            [object]$RoleAssignment,
            [string]$RbacSystem
        )

        if ([string]::IsNullOrEmpty($PrincipalId) -or $null -eq $RoleAssignment) { return }
        if ([string]($RoleAssignment.RoleAssignmentType ?? '') -ne 'Transitive') { return }

        $roleAssignmentSubType = [string]($RoleAssignment.RoleAssignmentSubType ?? '')
        $edgeProps = ConvertTo-PimMemberOfEdgeProperties -RoleAssignment $RoleAssignment -RbacSystem $RbacSystem

        if ($roleAssignmentSubType -eq 'Eligible member') {
            $transitiveByObjectId = [string]($RoleAssignment.TransitiveByObjectId ?? '')
            if (-not [string]::IsNullOrWhiteSpace($transitiveByObjectId)) {
                Add-Edge -StartId $PrincipalId -EndId $transitiveByObjectId -Kind $EdgeKind.MemberOf -Properties $edgeProps
            }
            return
        }

        if ($roleAssignmentSubType -notin @('Nested Eligible member', 'Nested Eligible group member')) {
            return
        }

        $nestingIds = Get-PrimitiveStringArray -Value $RoleAssignment.TransitiveByNestingObjectIds
        if ($nestingIds.Count -lt 2) { return }

        for ($ni = 1; $ni -lt $nestingIds.Count; $ni++) {
            Add-Edge -StartId $nestingIds[$ni] -EndId $nestingIds[$ni - 1] -Kind $EdgeKind.MemberOf -Properties $edgeProps
        }
    }

    # ── Helper: pick the best (lowest tier) classification item ───────────────
    function Get-BestClassification {
        param([array]$Classifications)
        if ($null -eq $Classifications -or $Classifications.Count -eq 0) { return $null }
        return $Classifications |
        Where-Object { $null -ne $_.AdminTierLevel } |
        Sort-Object AdminTierLevel |
        Select-Object -First 1
    }

    # ── Helper: build flat edge properties from a classification item ──────────
    # OpenGraph requires flat primitives only – no nested objects.
    function ConvertTo-EdgeProperties {
        param(
            [object]$Classification,
            [object]$RoleAssignment,
            [string]$RbacSystem
        )
        $props = @{}

        if ($null -ne $Classification) {
            $props['admintierlevel'] = [string]($Classification.AdminTierLevel ?? '')
            $props['admintierlevelname'] = [string]($Classification.AdminTierLevelName ?? '')
            $props['service'] = [string]($Classification.Service ?? '')
            $props['taggedby'] = [string]($Classification.TaggedBy ?? '')
            $props['taggedbyrolesystem'] = [string]($Classification.TaggedByRoleSystem ?? '')
        }

        if ($null -ne $RoleAssignment) {
            $props['roleassignmenttype'] = [string]($RoleAssignment.RoleAssignmentType ?? '')
            $props['roleassignmentsubtype'] = [string]($RoleAssignment.RoleAssignmentSubType ?? '')
            $props['pimassignmenttype'] = [string]($RoleAssignment.PIMAssignmentType ?? '')
            $props['pimmanagedrole'] = [bool]  ($RoleAssignment.PIMManagedRole -eq $true)
            $props['roleassignmentscopeid'] = [string]($RoleAssignment.RoleAssignmentScopeId ?? '')
            $props['roleassignmentscopename'] = [string]($RoleAssignment.RoleAssignmentScopeName ?? '')
            $props['rbacsystem'] = [string]$RbacSystem
        }

        return $props
    }

    # Keep EO_IntuneRolePermission edges focused on direct device-compromise
    # evidence. Source EAM MatchedActions remains unfiltered.
    function Get-PrunedIntunePermissionActions {
        param([object[]]$Actions)

        $directCompromiseActions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($directCompromiseAction in @(
                'Microsoft.Intune/DeviceConfigurations/Assign',
                'Microsoft.Intune/DeviceConfigurations/Create',
                'Microsoft.Intune/DeviceConfigurations/Update',
                'Microsoft.Intune/MobileApps/Assign',
                'Microsoft.Intune/MobileApps/Create',
                'Microsoft.Intune/MobileApps/Relate',
                'Microsoft.Intune/MobileApps/Update',
                'Microsoft.Intune/RemoteTasks/OnDemandProactiveRemediation',
                'Microsoft.Intune/RemoteTasks/RequestRemoteAssistance'
            )) {
            [void] $directCompromiseActions.Add($directCompromiseAction)
        }

        $prunedActions = [System.Collections.Generic.List[string]]::new()
        $seenActions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($action in @($Actions)) {
            if ($null -eq $action) { continue }

            $actionStr = ([string]$action).Trim()
            if ([string]::IsNullOrEmpty($actionStr)) { continue }

            if (-not $directCompromiseActions.Contains($actionStr)) { continue }

            if ($seenActions.Add($actionStr)) {
                $prunedActions.Add($actionStr)
            }
        }

        return @($prunedActions)
    }

    # ── Main loop ─────────────────────────────────────────────────────────────

    foreach ($RbacSystem in $RbacSystems) {
        $JsonFile = Join-Path $ImportPath "$RbacSystem/$RbacSystem.json"
        if (-not (Test-Path $JsonFile)) {
            Write-Warning "No export file found for $RbacSystem at $JsonFile – skipping."
            continue
        }

        Write-Host "Processing $RbacSystem..." -ForegroundColor Cyan
        try {
            $Privileges = Get-Content -Path $JsonFile -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 10
        } catch {
            Write-Warning "Failed to read $($JsonFile): $_"
            continue
        }

        $RoleEdgeKind = $HasRoleEdgeKindMap[$RbacSystem]
        $RoleEligibleEdgeKind = $EligibleEdgeKindMap[$RbacSystem]
        $HasRoleAssignmentEdgeKind = $HasRoleAssignmentEdgeKindMap[$RbacSystem]
        $RoleAssignedEdgeKind = $RoleAssignedEdgeKindMap[$RbacSystem]
        $RoleNodeKinds = $RoleNodeKindMap[$RbacSystem]
        $RoleAssignmentNodeKinds = $RoleAssignmentNodeKindMap[$RbacSystem]

        foreach ($Privilege in $Privileges) {
            # ── 1. Principal node ──────────────────────────────────────────────
            $principalId = [string]$Privilege.ObjectId
            if ([string]::IsNullOrEmpty($principalId)) { continue }

            # Top-level Classification[] is an array of objects – flatten to primitive arrays
            $tierLevels = @(
                $Privilege.Classification |
                Where-Object { $null -ne $_.AdminTierLevel } |
                Select-Object -ExpandProperty AdminTierLevel -Unique |
                ForEach-Object { [string]$_ }
            )
            $tierNames = @(
                $Privilege.Classification |
                Where-Object { $null -ne $_.AdminTierLevelName } |
                Select-Object -ExpandProperty AdminTierLevelName -Unique |
                ForEach-Object { [string]$_ }
            )
            $services = @(
                $Privilege.Classification |
                Where-Object { $null -ne $_.Service } |
                Select-Object -ExpandProperty Service -Unique |
                ForEach-Object { [string]$_ }
            )

            $principalProps = @{
                entraopsadmintierlevel        = [string]($Privilege.ObjectAdminTierLevel ?? '')
                entraopsadmintierlevelname    = [string]($Privilege.ObjectAdminTierLevelName ?? '')
                restrictedmanagementbyrag     = [bool]  ($Privilege.RestrictedManagementByRAG -eq $true)
                restrictedmanagementbyaadrole = [bool]  ($Privilege.RestrictedManagementByAadRole -eq $true)
                restrictedmanagementbyrmau    = [bool]  ($Privilege.RestrictedManagementByRMAU -eq $true)
            }

            # For service principals ObjectSignInName holds the appId – surface it explicitly
            # so BloodHound can cross-match against AZApp / AZServicePrincipal nodes from AzureHound
            if (($Privilege.ObjectType ?? '').ToLower() -eq 'serviceprincipal') {
                $spAppId = [string]($Privilege.ObjectUserPrincipalName ?? '')
                if (-not [string]::IsNullOrEmpty($spAppId)) {
                    $principalProps['appid'] = $spAppId
                }
            }
            
            if ($tierLevels.Count -gt 0) { $principalProps['classification_tierlevels'] = $tierLevels }
            if ($tierNames.Count -gt 0) { $principalProps['classification_tiernames'] = $tierNames }
            if ($services.Count -gt 0) { $principalProps['classification_services'] = $services }
            
            $primaryKind = $PrincipalKindMap[($Privilege.ObjectType ?? '').ToLower()] ?? $NodeKind.Base
            Upsert-Node -Id $principalId -Kinds $primaryKind -Properties $principalProps

            # ── 1a. AssignedToAdministrativeUnit edges (AU membership of the object) ──
            if ($IncludeAdministrativeUnitMembershipEdges) {
                $assignedAUs = @($Privilege.AssignedAdministrativeUnits | Where-Object { $null -ne $_ })
                foreach ($AU in $assignedAUs) {
                    $auId = [string]($AU.id ?? '')
                    if ([string]::IsNullOrEmpty($auId)) { continue }
                    $auNodeId = "au-$auId"
                    $auName = [string]($AU.displayName ?? $auId)
                    
                    Upsert-Node -Id $auNodeId -Kinds $NodeKind.AdministrativeUnit -Properties @{
                        name        = $auName
                        displayname = $auName
                    }

                    Add-Edge -StartId $principalId -EndId $auNodeId -Kind $EdgeKind.AssignedToAU

                }
            }

            # ── 1b. Work account & PAW device edges ───────────────────────────
            if ($IncludeWorkAccountEdges) {
                # HasWorkAccount: admin account → associated standard work account
                $workAccountIds = @($Privilege.AssociatedWorkAccount | Where-Object { $null -ne $_ -and $_ -ne '' } | ForEach-Object { [string]$_ })
                foreach ($waId in $workAccountIds) {
                    Add-Edge -StartId $principalId -EndId $waId -Kind $EdgeKind.HasWorkAccount -Properties @{
                        rbacsystem = [string]$RbacSystem
                    }

                }

                # UsesPAW: admin account -> assigned PAW/SAW device; PAWFor is the inverse.
                $pawDeviceIds = @($Privilege.AssociatedPawDevice | Where-Object { $null -ne $_ -and $_ -ne '' } | ForEach-Object { [string]$_ })
                foreach ($pawId in $pawDeviceIds) {
                    $pawEdgeProps = @{
                        rbacsystem = [string]$RbacSystem
                    }

                    $pawDeviceEndpoint = [ordered]@{
                        match_by          = 'property'
                        kind              = 'AZDevice'
                        property_matchers = @(
                            [ordered]@{
                                key      = 'deviceid'
                                operator = 'equals'
                                value    = ([string]$pawId).ToLowerInvariant()
                            }
                        )
                    }
                    $principalEndpoint = [ordered]@{
                        match_by          = 'property'
                        kind              = @($primaryKind)[0]
                        property_matchers = @(
                            [ordered]@{
                                key      = 'objectid'
                                operator = 'equals'
                                value    = ([string]$principalId).ToUpperInvariant()
                            }
                        )
                    }

                    Add-EdgeByEndpoint -StartEndpoint $principalEndpoint -EndEndpoint $pawDeviceEndpoint -Kind $EdgeKind.UsesPAW -Properties $pawEdgeProps
                    Add-EdgeByEndpoint -StartEndpoint $pawDeviceEndpoint -EndEndpoint $principalEndpoint -Kind $EdgeKind.PAWFor -Properties $pawEdgeProps

                }
            }

            # ── 1c. Owned device edges ────────────────────────────────────────
            if ($IncludeDeviceOwnershipEdges) {
                $ownedDeviceIds = @($Privilege.OwnedDevices | Where-Object { $null -ne $_ -and $_ -ne '' } | ForEach-Object { [string]$_ })

                foreach ($devId in $ownedDeviceIds) {
                    $ownedDeviceEdgeProps = @{
                        rbacsystem = [string]$RbacSystem
                    }
                    Ensure-AZDeviceNode -Id $devId
                    Add-Edge -StartId $principalId -EndId $devId -Kind $EdgeKind.OwnsDevice -Properties $ownedDeviceEdgeProps
                    Add-Edge -StartId $devId -EndId $principalId -Kind $EdgeKind.DeviceOwner -Properties $ownedDeviceEdgeProps

                }
            }

            # ── 1d. Sponsor edges ─────────────────────────────────────────────
            if ($IncludeSponsorEdges) {
                $sponsorIds = @($Privilege.Sponsors | Where-Object { $null -ne $_ -and $_ -ne '' } | ForEach-Object { [string]$_ })
                foreach ($sponsorId in $sponsorIds) {
                    Add-Edge -StartId $principalId -EndId $sponsorId -Kind $EdgeKind.IsSponsoredBy -Properties @{
                        rbacsystem = [string]$RbacSystem
                    }

                }
            }

            # ── 1e. Identity parent edges ─────────────────────────────────────
            if ($IncludeIdentityParentEdges) {
                $identityParentId = [string]($Privilege.IdentityParent ?? '')
                if (-not [string]::IsNullOrEmpty($identityParentId)) {
                    Add-Edge -StartId $principalId -EndId $identityParentId -Kind $EdgeKind.HasIdentityParent -Properties @{
                        rbacsystem = [string]$RbacSystem
                    }

                }
            }
            # ── 2. The principal's assignments, create Role and RoleAssignment nodes/edges ───────────────────────────────────────
            foreach ($RoleAssignment in $Privilege.RoleAssignments) {

                # Start Role Assignment node creation
                ######################################
                $roleAssignmentId = [string]($RoleAssignment.RoleAssignmentId ?? '')
                if ([string]::IsNullOrEmpty($roleAssignmentId)) { continue }

                #$roleAssignmentName = [string]($RoleAssignment.RoleDefinitionName ?? $roleAssignmentId)
                $roleAssignmentName = $roleAssignmentId

                $roleAssignmentProps = @{
                    name        = $roleAssignmentName
                    displayname = $roleAssignmentName
                    rbacsystem = [string]$RbacSystem
                    roleassignmentscopeid = [string]($RoleAssignment.RoleAssignmentScopeId ?? '')
                    roleassignmentscopename = [string]($RoleAssignment.RoleAssignmentScopeName ?? '')
                    roleassignmenttype = [string]($RoleAssignment.RoleAssignmentType ?? '')
                    roleassignmentsubtype = [string]($RoleAssignment.RoleAssignmentSubType ?? '')
                }

                $matchedRoleAssignmentActions = @(
                    $RoleAssignment.Classification |
                    Where-Object { $null -ne $_.MatchedActions } |
                    ForEach-Object { $_.MatchedActions } |
                    Where-Object { -not [string]::IsNullOrEmpty($_) } |
                    Select-Object -Unique |
                    ForEach-Object { [string]$_ }
                )
                if ($matchedRoleAssignmentActions.Count -gt 0) {
                    $roleAssignmentProps['matchedactions'] = $matchedRoleAssignmentActions
                }

                # Role assignment node (stub – first occurrence wins full properties)
                Upsert-Node -Id $roleAssignmentId -Kinds $RoleAssignmentNodeKinds -Properties $roleAssignmentProps

                # Best classification for this specific assignment
                $bestClass = Get-BestClassification -Classifications $RoleAssignment.Classification
                $edgeProps = ConvertTo-EdgeProperties -Classification $bestClass -RoleAssignment $RoleAssignment -RbacSystem $RbacSystem

                Add-PimEligibleMemberOfEdges -PrincipalId $principalId -RoleAssignment $RoleAssignment -RbacSystem $RbacSystem

                # Direct or transitive assignment → role edge from principal
                Add-Edge -StartId $principalId -EndId $roleAssignmentId -Kind $HasRoleAssignmentEdgeKind -Properties $edgeProps
                

                # Start Role node creation
                ###############################
                $roleDefId = [string]($RoleAssignment.RoleDefinitionId ?? '')
                if ([string]::IsNullOrEmpty($roleDefId)) { continue }

                $roleNodeId = $roleDefId + "@" + $TenantId

                $roleDefName = [string]($RoleAssignment.RoleDefinitionName ?? $roleNodeId)

                # Role definition node (stub – first occurrence wins full properties)
                $roleNodeProps = @{
                    rbacsystem = [string]$RbacSystem
                }
                if ($RbacSystem -ne 'EntraID') {
                    $roleNodeProps['name'] = $roleDefName
                    $roleNodeProps['displayname'] = $roleDefName
                }
                Upsert-Node -Id $roleNodeId -Kinds $RoleNodeKinds -Properties $roleNodeProps

                # Best classification for this specific assignment
                $bestClass = Get-BestClassification -Classifications $RoleAssignment.Classification
                $edgeProps = ConvertTo-EdgeProperties -Classification $bestClass -RoleAssignment $RoleAssignment -RbacSystem $RbacSystem

                # Select active vs eligible edge kind based on PIM assignment type
                $effectiveEdgeKind = if ($RoleAssignment.PIMAssignmentType -eq 'Eligible') {
                    $RoleEligibleEdgeKind
                } else {
                    $RoleEdgeKind
                }

                # Direct or transitive assignment → role edge from principal
                Add-Edge -StartId $principalId -EndId $roleNodeId -Kind $effectiveEdgeKind -Properties $edgeProps

                # Link Role to RoleAssignment
                Add-Edge -StartId $roleNodeId -EndId $roleAssignmentId -Kind $RoleAssignedEdgeKind -Properties $edgeProps

                # ── Role assignment scope edge ────────────────────────────────
                if ($IncludeAdministrativeUnitEdges) {
                    $scopeId = [string]($RoleAssignment.RoleAssignmentScopeId ?? '')
                    $scopeId = $scopeId.Trim()
                    $scopeName = [string]($RoleAssignment.RoleAssignmentScopeName ?? $scopeId)
                    $roleAssignmentSubType = [string]($RoleAssignment.RoleAssignmentSubType ?? '')
                    $auScopeId = ''

                    if ($scopeId -match '^/?administrativeUnits?/([^/]+)$') {
                        $auScopeId = $Matches[1]
                    } elseif ($roleAssignmentSubType -match 'AdministrativeUnit' -and -not [string]::IsNullOrEmpty($scopeId)) {
                        $auScopeId = $scopeId
                    }

                    if (-not [string]::IsNullOrEmpty($auScopeId)) {
                        $auNodeId = "au-$auScopeId"
                        $auName = $scopeName

                        Upsert-Node -Id $auNodeId -Kinds $NodeKind.AdministrativeUnit -Properties @{
                            name        = $auName
                            displayname = $auName
                            rbacsystem = [string]$RbacSystem
                        }

                        Add-Edge -StartId $roleAssignmentId -EndId $auNodeId -Kind $EdgeKind.ScopedTo -Properties @{
                            rbacsystem           = [string]$RbacSystem
                            roleassignmenttype    = [string]($RoleAssignment.RoleAssignmentType ?? '')
                            roleassignmentsubtype = $roleAssignmentSubType
                            roleassignmentscopeid = $scopeId
                            roleassignmentscopename = $auName
                            pimassignmenttype     = [string]($RoleAssignment.PIMAssignmentType ?? '')
                            roledefinitionid      = $roleNodeId
                            roledefinitionname    = $roleDefName
                        }

                    } elseif ([string]::IsNullOrWhiteSpace($scopeId) -or $scopeId -eq '/') {
                        Add-Edge -StartId $roleAssignmentId -EndId $TenantId -Kind $EdgeKind.ScopedTo -Properties @{
                            rbacsystem           = [string]$RbacSystem
                            roleassignmenttype    = [string]($RoleAssignment.RoleAssignmentType ?? '')
                            roleassignmentsubtype = $roleAssignmentSubType
                            roleassignmentscopeid = $scopeId
                            roleassignmentscopename = $scopeName
                            pimassignmenttype     = [string]($RoleAssignment.PIMAssignmentType ?? '')
                            roledefinitionid      = $roleNodeId
                            roledefinitionname    = $roleDefName
                        }

                    }
                }

                # ── 4. ClassifiedViaObject edges ──────────────────────────────
                if ($IncludeClassifiedViaObjectEdges) {
                    foreach ($ClassItem in $RoleAssignment.Classification) {
                        # Only emit when there are actual object IDs to point to
                        $taggedBy = [string]($ClassItem.TaggedBy ?? '')
                        if ($taggedBy -in @('ControlPlaneWithoutRoleActions', '')) { continue }

                        $taggedIds = @($ClassItem.TaggedByObjectIds          | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
                        if ($taggedIds.Count -eq 0) { continue }
                        $taggedRoleSystem = [string]($ClassItem.TaggedByRoleSystem ?? '')

                        for ($ti = 0; $ti -lt $taggedIds.Count; $ti++) {
                            $taggedId = $taggedIds[$ti]
                            if ([string]::IsNullOrEmpty($taggedId)) { continue }

                            # For OAuthApplication the tagged id is an app role GUID – prefix to avoid
                            # collisions with role definition nodes that use the same GUID space
                            $resolvedTaggedId = if ($taggedBy -like '*OAuthApplication*') {
                                "app-role-$taggedId"
                            } else {
                                $taggedId
                            }

                            # Principal -[ClassifiedViaObject] -> (object)
                            Add-Edge -StartId $principalId -EndId $resolvedTaggedId -Kind $EdgeKind.ClassifiedViaObject -Properties @{
                                taggedby           = $taggedBy
                                taggedbyrolesystem = $taggedRoleSystem
                                admintierlevel     = [string]($ClassItem.AdminTierLevel ?? '')
                                admintierlevelname = [string]($ClassItem.AdminTierLevelName ?? '')
                                service            = [string]($ClassItem.Service ?? '')
                                rbacsystem        = [string]$RbacSystem
                            }

                            # RoleAssignment -[ClassifiedViaObject] -> (object)
                            Add-Edge -StartId $roleAssignmentId -EndId $resolvedTaggedId -Kind $EdgeKind.ClassifiedViaObject -Properties @{
                                taggedby           = $taggedBy
                                taggedbyrolesystem = $taggedRoleSystem
                                admintierlevel     = [string]($ClassItem.AdminTierLevel ?? '')
                                admintierlevelname = [string]($ClassItem.AdminTierLevelName ?? '')
                                service            = [string]($ClassItem.Service ?? '')
                                rbacsystem        = [string]$RbacSystem
                            }

                        }
                    }
                }

                # ── 5. IntuneRolePermission edges: RoleAssignment → Device ────────
                if ($IncludeDeviceActionEdges -and $RbacSystem -eq 'DeviceManagement') {
                    # Pre-aggregate: collect all actions and devices across classifications
                    # so we create one edge per roleAssignment→device with ALL actions combined
                    $deviceActionsMap = @{} # deviceId → @{ actions = [List]; tierLevel; tierName }
                    foreach ($ClassItem in $RoleAssignment.Classification) {
                        $scopedDevices = @($ClassItem.ScopedObjects | Where-Object { $null -ne $_ })
                        $matchedActions = Get-PrunedIntunePermissionActions -Actions @($ClassItem.MatchedActions | Where-Object { $null -ne $_ })
                        if ($scopedDevices.Count -eq 0 -or $matchedActions.Count -eq 0) { continue }

                        foreach ($scopedDevice in $scopedDevices) {
                            $deviceId = [string]($scopedDevice.id ?? '')
                            if ([string]::IsNullOrEmpty($deviceId)) { continue }

                            if (-not $deviceActionsMap.ContainsKey($deviceId)) {
                                $deviceActionsMap[$deviceId] = @{
                                    actions   = [System.Collections.Generic.List[string]]::new()
                                    tierLevel = [string]($ClassItem.AdminTierLevel ?? '')
                                    tierName  = [string]($ClassItem.AdminTierLevelName ?? '')
                                }
                            }
                            foreach ($action in $matchedActions) {
                                $actionStr = [string]$action
                                if (-not $deviceActionsMap[$deviceId].actions.Contains($actionStr)) {
                                    $deviceActionsMap[$deviceId].actions.Add($actionStr)
                                }
                            }
                        }
                    }

                    # Emit one edge per device with all aggregated actions
                    foreach ($entry in $deviceActionsMap.GetEnumerator()) {
                        $deviceId = $entry.Key
                        $edgeActions = @($entry.Value.actions)
                        if ($edgeActions.Count -eq 0) { continue }

                        Ensure-AZDeviceNode -Id $deviceId

                        # RoleAssignment → Device
                        Add-Edge -StartId $roleAssignmentId -EndId $deviceId -Kind $EdgeKind.IntuneRolePermission -Properties @{
                            actions            = $edgeActions
                            admintierlevel     = $entry.Value.tierLevel
                            admintierlevelname = $entry.Value.tierName
                            rbacsystem         = [string]$RbacSystem
                        }

                        # Principal → Device
                        $queryDeviceId = ([string]$deviceId).ToUpperInvariant()
                        $queryPrincipalId = ([string]$principalId).ToUpperInvariant()
                        # $principalDeviceComposition = @(
                        #     "MATCH p1 = (principal)-[:AZMemberOf*1..]->(group)-[:EO_HasIntuneRoleAssignment]->(ra)-[:EO_IntuneRolePermission]->(device)"
                        #     "WHERE device.objectid = '$($queryDeviceId)'"
                        #     "  AND principal.objectid = '$($queryDeviceId)'
                        #     "OPTIONAL MATCH p2 = (ra)<-[:EO_IntuneRoleAssigned]-(role)"
                        #     "RETURN p1,p2"
                        # ) -join [Environment]::NewLine
                        $principalDeviceComposition = @(
                            "MATCH p1=(principal)-[:AZMemberOf*1..]->(group:AZGroup)-[r:EO_HasIntuneRoleAssignment]->(ra:EO_IntuneRoleAssignment)-[:EO_IntuneRolePermission]->(device)"
                            "WHERE device.objectid = '$($queryDeviceId)' AND principal.objectid = '$($queryPrincipalId)'"
                            "AND NOT r.roleassignmentsubtype IN ['Nested Eligible group member', 'Eligible member']"
                            "OPTIONAL MATCH p2=(ra)<-[:EO_IntuneRoleAssigned]-(:EO_IntuneRole)"
                            "OPTIONAL MATCH p3 = (principal)-[:AZMemberOf*1..]->(group)"
                            "RETURN p1,p2,p3"
                        ) -join [Environment]::NewLine
                        Add-Edge -StartId $principalId -EndId $deviceId -Kind $EdgeKind.IntuneRolePermission -Properties @{
                            actions            = $edgeActions
                            admintierlevel     = $entry.Value.tierLevel
                            admintierlevelname = $entry.Value.tierName
                            rbacsystem         = [string]$RbacSystem
                            Composition        = $principalDeviceComposition
                        }
                    }
                }
            }
        }

        Write-Host "  ✓ $($RbacSystem): $($Privileges.Count) principals loaded" -ForegroundColor Green
    }

    # ── Add Cypher query properties to nodes ────────────────────────────────────
    # Sets of kind names for kind-based dispatch
    $RoleNodeKindSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($RoleNodeKindMap.Values | ForEach-Object { $_ })
    )
    $RoleAssignmentKindSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($RoleAssignmentNodeKindMap.Values | ForEach-Object { $_ })
    )

    # All-system edge kind strings for node query shortcuts.
    $AllActiveEdgeKindsQ   = $AllActiveRoleEdgeKinds
    $AllEligibleEdgeKindsQ = $AllEligibleRoleEdgeKinds
    $AllRaEdgesQ           = $AllRoleAssignmentEdges
    $AllRaAssignedQ        = $AllRoleAssignedEdges
    $MemberOfEdgeQ         = $EdgeKind.MemberOf
    $UsesPAWEdgeQ          = $EdgeKind.UsesPAW
    $PAWForEdgeQ           = $EdgeKind.PAWFor
    $OwnsDeviceEdgeQ       = $EdgeKind.OwnsDevice
    $DeviceOwnerEdgeQ      = $EdgeKind.DeviceOwner
    $IntunePermissionEdgeQ = $EdgeKind.IntuneRolePermission
    $AssignedToAUEdgeQ     = $EdgeKind.AssignedToAU
    $ScopedToEdgeQ         = $EdgeKind.ScopedTo

    foreach ($nodeId in @($NodesIndex.Keys)) {
        $node       = $NodesIndex[$nodeId]
        $props      = $node.properties
        $nodeKinds  = $node.kinds
        $rbacSystem = [string]($props['rbacsystem'] ?? '')
        if (-not $rbacSystem) {
            foreach ($candidateRbacSystem in $RoleAssignmentNodeKindMap.Keys) {
                $candidateKinds = @($RoleAssignmentNodeKindMap[$candidateRbacSystem])
                if ($nodeKinds | Where-Object { $candidateKinds -contains $_ }) {
                    $rbacSystem = $candidateRbacSystem
                    break
                }
            }
        }
        $queryNodeId = ([string]$nodeId).ToUpperInvariant()

        # Universal: every node gets inbound + outbound traversal queries
        $props['InboundRelationships']  = "MATCH p=(n)<-[r]-(m) WHERE n.objectid = '$queryNodeId' RETURN p"
        $props['OutboundRelationships'] = "MATCH p=(n)-[r]->(m) WHERE n.objectid = '$queryNodeId' RETURN p"

        # Resolve per-system or all-system edge kind strings
        if ($rbacSystem -and $HasRoleEdgeKindMap.ContainsKey($rbacSystem)) {
            $activeEdgeQ   = $HasRoleEdgeKindMap[$rbacSystem]
            $eligibleEdgeQ = $EligibleEdgeKindMap[$rbacSystem]
            $raEdgeQ       = $HasRoleAssignmentEdgeKindMap[$rbacSystem]
            $raAssignedQ   = $RoleAssignedEdgeKindMap[$rbacSystem]
            $roleNodeQ     = @($RoleNodeKindMap[$rbacSystem])[0]
            $raNodeQ       = @($RoleAssignmentNodeKindMap[$rbacSystem])[0]
        } else {
            $activeEdgeQ   = $AllActiveEdgeKindsQ
            $eligibleEdgeQ = $AllEligibleEdgeKindsQ
            $raEdgeQ       = $AllRaEdgesQ
            $raAssignedQ   = $AllRaAssignedQ
            $roleNodeQ     = ($RoleNodeKindMap.Values | ForEach-Object { $_ }) -join '|'
            $raNodeQ       = ($RoleAssignmentNodeKindMap.Values | ForEach-Object { $_ }) -join '|'
        }

        # Kind-specific queries
        # Role definition nodes  (AZRole, EO_DefenderRole, EO_IntuneRole, etc.)
        if ($nodeKinds | Where-Object { $RoleNodeKindSet.Contains($_) }) {
            $props['ActiveAssignments']   = "MATCH p=()-[:$activeEdgeQ|$MemberOfEdgeQ*1..]->(role) WHERE role.objectid = '$queryNodeId' RETURN p"
            $props['EligibleAssignments'] = "MATCH p=()-[:$eligibleEdgeQ|$MemberOfEdgeQ*1..]->(role) WHERE role.objectid = '$queryNodeId' RETURN p"
        }
        # Role assignment nodes  (EO_EntraRoleAssignment, EO_DefenderRoleAssignment, etc.)
        elseif ($nodeKinds | Where-Object { $RoleAssignmentKindSet.Contains($_) }) {
            $props['RoleAndAssignments'] = "MATCH p1 = (role:$roleNodeQ)-[:$raAssignedQ]->(ra:$raNodeQ) WHERE ra.objectid = '$queryNodeId' OPTIONAL MATCH p2 = (group:AZGroup)-[r:$raEdgeQ]->(ra) WHERE NOT r.roleassignmentsubtype IN ['Nested Eligible group member', 'Eligible member'] OPTIONAL MATCH p3 = (principal)-[:$MemberOfEdgeQ*1..]->(group) RETURN p1,p2,p3"
            $props['AssignmentScope'] = "MATCH p=(ra)-[:$ScopedToEdgeQ]->(scope) WHERE ra.objectid = '$queryNodeId' RETURN p"
        }
        # User nodes
        elseif ($nodeKinds -contains 'AZUser') {
            $props['Roles'] = "MATCH p=(principal)-[:$MemberOfEdgeQ*1..]->(:AZGroup)-[:$activeEdgeQ|$eligibleEdgeQ]->(role) WHERE principal.objectid = '$queryNodeId' RETURN p"
            $props['PAWDevices'] = "MATCH p=(principal)-[:$UsesPAWEdgeQ|$OwnsDeviceEdgeQ]->(device) WHERE principal.objectid = '$queryNodeId' RETURN p"
        }
        # Group nodes
        elseif ($nodeKinds -contains 'AZGroup') {
            $props['Roles']   = "MATCH p=(principal)-[:$activeEdgeQ|$eligibleEdgeQ]->(role) WHERE principal.objectid = '$queryNodeId' RETURN p"
        }
        # Service principal nodes
        elseif ($nodeKinds -contains 'AZServicePrincipal') {
            $props['Roles']   = "MATCH p=(principal)-[:$MemberOfEdgeQ*1..]->(:AZGroup)-[:$activeEdgeQ|$eligibleEdgeQ]->(role) WHERE principal.objectid = '$queryNodeId' RETURN p"
        }
        # Device nodes
        elseif ($nodeKinds -contains 'AZDevice') {
            $props['AssociatedPrincipals'] = "MATCH p=(device)-[:$PAWForEdgeQ|$DeviceOwnerEdgeQ]->(principal) WHERE device.objectid = '$queryNodeId' RETURN p"
            $props['InboundIntunePermissions']  = "MATCH p=(principal)-[:$IntunePermissionEdgeQ]->(device) WHERE device.objectid = '$queryNodeId' RETURN p"
        }
        # Administrative unit nodes
        elseif ($nodeKinds -contains 'EO_AdministrativeUnit') {
            $props['Members']           = "MATCH p=(n)-[:$AssignedToAUEdgeQ]->(au) WHERE au.objectid = '$queryNodeId' RETURN p"
            $props['ScopedByRoleAssignments'] = "MATCH p=(ra)-[:$ScopedToEdgeQ]->(au) WHERE au.objectid = '$queryNodeId' RETURN p"
        }
        # EO_Base stub nodes: no type-specific queries beyond the universal pair
    }

    # ── Assemble OpenGraph payload ─────────────────────────────────────────────
    $Payload = [ordered]@{
        graph = [ordered]@{
            nodes = @($NodesIndex.Values)
            edges = @($EdgesList)
        }
    }

    # ── Write output ──────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "Writing BloodHound OpenGraph payload..." -ForegroundColor Cyan
    $Json = $Payload | ConvertTo-Json -Depth 10 -Compress:$false
    $Json | Out-File -FilePath $OutputPath -Encoding utf8 -Force

    $NodeCount = $NodesIndex.Count
    $EdgeCount = $EdgesList.Count
    $FileSizeKB = [Math]::Round((Get-Item $OutputPath).Length / 1KB, 1)

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ BloodHound OpenGraph export complete" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Nodes : $NodeCount" -ForegroundColor Gray
    Write-Host "  Edges : $EdgeCount" -ForegroundColor Gray
    Write-Host "  File  : $OutputPath ($FileSizeKB KB)" -ForegroundColor Gray
    Write-Host ""

    return [PSCustomObject]@{
        OutputPath = $OutputPath
        NodeCount  = $NodeCount
        EdgeCount  = $EdgeCount
        FileSizeKB = $FileSizeKB
    }
}
