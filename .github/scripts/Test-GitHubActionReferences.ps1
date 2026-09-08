[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..')
)

$ResolvedRepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
$GitHubPath = Join-Path $ResolvedRepositoryRoot '.github'
if (-not (Test-Path -LiteralPath $GitHubPath -PathType Container)) {
    throw "GitHub configuration path '$GitHubPath' does not exist."
}

$ActionReferences = [System.Collections.Generic.List[object]]::new()
$Violations = [System.Collections.Generic.List[string]]::new()
$YamlFiles = Get-ChildItem -LiteralPath $GitHubPath -Recurse -File | Where-Object {
    $_.Extension -in '.yml', '.yaml'
}

foreach ($YamlFile in $YamlFiles) {
    $LineNumber = 0
    foreach ($Line in [System.IO.File]::ReadLines($YamlFile.FullName)) {
        $LineNumber++
        if ($Line -notmatch '^\s*(?:-\s*)?uses:\s*(?<Reference>[^\s#]+)(?:\s+#\s*(?<Version>\S+))?\s*$') {
            continue
        }

        $LineMatch = $Matches.Clone()
        $Reference = $LineMatch.Reference
        if ($Reference.StartsWith('./')) {
            continue
        }

        $Location = "$($YamlFile.FullName):$LineNumber"
        if ($Reference -notmatch '^(?<Action>[^@\s]+)@(?<Commit>[0-9a-fA-F]{40})$') {
            $Violations.Add("$Location uses mutable or invalid external action reference '$Reference'.")
            continue
        }

        $Action = $Matches.Action
        $Version = $LineMatch.Version
        if ($Version -notmatch '^v\d+(?:\.\d+){0,2}$') {
            $Violations.Add("$Location must annotate '$Reference' with a version comment such as '# v4'.")
        }

        $ActionReferences.Add([pscustomobject]@{
                Action    = $Action
                Reference = $Reference.ToLowerInvariant()
                Version   = $Version
                Location  = $Location
            })
    }
}

foreach ($ActionGroup in $ActionReferences | Group-Object Action) {
    $DistinctReferences = @($ActionGroup.Group.Reference | Sort-Object -Unique)
    if ($DistinctReferences.Count -gt 1) {
        $Locations = $ActionGroup.Group.Location -join ', '
        $Violations.Add("Action '$($ActionGroup.Name)' uses inconsistent pinned commits across: $Locations.")
    }

    $DistinctVersions = @($ActionGroup.Group.Version | Sort-Object -Unique)
    if ($DistinctVersions.Count -gt 1) {
        $Locations = $ActionGroup.Group.Location -join ', '
        $Violations.Add("Action '$($ActionGroup.Name)' uses inconsistent version annotations across: $Locations.")
    }
}

if ($Violations.Count -gt 0) {
    throw "GitHub Action reference validation failed with $($Violations.Count) violation(s):`n$($Violations -join "`n")"
}

Write-Output "Validated $($ActionReferences.Count) immutable GitHub Action reference(s) across $($YamlFiles.Count) YAML file(s)."