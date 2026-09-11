[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$CommitMessage = "EntraOps automated update",

    [Parameter(Mandatory = $false)]
    [string]$BranchName = $env:BUILD_SOURCEBRANCHNAME,

    [Parameter(Mandatory = $false)]
    [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN
)

$ErrorActionPreference = "Continue"

git config user.email "entraops-ado@dev.azure.com"
git config user.name "Azure DevOps"

git add --all
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git add failed or nothing to add."
    exit 0
}

git diff-index --quiet HEAD
if ($LASTEXITCODE -eq 0) {
    Write-Host "No changes to commit."
    exit 0
}

git commit -m "$CommitMessage [skip ci]"
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git commit failed."
    exit 0
}

git -c http.extraheader="AUTHORIZATION: bearer $AccessToken" push origin HEAD:$BranchName
if ($LASTEXITCODE -ne 0) {
    Write-Error "git push failed."
    exit 1
}

Write-Host "Successfully pushed changes to $BranchName."
