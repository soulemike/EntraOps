<#
.SYNOPSIS
    Update classification files from AzurePrivilegedIAM repository to get latest definition of levels in Enterprise Access Model.

.DESCRIPTION
    Check all files in the EntraOps_Classification folder in the AzurePrivilegedIAM repository and download them to the folder specified in the $DefaultFolderClassification variable.

.PARAMETER FolderClassification
    Folder where the classification files should be stored. Default is "$DefaultFolderClassification/Templates".

.PARAMETER Classifications
    Array of classification names which should be updated. Default is ("AadResources", "AppRoles") which are available from the public repository.

.PARAMETER IncludeParamFiles
    If set, automatically includes any matching .Param variant files found in the repository for each classification in $Classifications.
    For example, if "DeviceManagement" is in $Classifications and a "Classification_DeviceManagement.Param.json" exists in the repository, it will also be downloaded.

.EXAMPLE
    Update all classification files in default location (./EntraOps_Classification/Templates) with classifications from the public repository AzurePrivilegedIAM
    Update-EntraOpsClassificationFiles

.EXAMPLE
    Update classification files including any available .Param variant files
    Update-EntraOpsClassificationFiles -Classifications ("AadResources", "DeviceManagement") -IncludeParamFiles
#>
function Update-EntraOpsClassificationFiles {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [System.String]$FolderClassification = "$DefaultFolderClassification/Templates",

        [Parameter(Mandatory = $false)]
        [Object]$Classifications = ("AadResources", "AadResources.Param", "AppRoles"),

        [Parameter(Mandatory = $false)]
        [Switch]$IncludeParamFiles = $true
    )

    $ClassificationTemplates = Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/Cloud-Architekt/AzurePrivilegedIAM/contents/EntraOps_Classification"

    # When -IncludeParamFiles is set, expand $Classifications with any .Param variants found in the repository
    if ($IncludeParamFiles) {
        $ParamVariants = $ClassificationTemplates | ForEach-Object {
            $_.Name.Replace("Classification_", "").Replace(".json", "")
        } | Where-Object {
            $BaseName = $_ -replace '\.Param$', ''
            $_ -like "*.Param" -and $BaseName -in $Classifications
        }
        $Classifications = ($Classifications + $ParamVariants) | Select-Object -Unique
    }

    foreach ($ClassificationTemplate in $ClassificationTemplates) {
        # Parsing classification name by removing the prefix and suffix from file name
        $ClassificationName = $ClassificationTemplate.Name.Replace("Classification_", "").Replace(".json", "")
        if ($ClassificationName -in $Classifications) {
            $LocalFilePath = "$($FolderClassification)/$($ClassificationTemplate.name)"
            $FileExisted = Test-Path $LocalFilePath
            $OldHash = if ($FileExisted) { (Get-FileHash $LocalFilePath -Algorithm SHA256).Hash } else { $null }
            $OldLastWriteTime = if ($FileExisted) { (Get-Item $LocalFilePath).LastWriteTime } else { $null }

            Invoke-RestMethod -Method GET -Uri $ClassificationTemplate.download_url -OutFile $LocalFilePath

            $NewLastWriteTime = (Get-Item $LocalFilePath).LastWriteTime
            $NewHash = (Get-FileHash $LocalFilePath -Algorithm SHA256).Hash

            if (-not $FileExisted) {
                Write-Host "[$($ClassificationTemplate.name)] New file downloaded at $NewLastWriteTime" -ForegroundColor Green
            } elseif ($OldHash -ne $NewHash) {
                Write-Host "[$($ClassificationTemplate.name)] Updated (Previous: $OldLastWriteTime | Current: $NewLastWriteTime)" -ForegroundColor Cyan
            } else {
                Write-Host "[$($ClassificationTemplate.name)] No changes detected (Last modified: $OldLastWriteTime)" -ForegroundColor Gray
            }
        }
    }
}
