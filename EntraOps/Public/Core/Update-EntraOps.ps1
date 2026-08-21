<#
.SYNOPSIS
    Update of EntraOps PowerShell module and CI/CD pipeline files.

.DESCRIPTION
    Cmdlet is used to update the EntraOps PowerShell module and pipeline files from an upstream repository.
    Defaults to the GitHub upstream (Cloud-Architekt/EntraOps); use -UpstreamUrl to clone from Azure DevOps or another Git remote.

.EXAMPLE
    This example updates EntraOps with default values of the main branch and the default target folders.
    Update-EntraOps

.EXAMPLE
    Update from an Azure DevOps Git mirror instead of the default GitHub upstream.
    Update-EntraOps -UpstreamUrl "https://dev.azure.com/my-org/my-project/_git/entraOps"
#>

function Update-EntraOps {
    [cmdletbinding()]
    param (
    [Parameter(Mandatory = $False)]
    [System.String]$Branch = "main"
    ,
    [Parameter(Mandatory = $False)]
    [System.String]$Repository = "EntraOps"
    ,
    [Parameter(Mandatory = $False)]
    [System.String]$UpstreamUrl
    ,
        [Parameter(Mandatory = $False)]
        [System.String]$PersonalAccessToken
        ,
        [Parameter(Mandatory = $False)]
        [System.String]$ConfigFile = "./EntraOpsConfig.json"
        ,
        [Parameter(Mandatory = $False)]
        [ValidateSet("./.github", "./.github/agents", "./EntraOps", "./Parsers", "./Queries", "./Samples", "./Workbooks")]
        [Object]$TargetUpdateFolders = @("./.github", "./.github/agents", "./EntraOps", "./Parsers", "./Queries", "./Samples", "./Workbooks")
        ,
        [Parameter(Mandatory = $False)]
        [System.String]$TemporaryUpdateFolder = "TmpUpdate"
    )

    $ErrorActionPreference = "Stop"

    if ([string]::IsNullOrWhiteSpace($UpstreamUrl)) {
        $UpstreamUrl = "https://github.com/Cloud-Architekt/$($Repository).git"
    }

    if ([string]::IsNullOrWhiteSpace($PersonalAccessToken) -and -not [string]::IsNullOrWhiteSpace($env:ENTRAOPS_PAT)) {
        $PersonalAccessToken = $env:ENTRAOPS_PAT
    }

    if (-not [string]::IsNullOrWhiteSpace($PersonalAccessToken)) {
        Write-Output "Cloning repository '$UpstreamUrl' (branch: $Branch) using Personal Access Token..."
        # Pass credentials via environment-based HTTP header to avoid exposing the PAT in process listings, logs, or error messages
        $PreviousConfigCount = $env:GIT_CONFIG_COUNT
        $PreviousConfigKey0 = $env:GIT_CONFIG_KEY_0
        $PreviousConfigValue0 = $env:GIT_CONFIG_VALUE_0
        $UpstreamHost = ([System.Uri]$UpstreamUrl).Host
        try {
            $env:GIT_CONFIG_COUNT = "1"
            $env:GIT_CONFIG_KEY_0 = "http.https://$UpstreamHost/.extraheader"
            $env:GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$PersonalAccessToken")))"
            git clone -b $Branch $UpstreamUrl $TemporaryUpdateFolder
        } finally {
            # Restore previous env state
            if ($null -eq $PreviousConfigCount) { Remove-Item env:GIT_CONFIG_COUNT -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_COUNT = $PreviousConfigCount }
            if ($null -eq $PreviousConfigKey0) { Remove-Item env:GIT_CONFIG_KEY_0 -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_KEY_0 = $PreviousConfigKey0 }
            if ($null -eq $PreviousConfigValue0) { Remove-Item env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_VALUE_0 = $PreviousConfigValue0 }
        }
    } else {
        Write-Output "Cloning repository '$UpstreamUrl' (branch: $Branch) without authentication..."
        git clone -b $Branch $UpstreamUrl $TemporaryUpdateFolder
    }

    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE. Verify the upstream URL, branch, and whether a Personal Access Token (secret: EntraOpsUpdatePat) is required for private repositories."
    }

    foreach ($TargetUpdateFolder in $TargetUpdateFolders) {

        if (Test-Path -Path $TargetUpdateFolder) {
            Write-Output "Removing folder $TargetUpdateFolder..."
            try {
                Remove-Item -Path $TargetUpdateFolder -Force -Recurse
            } catch {
                Write-Error "Failed to remove folder $($TargetUpdateFolder). Error: $_"
            }
        }

        Write-Output "Updating folder $TargetUpdateFolder..."
        try {
            Copy-item -Path "$($TemporaryUpdateFolder)/$($TargetUpdateFolder)" -Destination "$($TargetUpdateFolder)" -Force -Recurse
        } catch {
            Write-Error "Failed to copy folder $($TemporaryUpdateFolder)/$($TargetUpdateFolder) to $($TargetUpdateFolder). Error: $_"
        }
    }

    Write-Output "Importing updated EntraOps module..."
    try {
        Import-Module ./EntraOps -Force
    } catch {
        Write-Error "Failed to import updated EntraOps module. Error: $_"
    }

    if ($TargetUpdateFolders -contains "./.github") {
        Write-Host "Re-adding workflow parameters in GitHub workflows after update..."
        try {
            Update-EntraOpsRequiredWorkflowParameters -ConfigFile $ConfigFile
        } catch {
            Write-Error "Failed to update required workflow parameters. Error: $_"
        }
    }

    Write-Output "Cleaning up temporary folder $TemporaryUpdateFolder."
    Remove-Item -Path $TemporaryUpdateFolder -Force -Recurse
}