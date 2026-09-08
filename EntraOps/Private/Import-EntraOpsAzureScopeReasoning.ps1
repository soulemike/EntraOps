<#
.SYNOPSIS
    Loads Azure resource scope reasoning created during classification generation.
#>

function Import-EntraOpsAzureScopeReasoning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $classificationRoot = Join-Path -Path $RepoRoot -ChildPath 'Classification'
    if (-not (Test-Path -LiteralPath $classificationRoot -PathType Container)) {
        return , @()
    }

    $scopeReasoningDetails = [System.Collections.Generic.List[object]]::new()
    $reasoningFiles = @(Get-ChildItem -LiteralPath $classificationRoot -Filter 'ScopeReasoning_Azure.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)

    foreach ($reasoningFile in $reasoningFiles) {
        try {
            $payload = Get-Content -LiteralPath $reasoningFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning "Could not parse Azure scope reasoning file '$($reasoningFile.FullName)': $($_.Exception.Message)"
            continue
        }

        # ScopeDetails with ScopeName/ScopeId (aligned with ScopeReasoning_IdentityGovernance.json)
        foreach ($detail in @($payload.ScopeDetails)) {
            if ($null -ne $detail -and -not [string]::IsNullOrWhiteSpace("$($detail.ScopeId)")) {
                $scopeReasoningDetails.Add($detail)
            }
        }
    }

    return , @($scopeReasoningDetails)
}

function Find-EntraOpsAzureScopeReasoning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ScopeReasoningDetails,

        [Parameter(Mandatory = $true)]
        [string]$ScopeId
    )

    $normalizedScopeId = $ScopeId.Trim().TrimEnd('/').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalizedScopeId)) {
        return , @()
    }

    $matchingDetails = foreach ($detail in $ScopeReasoningDetails) {
        if ($null -eq $detail) { continue }

        $detailScopeId = "$($detail.ScopeId)".Trim().TrimEnd('/').ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($detailScopeId)) { continue }

        $expandedScopePaths = if ($detail.PSObject.Properties.Name -contains 'ExpandedScopePaths') {
            @($detail.ExpandedScopePaths | ForEach-Object { "$_".Trim().TrimEnd('/').ToLowerInvariant() })
        } else {
            @()
        }

        if ($detailScopeId -eq $normalizedScopeId -or
            $detailScopeId.StartsWith("$normalizedScopeId/", [System.StringComparison]::OrdinalIgnoreCase) -or
            $expandedScopePaths -contains $normalizedScopeId) {
            $detail
        }
    }

    return , @($matchingDetails | Sort-Object ScopeName, ScopeId -Unique)
}