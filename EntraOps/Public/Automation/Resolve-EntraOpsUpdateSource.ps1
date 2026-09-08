function Resolve-EntraOpsUpdateSource {
<#
.SYNOPSIS
    Resolves an EntraOps update source against the local distribution repository catalog.

.DESCRIPTION
    The trusted local EntraOpsUpdateContract.json is the single place that declares which
    Cloud-Architekt repositories distribute EntraOps and whether they require a Personal Access
    Token (private Insiders channel) or not (public release channel). Update-EntraOps and the
    Update-EntraOps workflow call this command before any clone so the credential decision is made
    from local, reviewed data and never from the downloaded candidate.
#>
[CmdletBinding()]
param (
    # Repository name below the Cloud-Architekt organization, or the full Owner/Name.
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Repository,

    [Parameter(Mandatory = $false)]
    [string]$ContractPath = (Join-Path $EntraOpsBaseFolder 'EntraOpsUpdateContract.json')
)

$ErrorActionPreference = 'Stop'

if ($Repository -match '^(?<Owner>[A-Za-z0-9_.-]+)/(?<Name>[A-Za-z0-9_.-]+)$') {
    $Owner = $Matches.Owner
    $RepositoryName = $Matches.Name
} elseif ($Repository -match '^[A-Za-z0-9_.-]+$') {
    $Owner = 'Cloud-Architekt'
    $RepositoryName = $Repository
} else {
    throw "Unsupported automated-update repository name '$Repository'. Provide only a repository name in the Cloud-Architekt organization."
}
if ($Owner -ne 'Cloud-Architekt') {
    throw "Unsupported automated-update repository owner '$Owner'. Only repositories in the Cloud-Architekt organization are supported."
}
$FullName = "$Owner/$RepositoryName"

$ContractPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ContractPath)
if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    throw "Local update contract '$ContractPath' was not found. It declares the supported distribution repositories; restore ./EntraOpsUpdateContract.json from the EntraOps release before updating."
}
try {
    $Contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Local update contract '$ContractPath' is not valid JSON: $_"
}

$Catalog = [ordered]@{}
foreach ($Property in @($Contract.DistributionRepositories.PSObject.Properties)) {
    $Catalog[$Property.Name] = $Property.Value
}
$CatalogEntry = $null
foreach ($Key in $Catalog.Keys) {
    if ($Key -eq $FullName) { $CatalogEntry = $Catalog[$Key]; $FullName = $Key; break }
}

if ($null -ne $CatalogEntry) {
    $RequiresPat = [bool]$CatalogEntry.RequiresPersonalAccessToken
    $Visibility = if ($CatalogEntry.Visibility) { [string]$CatalogEntry.Visibility } elseif ($RequiresPat) { 'Private' } else { 'Public' }
    $Channel = if ($CatalogEntry.Channel) { [string]$CatalogEntry.Channel } else { $RepositoryName }
} else {
    Write-Warning "Repository '$FullName' is not a known EntraOps distribution repository ($(@($Catalog.Keys) -join ', ')). It is accepted only when it publishes a matching EntraOpsUpdateContract.json; a Personal Access Token is used when one is provided."
    $RequiresPat = $false
    $Visibility = 'Unknown'
    $Channel = 'Custom'
}

[pscustomobject]@{
    Repository                    = $FullName
    RepositoryName                = $RepositoryName
    RepositoryUrl                 = "https://github.com/$FullName.git"
    Channel                       = $Channel
    Visibility                    = $Visibility
    RequiresPersonalAccessToken   = $RequiresPat
    IsKnownDistributionRepository = ($null -ne $CatalogEntry)
    KnownDistributionRepositories = @($Catalog.Keys)
}
}
