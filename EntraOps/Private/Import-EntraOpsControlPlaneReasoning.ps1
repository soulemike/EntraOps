function Import-EntraOpsControlPlaneReasoning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $classificationRoot = Join-Path -Path $RepoRoot -ChildPath 'Classification'
    if (-not (Test-Path -LiteralPath $classificationRoot -PathType Container)) {
        return , @()
    }

    $reasoningObjects = [System.Collections.Generic.List[object]]::new()
    $reasoningFiles = @(Get-ChildItem -LiteralPath $classificationRoot -Filter 'ScopeReasoning_ControlPlane.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)

    foreach ($reasoningFile in $reasoningFiles) {
        try {
            $payload = Get-Content -LiteralPath $reasoningFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 10 -ErrorAction Stop
        } catch {
            Write-Warning "Could not parse Control Plane reasoning file '$($reasoningFile.FullName)': $($_.Exception.Message)"
            continue
        }

        foreach ($privilegedObject in @($payload.PrivilegedObjects)) {
            if ($null -ne $privilegedObject -and -not [string]::IsNullOrWhiteSpace("$($privilegedObject.ObjectId)")) {
                $reasoningObjects.Add($privilegedObject)
            }
        }
    }

    return , @($reasoningObjects)
}

function Find-EntraOpsControlPlaneReasoning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ReasoningObjects,

        [Parameter(Mandatory = $true)]
        [string]$ObjectId
    )

    if ([string]::IsNullOrWhiteSpace($ObjectId)) { return , @() }
    return , @($ReasoningObjects | Where-Object { "$($_.ObjectId)" -ieq $ObjectId })
}