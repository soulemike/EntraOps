#Requires -Version 7.0
<#
.SYNOPSIS
    Embeds the EntraOps Docs Markdown content into a JS bundle consumed by the Docs pages.
.DESCRIPTION
    All EntraOps Docs content is authored and maintained as plain Markdown:
    - Docs/content/*.md (overview, get-started, core, privileged-eam, reportings)
    - the repository root CHANGELOG.md (single source of truth for the Changelog page,
      not duplicated as a separate Markdown file under Docs/content)

    Since the Docs pages are static, self-contained HTML/JS that must keep working fully
    offline from file:// (no backend, no fetch()/build step at view time - same convention
    as the Reports/* reporting apps and their content/attack-paths/*.md -> data/attack-paths.js
    embedding), this script embeds every Markdown source as a plain JS string bundle:
    Docs/data/content.js, exposing window.EODOCS_CONTENT. Docs/js/markdown.js then renders it
    to HTML in the browser at view time.

    Re-run this script after editing any Markdown source file (Docs/content/*.md or
    CHANGELOG.md) so Docs/data/content.js stays in sync.
.PARAMETER RepoRoot
    Path to the repository root. Defaults to the parent of this script's folder (Docs/).
.PARAMETER DeploymentMode
    EntraOps preserves repository-relative links for a complete local checkout. Standalone rewrites
    links that leave the Docs folder to canonical GitHub URLs for public web deployment.
.PARAMETER RepositoryUrl
    Repository base URL used when DeploymentMode is Standalone.
.PARAMETER RepositoryBranch
    Repository branch used when DeploymentMode is Standalone.
.EXAMPLE
    ./Docs/Update-EntraOpsDocsContent.ps1
.EXAMPLE
    ./Docs/Update-EntraOpsDocsContent.ps1 -DeploymentMode Standalone

    Generates the public-web bundle without links that depend on a local repository checkout.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [ValidateSet('EntraOps', 'Standalone')]
    [string]$DeploymentMode = 'EntraOps',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^https://')]
    [string]$RepositoryUrl = 'https://github.com/Cloud-Architekt/EntraOps',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryBranch = 'main'
)

$DocsFolder = Join-Path -Path $RepoRoot -ChildPath "Docs"
$ContentFolder = Join-Path -Path $DocsFolder -ChildPath "content"
$DataFolder = Join-Path -Path $DocsFolder -ChildPath "data"
$ChangelogPath = Join-Path -Path $RepoRoot -ChildPath "CHANGELOG.md"

if (-not (Test-Path -Path $ContentFolder)) {
    throw "Markdown content folder not found: $ContentFolder"
}
if (-not (Test-Path -Path $DataFolder)) {
    New-Item -Path $DataFolder -ItemType Directory -Force | Out-Null
}

function ConvertTo-StandaloneContent {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Markdown
    )

    $RepositoryBase = $RepositoryUrl.TrimEnd('/')
    return [regex]::Replace(
        $Markdown,
        '(?<Prefix>!?\[[^\]]*\]\()(?<Url>\.\./\.\./[^)\s]+)(?<Suffix>\))',
        {
            param($Match)

            $RepositoryPath = $Match.Groups['Url'].Value.Substring(6).TrimStart('/')
            $TargetUrl = if ($RepositoryPath -match '^(?<Directory>.+)/index\.html$') {
                "$RepositoryBase/tree/$RepositoryBranch/$($Matches.Directory)"
            } else {
                "$RepositoryBase/blob/$RepositoryBranch/$RepositoryPath"
            }
            return $Match.Groups['Prefix'].Value + $TargetUrl + $Match.Groups['Suffix'].Value
        },
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

$Content = [ordered]@{}
Get-ChildItem -Path $ContentFolder -Filter "*.md" | Sort-Object Name | ForEach-Object {
    $Key = $_.BaseName
    Write-Host "  Embedding Docs/content/$($_.Name) -> `$EODOCS_CONTENT.$Key" -ForegroundColor DarkGreen
    $Markdown = Get-Content -Raw -Path $_.FullName
    $Content[$Key] = if ($DeploymentMode -eq 'Standalone') { ConvertTo-StandaloneContent -Markdown $Markdown } else { $Markdown }
}

if (Test-Path -Path $ChangelogPath) {
    Write-Host "  Embedding CHANGELOG.md -> `$EODOCS_CONTENT.changelog" -ForegroundColor DarkGreen
    $ChangelogMarkdown = Get-Content -Raw -Path $ChangelogPath
    $Content["changelog"] = if ($DeploymentMode -eq 'Standalone') { ConvertTo-StandaloneContent -Markdown $ChangelogMarkdown } else { $ChangelogMarkdown }
} else {
    # Older deployment repositories may only have the previously generated embedded changelog.
    # Preserve it rather than replacing a complete offline history during an unrelated docs build.
    $ExistingBundlePath = Join-Path -Path $DataFolder -ChildPath 'content.js'
    $ExistingChangelog = $null
    if (Test-Path -LiteralPath $ExistingBundlePath -PathType Leaf) {
        try {
            $ExistingBundle = Get-Content -LiteralPath $ExistingBundlePath -Raw
            $ExistingMatch = [regex]::Match($ExistingBundle, 'window\.EODOCS_CONTENT\s*=\s*(?<Json>\{.*\});\s*$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($ExistingMatch.Success) {
                $ExistingContent = $ExistingMatch.Groups['Json'].Value | ConvertFrom-Json -Depth 20
                $ExistingChangelog = [string]$ExistingContent.changelog
            }
        } catch {
            Write-Warning "Could not preserve the embedded changelog from $ExistingBundlePath. Error: $($_.Exception.Message)"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExistingChangelog)) {
        $Content['changelog'] = $ExistingChangelog
        Write-Warning "CHANGELOG.md not found at $ChangelogPath - preserving the existing embedded changelog. Add CHANGELOG.md to make future generation independently reproducible."
    } else {
        $Content['changelog'] = "# Change Log`n`nThe changelog is not available in this repository. See the [EntraOps releases](https://github.com/Cloud-Architekt/EntraOps/blob/main/CHANGELOG.md).`n"
        Write-Warning "CHANGELOG.md not found at $ChangelogPath and no embedded changelog could be recovered."
    }
}

$Json = $Content | ConvertTo-Json -Depth 5
$Header = "// Generated by Docs/Update-EntraOpsDocsContent.ps1 for $DeploymentMode deployment - do not edit directly.`n" +
"// Edit the Markdown sources instead (Docs/content/*.md, repository root CHANGELOG.md)`n" +
"// and re-run that script.`n"
$OutputPath = Join-Path -Path $DataFolder -ChildPath "content.js"
$ModeJson = $DeploymentMode | ConvertTo-Json -Compress
Set-Content -Path $OutputPath -Value "$Header`nwindow.EODOCS_DEPLOYMENT_MODE = $ModeJson;`nwindow.EODOCS_CONTENT = $Json;`n" -NoNewline:$false -Encoding utf8

Write-Host "Wrote $OutputPath ($DeploymentMode deployment)" -ForegroundColor Cyan
