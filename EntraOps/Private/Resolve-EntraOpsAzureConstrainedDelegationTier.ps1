function Resolve-EntraOpsAzureConstrainedDelegationTier {
    <#
    .SYNOPSIS
        Downgrades the Authorization (roleAssignments write/delete) classification of an Azure RBAC
        assignment when an ABAC RoleAssignmentCondition limits which roles can be delegated.
    .DESCRIPTION
        Azure RBAC supports condition-based (ABAC) constrained delegation, where a role that can write
        role assignments (e.g. Role Based Access Control Administrator, User Access Administrator, Owner)
        is restricted so the principal can only assign a specific allow-list of roles, or any role except
        a deny-list. Such a delegation is not itself "Control Plane" if it cannot be used to grant
        control-plane access. This helper re-tiers the Authorization classification of the assignment by
        classifying the RoleDefinitionIds referenced in the condition against the same RoleAssignmentScopeId,
        using the same classification rules used for normal role-assignment tiering.

                Behavior:
                - Only applies when an assignment- or role-definition-level condition constrains
                    "Microsoft.Authorization/roleAssignments" write/delete by RoleDefinitionId, the assignment already
                    has an Authorization Control Plane (Tier 0) entry, and the RoleAssignmentScopeId is not itself a
                    concrete control-plane scope.
                - The negated ActionMatches guards ("(!(ActionMatches{'...roleAssignments/write'})) OR (...)") decide
                    WHICH actions the RoleDefinitionId allow-list applies to: only guarded actions are re-tiered, an
                    unguarded write/delete stays Control Plane. Expressions without a recognizable guard for a
                    roleAssignments write/delete action are not interpreted - the assignment keeps Control Plane.
                - A recognized GuidEquals allow-list is downgraded to the most privileged tier that its allowed roles
                    classify to at the assignment scope; per-action allow-lists intersect across multiple conditions
                    (assignment + role definition) since the conditions combine with AND at evaluation time.
                - GuidNotEquals deny-lists, unknown role definitions, unsupported condition versions and unrecognized
                    constraints remain Control Plane because they cannot prove all Control Plane delegation is prevented.

        Note: the downgrade targets only the roleAssignments-write/delete portion of the Authorization
        classification. If the same Tier 0 entry also matched other Authorization powers the condition does
        not restrict (e.g. roleDefinitions/write, elevateAccess/action, PIM policy writes - directly or via
        a broad role action such as "*" or "Microsoft.Authorization/*"), the entry is split: those matched
        actions remain Control Plane and only the constrained roleAssignments actions are re-tiered.
        Classification entries that come from the role's own actions (e.g. key/secret read) are left unchanged.
    .PARAMETER Assignment
        The Azure RBAC assignment object. Must expose RoleAssignmentCondition, RoleAssignmentScopeId and a
        Classification array (as produced by Get-EntraOpsPrivilegedEAMAzure Stage 3).
    .PARAMETER ClassificationDefinitions
        The expanded Classification_Azure.json entries (EAMTierLevelName, EAMTierLevelTagValue, Service,
        RoleAssignmentScopeName, ExcludedRoleAssignmentScopeName, RoleDefinitionActions, ExcludedRoleDefinitionActions).
    .PARAMETER RoleDefinitionCache
        Hashtable keyed by role definition GUID with values exposing .properties.permissions[].actions/.dataActions/.notActions/.notDataActions.
    .PARAMETER TierNameByTag
        Hashtable mapping tier tag value (as string, e.g. "0") to the tier name (e.g. "ControlPlane").
    .OUTPUTS
        [array] The (possibly modified) classification array for the assignment.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$Assignment,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$ClassificationDefinitions,

        [Parameter(Mandatory = $true)]
        [hashtable]$RoleDefinitionCache,

        [Parameter(Mandatory = $true)]
        [hashtable]$TierNameByTag
    )

    $Classification = @($Assignment.Classification)
    if ($Classification.Count -eq 0) {
        return $Classification
    }

    # The assignment must contain an Authorization Control Plane (Tier 0) classification to downgrade.
    $AuthorizationEntries = @($Classification | Where-Object {
            "$($_.AdminTierLevel)" -eq "0" -and (
                $_.Service -eq "Authorization" -or
                (@($_.MatchedActions) | Where-Object {
                        -not [string]::IsNullOrEmpty($_) -and (
                            $_ -like "*roleAssignments/write" -or
                            $_ -like "*roleAssignments/delete" -or
                            ($_ -like "Microsoft.Authorization/*" -and ($_ -like "*/write" -or $_ -like "*/delete"))
                        )
                    }).Count -gt 0
            )
        })
    if ($AuthorizationEntries.Count -eq 0) {
        return $Classification
    }

    # --- Parse the RoleDefinitionId constraints from assignment and role-definition conditions ---
    # Azure built-in constrained-delegation roles (for example Key Vault Data Access Administrator)
    # define their ABAC condition on the role definition. An assignment can add another condition.
    $ConditionPattern = "RoleDefinitionId\]\s*\w+:(Guid(?:Not)?Equals)\s*\{([^}]*)\}"
    # Canonical ABAC guard form for role-assignment conditions: "IF the request action is X THEN the
    # RoleDefinitionId constraint applies" is expressed as (!(ActionMatches{'X'})) OR (<constraint>).
    $GuardPattern = "!\s*\(\s*ActionMatches\s*\{\s*'([^']+)'\s*\}\s*\)"
    $ConditionExpressions = [System.Collections.Generic.List[PSCustomObject]]::new()
    if (-not [string]::IsNullOrEmpty($Assignment.RoleAssignmentCondition)) {
        $ConditionExpressions.Add([PSCustomObject]@{ Expression = $Assignment.RoleAssignmentCondition; Version = $Assignment.RoleAssignmentConditionVersion }) | Out-Null
    }
    $AssignedRoleDefinition = $RoleDefinitionCache[$Assignment.RoleDefinitionId]
    foreach ($Permission in @($AssignedRoleDefinition.properties.permissions)) {
        if (-not [string]::IsNullOrEmpty($Permission.condition)) {
            $ConditionExpressions.Add([PSCustomObject]@{ Expression = $Permission.condition; Version = $Permission.conditionVersion }) | Out-Null
        }
    }
    if ($ConditionExpressions.Count -eq 0) {
        return $Classification
    }

    # Allow-list per constrained action ('write'/'delete'). The RoleDefinitionId constraint only
    # applies to the actions named in an expression's negated ActionMatches guards; multiple
    # expressions (assignment + role definition) combine with AND at evaluation time, so per-action
    # allow-lists intersect across expressions.
    $AllowedByAction = @{}
    foreach ($ConditionExpression in $ConditionExpressions) {
        if (-not [string]::IsNullOrEmpty($ConditionExpression.Version) -and $ConditionExpression.Version -ne '2.0') {
            return $Classification
        }
        if ($ConditionExpression.Expression -notlike '*Microsoft.Authorization/roleAssignments*') {
            continue
        }
        $ConditionMatches = [regex]::Matches($ConditionExpression.Expression, $ConditionPattern)
        if ($ConditionMatches.Count -eq 0) {
            return $Classification
        }

        # Which roleAssignments actions does this expression's allow-list actually constrain? Without a
        # recognizable negated guard the boolean structure cannot be interpreted - keep Control Plane
        # (fail closed) instead of assuming the constraint covers both write and delete.
        $GuardedActions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($GuardMatch in [regex]::Matches($ConditionExpression.Expression, $GuardPattern)) {
            $GuardAction = $GuardMatch.Groups[1].Value
            if ($GuardAction -like "*roleAssignments/write") { [void]$GuardedActions.Add('write') }
            elseif ($GuardAction -like "*roleAssignments/delete") { [void]$GuardedActions.Add('delete') }
        }
        if ($GuardedActions.Count -eq 0) {
            return $Classification
        }

        $ConditionAllowedRoleDefIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Match in $ConditionMatches) {
            # A deny-list still permits every role not named in it. Do not downgrade unless
            # the expression proves a closed allow-list of delegable role definitions.
            if ($Match.Groups[1].Value -ieq 'GuidNotEquals') {
                return $Classification
            }
            foreach ($Guid in @($Match.Groups[2].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrEmpty($_) })) {
                [void]$ConditionAllowedRoleDefIds.Add($Guid)
            }
        }
        if ($ConditionAllowedRoleDefIds.Count -eq 0) {
            return $Classification
        }
        foreach ($GuardedAction in $GuardedActions) {
            if (-not $AllowedByAction.ContainsKey($GuardedAction)) {
                # Copy via UnionWith; the 2-arg HashSet ctor fails overload resolution on some pwsh versions.
                $ActionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $ActionSet.UnionWith([string[]]@($ConditionAllowedRoleDefIds))
                $AllowedByAction[$GuardedAction] = $ActionSet
            } else {
                $AllowedByAction[$GuardedAction].IntersectWith([string[]]@($ConditionAllowedRoleDefIds))
            }
        }
    }
    if ($AllowedByAction.Count -eq 0) { return $Classification }

    # --- Control-plane scope guard ---
    # If the assignment scope is itself a concrete (non-wildcard) Tier 0 control-plane scope, keep Control Plane.
    # Only scope patterns without a wildcard count: a wildcard pattern such as "/subscriptions/*" describes the
    # tier of control-plane *actions*, not a specific control-plane resource path.
    $Scope = $Assignment.RoleAssignmentScopeId
    foreach ($ClassEntry in @($ClassificationDefinitions)) {
        if ("$($ClassEntry.EAMTierLevelTagValue)" -ne "0") { continue }
        $ScopePattern = $ClassEntry.RoleAssignmentScopeName
        if ([string]::IsNullOrWhiteSpace($ScopePattern) -or $ScopePattern -eq "/" -or $ScopePattern.Contains("*")) { continue }
        if ($Scope -like $ScopePattern) {
            $IsExcludedScope = $false
            foreach ($ExcludedScope in @($ClassEntry.ExcludedRoleAssignmentScopeName)) {
                if (-not [string]::IsNullOrEmpty($ExcludedScope) -and ($Scope -like $ExcludedScope)) { $IsExcludedScope = $true; break }
            }
            if (-not $IsExcludedScope) {
                # Scope is a concrete control-plane resource; do not downgrade.
                return $Classification
            }
        }
    }

    # --- Local helper: classify a single role definition at the assignment scope (returns tier tags) ---
    $GetRoleTierTags = {
        param($RoleDef, $ScopeId, $Defs)
        $Tags = [System.Collections.Generic.List[int]]::new()
        if ($null -eq $RoleDef) { return $Tags }
        foreach ($ClassEntry in @($Defs)) {
            if (-not ($ScopeId -like $ClassEntry.RoleAssignmentScopeName)) { continue }
            $IsExcludedScope = $false
            foreach ($ExcludedScope in @($ClassEntry.ExcludedRoleAssignmentScopeName)) {
                if (-not [string]::IsNullOrEmpty($ExcludedScope) -and ($ScopeId -like $ExcludedScope)) { $IsExcludedScope = $true; break }
            }
            if ($IsExcludedScope) { continue }

            $IsDataActionRule = "$($ClassEntry.ActionType)" -ieq 'DataAction'
            $TierMatched = $false
            foreach ($ClassAction in @($ClassEntry.RoleDefinitionActions)) {
                if ($TierMatched) { break }
                if ([string]::IsNullOrEmpty($ClassAction)) { continue }
                foreach ($Permission in @($RoleDef.properties.permissions)) {
                    if ($TierMatched) { break }
                    $RoleActions = if ($IsDataActionRule) { @($Permission.dataActions) } else { @($Permission.actions) }
                    $NotRoleActions = if ($IsDataActionRule) { @($Permission.notDataActions) } else { @($Permission.notActions) }
                    foreach ($RoleAction in $RoleActions) {
                        if ([string]::IsNullOrEmpty($RoleAction)) { continue }
                        if ($RoleAction -eq '*/read' -and $ClassAction -ne '*/read') { continue }
                        if ($RoleAction -like $ClassAction -or $ClassAction -like $RoleAction) {
                            $IsExcludedByClassification = @($ClassEntry.ExcludedRoleDefinitionActions | Where-Object {
                                    -not [string]::IsNullOrEmpty($_) -and $RoleAction -like $_
                                }).Count -gt 0
                            if ($IsExcludedByClassification) { continue }
                            $IsNotActioned = $false
                            foreach ($NotAction in $NotRoleActions) {
                                if (-not [string]::IsNullOrEmpty($NotAction) -and ($ClassAction -like $NotAction)) { $IsNotActioned = $true; break }
                            }
                            if (-not $IsNotActioned) { $TierMatched = $true; break }
                        }
                    }
                }
            }
            if ($TierMatched) { [void]$Tags.Add([int]$ClassEntry.EAMTierLevelTagValue) }
        }
        return @($Tags | Select-Object -Unique)
    }

    # --- Determine downgrade tier per constrained action ---
    # An action whose allow-list still reaches a Control Plane role, cannot be fully resolved, or
    # intersected to nothing is effectively unproven and stays Control Plane; only provably-limited
    # actions are re-tiered, to the most privileged tier reachable through their allow-list.
    $DowngradeTagByAction = @{}
    foreach ($ActionName in @($AllowedByAction.Keys)) {
        $ActionAllowedRoleDefIds = $AllowedByAction[$ActionName]
        if ($ActionAllowedRoleDefIds.Count -eq 0) { continue }
        $AllowedTags = [System.Collections.Generic.List[int]]::new()
        $Resolvable = $true
        foreach ($Guid in $ActionAllowedRoleDefIds) {
            $AllowedRoleDefinition = $RoleDefinitionCache[$Guid]
            if ($null -eq $AllowedRoleDefinition) { $Resolvable = $false; break }
            $RoleTags = @(& $GetRoleTierTags $AllowedRoleDefinition $Scope $ClassificationDefinitions)
            if ($RoleTags.Count -eq 0) { $Resolvable = $false; break }
            foreach ($Tag in $RoleTags) { [void]$AllowedTags.Add($Tag) }
        }
        if (-not $Resolvable -or $AllowedTags.Count -eq 0) { continue }
        $ActionTag = ($AllowedTags | Measure-Object -Minimum).Minimum
        if ([int]$ActionTag -le 0) { continue }
        $DowngradeTagByAction[$ActionName] = [int]$ActionTag
    }
    if ($DowngradeTagByAction.Count -eq 0) {
        return $Classification
    }

    # Single conservative downgrade tier: the most privileged tier among the constrained actions.
    $DowngradeTag = ($DowngradeTagByAction.Values | Measure-Object -Minimum).Minimum
    if (-not $TierNameByTag.ContainsKey("$DowngradeTag")) {
        return $Classification
    }
    $WriteConstrained = $DowngradeTagByAction.ContainsKey('write')
    $DeleteConstrained = $DowngradeTagByAction.ContainsKey('delete')

    # --- Apply the downgrade to the constrained roleAssignments actions only ---
    # The ABAC RoleDefinitionId condition constrains solely Microsoft.Authorization/roleAssignments
    # write/delete. Other Authorization powers aggregated in the same Tier 0 entry (roleDefinitions/write,
    # elevateAccess/action, PIM policy/schedule writes) are unaffected by the condition and must stay
    # Control Plane, so entries are split instead of re-tiered wholesale.
    $Changed = $false
    $UpdatedClassification = foreach ($Entry in $Classification) {
        $IsAuthorizationEntry = "$($Entry.AdminTierLevel)" -eq "0" -and (
            $Entry.Service -eq "Authorization" -or
            (@($Entry.MatchedActions) | Where-Object {
                    -not [string]::IsNullOrEmpty($_) -and (
                        $_ -like "*roleAssignments/write" -or
                        $_ -like "*roleAssignments/delete" -or
                        ($_ -like "Microsoft.Authorization/*" -and ($_ -like "*/write" -or $_ -like "*/delete"))
                    )
                }).Count -gt 0
        )
        if (-not $IsAuthorizationEntry) {
            $Entry
            continue
        }

        # Partition the matched classification patterns: a pattern is constrained when every role action
        # granting it is itself a roleAssignments write/delete. A wider grant (e.g. "*",
        # "Microsoft.Authorization/*") keeps powers the condition does not restrict, so such patterns
        # (and patterns unverifiable because the role definition is not cached) remain Control Plane.
        $ConstrainedPatterns = [System.Collections.Generic.List[string]]::new()
        $RemainderPatterns = [System.Collections.Generic.List[string]]::new()
        foreach ($Pattern in @($Entry.MatchedActions)) {
            if ([string]::IsNullOrEmpty($Pattern)) { continue }
            if ($Pattern -like "*roleAssignments/write") {
                if ($WriteConstrained) { $ConstrainedPatterns.Add($Pattern) } else { $RemainderPatterns.Add($Pattern) }
                continue
            }
            if ($Pattern -like "*roleAssignments/delete") {
                if ($DeleteConstrained) { $ConstrainedPatterns.Add($Pattern) } else { $RemainderPatterns.Add($Pattern) }
                continue
            }
            $HasAnyGrant = $false
            $HasUnconstrainedGrant = $false
            foreach ($Permission in @($AssignedRoleDefinition.properties.permissions)) {
                foreach ($RoleAction in @($Permission.actions)) {
                    if ([string]::IsNullOrEmpty($RoleAction)) { continue }
                    if ($RoleAction -eq '*/read' -and $Pattern -ne '*/read') { continue }
                    if ($RoleAction -like $Pattern -or $Pattern -like $RoleAction) {
                        $HasAnyGrant = $true
                        $IsConstrainedGrant = ($RoleAction -like "*roleAssignments/write" -and $WriteConstrained) -or
                            ($RoleAction -like "*roleAssignments/delete" -and $DeleteConstrained)
                        if (-not $IsConstrainedGrant) {
                            $HasUnconstrainedGrant = $true
                        }
                    }
                }
            }
            if ($HasAnyGrant -and -not $HasUnconstrainedGrant) {
                $ConstrainedPatterns.Add($Pattern)
            } else {
                $RemainderPatterns.Add($Pattern)
            }
        }

        if ($ConstrainedPatterns.Count -eq 0) {
            # Nothing in this entry is provably limited by the condition; keep it Control Plane.
            $Entry
            continue
        }

        $Changed = $true
        if ($RemainderPatterns.Count -gt 0) {
            [PSCustomObject]@{
                'AdminTierLevel'             = $Entry.AdminTierLevel
                'AdminTierLevelName'         = $Entry.AdminTierLevelName
                'Service'                    = $Entry.Service
                'MatchedActions'             = @($RemainderPatterns)
                'ScopedObjects'              = $Entry.ScopedObjects
                'TaggedBy'                   = $Entry.TaggedBy
                'TaggedByObjectIds'          = $Entry.TaggedByObjectIds
                'TaggedByObjectDisplayNames' = $Entry.TaggedByObjectDisplayNames
                'TaggedByRoleSystem'         = $Entry.TaggedByRoleSystem
            }
        }
        [PSCustomObject]@{
            'AdminTierLevel'             = "$DowngradeTag"
            'AdminTierLevelName'         = $TierNameByTag["$DowngradeTag"]
            'Service'                    = $Entry.Service
            'MatchedActions'             = @($ConstrainedPatterns)
            'ScopedObjects'              = $Entry.ScopedObjects
            'TaggedBy'                   = "JSONwithConditionInScope"
            'TaggedByObjectIds'          = $Entry.TaggedByObjectIds
            'TaggedByObjectDisplayNames' = $Entry.TaggedByObjectDisplayNames
            'TaggedByRoleSystem'         = $Entry.TaggedByRoleSystem
        }
    }

    if ($Changed) { return @($UpdatedClassification) }
    return $Classification
}
