#Requires -Version 7.4
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$CandidateRoot,

    [Parameter(Mandatory = $false)]
    [switch]$RunBrowserTests,

    [Parameter(Mandatory = $false)]
    [string]$ArchivePath,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedArchiveSha256
)

$ErrorActionPreference = 'Stop'
$CandidateRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CandidateRoot)
if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ArchivePath)
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Update candidate archive '$ArchivePath' does not exist."
    }
    $ActualDigest = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedArchiveSha256 -and $ActualDigest -ne $ExpectedArchiveSha256.ToLowerInvariant()) {
        throw "Transferred candidate digest '$ActualDigest' does not match the resolved archive digest."
    }
    if (Test-Path -LiteralPath $CandidateRoot) {
        throw "Update candidate root '$CandidateRoot' already exists before archive extraction."
    }
    New-Item -ItemType Directory -Path $CandidateRoot -ErrorAction Stop | Out-Null
    & tar -xf $ArchivePath -C $CandidateRoot
    if ($LASTEXITCODE -ne 0) { throw "Candidate extraction failed with exit code $LASTEXITCODE." }
}
if (-not (Test-Path -LiteralPath $CandidateRoot -PathType Container)) {
    throw "Update candidate root '$CandidateRoot' does not exist."
}

$Results = [System.Collections.Generic.List[object]]::new()
function Add-ValidationResult {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $Results.Add([pscustomobject]@{ Name = $Name; Status = 'Passed' })
}

function Get-CandidateFingerprint {
    $ExcludedDirectoryNames = @('.git', 'node_modules', 'playwright-report', 'test-results')
    return @(Get-ChildItem -LiteralPath $CandidateRoot -File -Recurse | Where-Object {
            $RelativePath = [System.IO.Path]::GetRelativePath($CandidateRoot, $_.FullName)
            $Segments = $RelativePath -split '[\\/]'
            @($Segments | Where-Object { $ExcludedDirectoryNames -contains $_ }).Count -eq 0
        } | ForEach-Object {
            $RelativePath = [System.IO.Path]::GetRelativePath($CandidateRoot, $_.FullName).Replace('\', '/')
            "$RelativePath`t$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        } | Sort-Object)
}

$InitialFingerprint = Get-CandidateFingerprint

Push-Location $CandidateRoot
try {
    # Order matters: every check that only reads the candidate runs before the first check that
    # executes candidate code. Once Import-Module has run, candidate code shares this process and a
    # writable workspace, so it could replace a validator script that runs later.
    Add-ValidationResult 'Module manifest' {
        # Test-ModuleManifest parses the restricted-language data file; it does not run the module.
        Test-ModuleManifest -Path './EntraOps/EntraOps.psd1' -ErrorAction Stop | Out-Null
    }
    Add-ValidationResult 'Immutable GitHub Action references' {
        # Use the validator from the trusted deployment checkout, before any candidate code has run.
        # The candidate must not be able to replace the policy that decides whether its own action
        # references are acceptable.
        & (Join-Path $PSScriptRoot 'Test-GitHubActionReferences.ps1') -RepositoryRoot $CandidateRoot | Out-Host
    }
    Add-ValidationResult 'Module import' {
        Import-Module './EntraOps/EntraOps.psd1' -Force -ErrorAction Stop
    }
    Add-ValidationResult 'Generated documentation' {
        $GeneratedDocsPath = Join-Path $CandidateRoot 'Docs/data/content.js'
        $GeneratedDocsHash = (Get-FileHash -LiteralPath $GeneratedDocsPath -Algorithm SHA256).Hash
        & './Docs/Update-EntraOpsDocsContent.ps1' -RepoRoot $CandidateRoot | Out-Host
        if ((Get-FileHash -LiteralPath $GeneratedDocsPath -Algorithm SHA256).Hash -ne $GeneratedDocsHash) {
            throw 'Docs/data/content.js is not synchronized with its Markdown and changelog sources.'
        }
    }
    Add-ValidationResult 'Pester regression suite' {
        if (-not (Get-Command Invoke-Pester -ErrorAction SilentlyContinue)) {
            throw 'Pester is required to validate an EntraOps update candidate.'
        }
        $PesterResult = Invoke-Pester -Path './Tests' -Output Normal -PassThru
        if ($null -eq $PesterResult -or $PesterResult.FailedCount -gt 0 -or $PesterResult.TotalCount -eq 0) {
            throw "Pester failed: $($PesterResult.FailedCount) failed of $($PesterResult.TotalCount) tests."
        }
    }

    if ($RunBrowserTests) {
        Add-ValidationResult 'Browser and report smoke tests' {
            foreach ($RequiredPath in @('./package.json', './package-lock.json', './playwright.config.mjs')) {
                if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
                    throw "Browser validation requires $RequiredPath in the update candidate."
                }
            }
            & npm ci
            if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE." }
            & npx playwright install --with-deps chromium
            if ($LASTEXITCODE -ne 0) { throw "Playwright Chromium installation failed with exit code $LASTEXITCODE." }
            & npm run test:browser
            if ($LASTEXITCODE -ne 0) { throw "Browser tests failed with exit code $LASTEXITCODE." }
        }
    }
    Add-ValidationResult 'Candidate sources remain unchanged after validation' {
        $FinalFingerprint = Get-CandidateFingerprint
        $FingerprintChanges = @(Compare-Object -ReferenceObject $InitialFingerprint -DifferenceObject $FinalFingerprint)
        if ($FingerprintChanges.Count -gt 0) {
            throw "Candidate validation modified source files:`n$($FingerprintChanges.InputObject -join "`n")"
        }
    }
} finally {
    Pop-Location
}

return @($Results)
