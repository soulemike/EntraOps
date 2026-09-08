<#
.SYNOPSIS
    Loads scope-reasoning artifacts that can be matched to EAM Dashboard role assignments.
#>

function Import-EntraOpsDashboardScopeReasoning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $classificationRoot = Join-Path -Path $RepoRoot -ChildPath 'Classification'
    if (-not (Test-Path -LiteralPath $classificationRoot -PathType Container)) {
        return , @()
    }

    $scopeReasoning = [System.Collections.Generic.List[object]]::new()
    $systems = @{
        'ScopeReasoning_Azure.json'              = 'Azure'
        'ScopeReasoning_EntraID.json'            = 'EntraID'
        'ScopeReasoning_IdentityGovernance.json' = 'IdentityGovernance'
    }

    foreach ($fileName in $systems.Keys) {
        $roleSystem = $systems[$fileName]
        foreach ($reasoningFile in @(Get-ChildItem -LiteralPath $classificationRoot -Filter $fileName -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
            try {
                $payload = Get-Content -LiteralPath $reasoningFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Write-Warning "Could not parse scope reasoning file '$($reasoningFile.FullName)': $($_.Exception.Message)"
                continue
            }

            foreach ($detail in @($payload.ScopeDetails)) {
                if ($null -eq $detail) { continue }
                foreach ($scopeId in @($detail.ScopeId)) {
                    if ([string]::IsNullOrWhiteSpace("$scopeId")) { continue }
                    $scopeReasoning.Add([PSCustomObject]@{
                            RoleSystem              = $roleSystem
                            ScopeId                 = "$scopeId"
                            ScopeName               = "$($detail.ScopeName)"
                            Source                  = "$($detail.Source)"
                            EAMTier                 = "$($detail.EAMTier)"
                            ResultingScope          = "$($detail.ResultingScope)"
                            TierSource              = "$($detail.TierSource)"
                            TierEvidence            = @($detail.TierEvidence)
                            Reason                  = "$($detail.Reason)"
                            CriticalityLevel        = "$($detail.CriticalityLevel)"
                            CriticalityRules        = "$($detail.CriticalityRules)"
                            ManagedIdentityObjectId = "$($detail.ManagedIdentityObjectId)"
                            ScopeCategory           = "$($detail.ScopeCategory)"
                            ScopeType               = "$($detail.ScopeType)"
                            CatalogDisplayName      = "$($detail.CatalogDisplayName)"
                            ClassifiedResources     = @($detail.ClassifiedResources)
                            ExpandedScopePaths      = @($detail.ExpandedScopePaths)
                            AffectedObjects         = @($detail.AffectedObjects)
                        })
                }
            }
        }
    }

    foreach ($reasoningFile in @(Get-ChildItem -LiteralPath $classificationRoot -Filter 'ScopeReasoning_Defender.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        try {
            $payload = Get-Content -LiteralPath $reasoningFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning "Could not parse Defender scope reasoning file '$($reasoningFile.FullName)': $($_.Exception.Message)"
            continue
        }

        foreach ($detail in @($payload.CloudSetDetails)) {
            if ($null -eq $detail -or [string]::IsNullOrWhiteSpace("$($detail.CloudSetId)")) { continue }
            $scopeReasoning.Add([PSCustomObject]@{
                    RoleSystem              = 'Defender'
                    ScopeId                 = "$($detail.CloudSetId)"
                    ScopeName               = "$($detail.CloudSetName)"
                    Source                  = 'Defender CloudSet'
                    EAMTier                 = $(if ($detail.ResultingScope -eq 'Tier0') { 'ControlPlane' } elseif ($detail.ResultingScope -eq 'Tier1') { 'ManagementPlane' } else { 'Unclassified' })
                    ResultingScope          = "$($detail.ResultingScope)"
                    TierSource              = 'ScopeReasoning_Defender'
                    TierEvidence            = @()
                    Reason                  = "$($detail.Reason)"
                    CriticalityLevel        = ''
                    CriticalityRules        = ''
                    ManagedIdentityObjectId = ''
                    ScopeCategory           = 'CloudSet'
                    ScopeType               = 'CloudSet'
                    CatalogDisplayName      = ''
                    ClassifiedResources     = @()
                    ExpandedScopePaths      = @()
                    AffectedObjects         = @()
                    ResolutionStatus        = "$($detail.ResolutionStatus)"
                    SubscriptionScopes      = @($detail.SubscriptionScopes)
                    Tier0SubscriptionScopes = @($detail.Tier0SubscriptionScopes)
                    Tier1SubscriptionScopes = @($detail.Tier1SubscriptionScopes)
                    AzureScopeEvidence      = @($detail.AzureScopeEvidence)
                })
        }
    }

    foreach ($reasoningFile in @(Get-ChildItem -LiteralPath $classificationRoot -Filter 'ScopeReasoning_DeviceManagement.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        try {
            $payload = Get-Content -LiteralPath $reasoningFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $membersFile = Join-Path $reasoningFile.DirectoryName 'DeviceManagement_ScopeGroupDeviceMembers.json'
            $membersPayload = if (Test-Path -LiteralPath $membersFile -PathType Leaf) {
                Get-Content -LiteralPath $membersFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            } else { $null }
        } catch {
            Write-Warning "Could not parse Device Management scope reasoning near '$($reasoningFile.FullName)': $($_.Exception.Message)"
            continue
        }

        foreach ($group in @($payload.Groups)) {
            if ($null -eq $group -or [string]::IsNullOrWhiteSpace("$($group.GroupId)")) { continue }
            $memberEntry = if ($null -ne $membersPayload) { $membersPayload.groupDeviceMembers.PSObject.Properties["$($group.GroupId)"].Value } else { $null }
            foreach ($tierDescriptor in @($group.EAMTierLevelName)) {
                $tierMatch = [regex]::Match("$tierDescriptor", '^(ControlPlane|ManagementPlane|WorkloadPlane|UserAccess)(?:\s+\(([^)]+)\))?$')
                if (-not $tierMatch.Success) { continue }
                $tierName = $tierMatch.Groups[1].Value
                $scopeType = $tierMatch.Groups[2].Value
                $tierEvidence = [System.Collections.Generic.List[string]]::new()
                $tierEvidence.Add("Scope group classification: $tierDescriptor") | Out-Null
                if ([bool]$group.IncludedInScopeTagFilter) {
                    $tierEvidence.Add("Matched Intune scope tag filter: $($group.MatchedIntuneScopeTags)") | Out-Null
                }
                $scopeReasoning.Add([PSCustomObject]@{
                        RoleSystem              = 'DeviceManagement'
                        ScopeId                 = "$($group.GroupId)"
                        ScopeName               = "$($group.GroupName)"
                        Source                  = 'Device Management scope reasoning'
                        EAMTier                 = $tierName
                        ResultingScope          = ''
                        TierSource              = 'ScopeReasoning_DeviceManagement'
                        TierEvidence            = @($tierEvidence)
                        Reason                  = "Intune scope group contributes $tierName access through classified $scopeType members."
                        CriticalityLevel        = ''
                        CriticalityRules        = ''
                        ManagedIdentityObjectId = ''
                        ScopeCategory           = 'Intune scope group'
                        ScopeType               = $scopeType
                        CatalogDisplayName      = ''
                        ClassifiedResources     = @()
                        ExpandedScopePaths      = @()
                        AffectedObjects         = $(if ($null -ne $memberEntry) { @($memberEntry.deviceMembers) } else { @() })
                    })
            }
        }
    }

    return , @($scopeReasoning)
}