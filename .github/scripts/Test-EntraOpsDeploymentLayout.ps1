[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..')
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
$ActiveConfig = Join-Path $RepositoryRoot 'EntraOpsConfig.json'
$WorkflowRoot = Join-Path $RepositoryRoot '.github/workflows'
$TemplateNotice = Join-Path $RepositoryRoot 'workflows-templates/README.md'

if (-not (Test-Path -LiteralPath $ActiveConfig -PathType Leaf)) {
    throw "Active deployment configuration is missing: $ActiveConfig"
}
if (-not (Test-Path -LiteralPath $WorkflowRoot -PathType Container)) {
    throw "Active workflow directory is missing: $WorkflowRoot"
}
if ((Test-Path -LiteralPath (Join-Path $RepositoryRoot 'workflows-templates') -PathType Container) -and
    -not (Test-Path -LiteralPath $TemplateNotice -PathType Leaf)) {
    throw 'workflows-templates exists without a README that marks the directory as reference-only.'
}

$Violations = [System.Collections.Generic.List[string]]::new()
foreach ($Workflow in @(Get-ChildItem -LiteralPath $WorkflowRoot -File -Include '*.yml', '*.yaml')) {
    $Content = Get-Content -LiteralPath $Workflow.FullName -Raw
    foreach ($AlternativeConfig in @('EntraOpsConfig-Azure.json', 'EntraOpsConfig-Sp.json')) {
        if ($Content -match [regex]::Escape($AlternativeConfig)) {
            $Violations.Add("$($Workflow.Name) references compatibility example $AlternativeConfig.")
        }
    }
}
if ($Violations.Count -gt 0) {
    throw "Deployment layout validation failed:`n$($Violations -join "`n")"
}

$WorkflowCount = @(Get-ChildItem -LiteralPath $WorkflowRoot -File -Include '*.yml', '*.yaml').Count
Write-Output "Validated active configuration and $WorkflowCount active workflow file(s); compatibility configs and workflow templates are not referenced."
