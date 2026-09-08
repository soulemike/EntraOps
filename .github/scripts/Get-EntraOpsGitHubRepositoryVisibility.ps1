#Requires -Version 7.4
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Repository = $env:GITHUB_REPOSITORY,

    [Parameter(Mandatory = $false)]
    [string]$GitHubOutputPath = $env:GITHUB_OUTPUT
)

$ErrorActionPreference = 'Stop'
$Private = (& gh api "repos/$Repository" --jq .private).Trim()
if ($LASTEXITCODE -ne 0) { throw "Failed to read GitHub repository visibility for '$Repository'." }
if (-not [string]::IsNullOrWhiteSpace($GitHubOutputPath)) {
    "private=$Private" | Out-File -LiteralPath $GitHubOutputPath -Append -Encoding utf8
}
if ($Private -ne 'true') {
    Write-Warning 'Repository is public - report artifact upload and release publishing are disabled to avoid disclosing tenant data.'
}
[pscustomobject]@{ Repository = $Repository; Private = $Private -eq 'true' }
