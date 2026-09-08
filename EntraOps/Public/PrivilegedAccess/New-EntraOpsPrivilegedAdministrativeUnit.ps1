<#
.SYNOPSIS
    Creates (Restricted Management) Administrative Units based on EntraOps classification.

.DESCRIPTION
    (Restricted Management) Administrative Units for the different Enterprise Access Levels will be created based on the classification of EntraOps.

.PARAMETER ApplyToAccessTierLevel
    Array of Access Tier Levels to be processed. Default is ControlPlane, ManagementPlane.

.PARAMETER RbacSystems
    Array of RBAC systems to be processed. Default is Azure, AzureBilling, EntraID, IdentityGovernance, DeviceManagement, ResourceApps.

.PARAMETER RestrictedAUMode
    Parameter to define the mode of creating Restricted Management Administrative Units. Default is Selected.
    Selected will not create RMAU for Tier0 but also EntraID and Identity Governance RBACs. Mostly those are the RBACs which using role-assignable groups and are already restricted.

.EXAMPLE
    Create administrative units for EntraID, IdentityGovernance and ResourceApps RBAC systems with User and Group objectss
    New-EntraOpsPrivilegedAdministrativeUnit -RbacSystems ("EntraID", "IdentityGovernance") -RestrictedAUMode "Selected"
#>

function New-EntraOpsPrivilegedAdministrativeUnit {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $False)]
        [ValidateSet("ControlPlane", "ManagementPlane")]
        [Array]$ApplyToAccessTierLevel = ("ControlPlane", "ManagementPlane")
        ,
        [Parameter(Mandatory = $False)]
        [ValidateSet("User", "Group")]
        [Array]$FilterObjectType = ("User", "Group")
        ,        
        [Parameter(Mandatory = $False)]
        [ValidateSet("Azure", "EntraID", "IdentityGovernance", "ResourceApps", "DeviceManagement", "Defender")]
        [Array]$RbacSystems = ("EntraID", "IdentityGovernance", "ResourceApps", "DeviceManagement", "Defender")
        ,
        [Parameter(Mandatory = $False)]
        [ValidateSet("None", "Selected", "All")]
        [string]$RestrictedAuMode = "Selected" #Default value will not create RMAU for Tier0 and EntraID and Identity Governance RBACs
        ,
        [Parameter(Mandatory = $False)]
        [boolean]$ApplyAdministrativeUnitAssignments = $false
        ,
        [Parameter(Mandatory = $False)]
        [ValidateRange(0, 1)]
        [double]$RemovalSafetyThreshold = 0.5
    )

    foreach ($RbacSystem in $RbacSystems) {

        # Get EAM classification files
        if ($RbacSystem -eq "EntraID") {
            $ClassificationTemplateSubFolder = "AadResources"
        } else {
            $ClassificationTemplateSubFolder = $RbacSystem
        }
        $ClassificationTemplates = "$DefaultFolderClassification/Templates/Classification_$($ClassificationTemplateSubFolder).json"

        $PrivilegedEamClassificationFiles = @()
        $PrivilegedEamClassificationFiles = Get-ChildItem -Path $ClassificationTemplates -Filter "*.json"
        $PrivilegedEamClassifications = $PrivilegedEamClassificationFiles | foreach-object { Get-Content -Path $_.FullName | ConvertFrom-Json } | where-object { $_.EAMTierLevelName -in $ApplyToAccessTierLevel } | select-object -unique EAMTierLevelName, EAMTierLevelTagValue

        foreach ($TierLevel in $PrivilegedEamClassifications) {

            #region Verify existing or create new (Restricted Management) Administrative Units
            $Name = "Tier" + $TierLevel.EAMTierLevelTagValue + "-" + $TierLevel.EAMTierLevelName + "." + $RbacSystem
            $AdministrativeUnits = @(Invoke-EntraOpsMsGraphQuery -Method "GET" -Uri "/beta/administrativeUnits?`$filter=DisplayName eq '$(ConvertTo-EntraOpsODataStringLiteral -Value $Name)'" -OutputType PSObject -DisableCache)
            $AdministrativeUnit = (Select-EntraOpsUniqueGraphObject -InputObject $AdministrativeUnits -ObjectDescription "administrative unit '$Name'" -AllowNotFound).displayName
            if (-not $AdministrativeUnit) {
                Write-Host "Creating Administrative Unit $($Name)"
                $CreatedAuObject = $null

                $AuParams = @{
                    DisplayName = $Name
                    Description = "This administrative unit contains assets of " + $TierLevel.EAMTierLevelName + " in " + $RbacSystem
                }

                # Create Administrative Unit (AU) or Restricted Management AU for related Tier level
                if ($RestrictedAUMode -eq "All" `
                        -or ($RestrictedAUMode -eq "Selected" -and ($TierLevel.EAMTierLevelTagValue -ne "0") -and ($RbacSystem -ne "EntraID") -and ($RbacSystem -ne "IdentityGovernance") -and ($RBACSystem -ne "ResourceApps")) `
                        -or ($RestrictedAUMode -eq "Selected" -and ($RbacSystem -eq "ResourceApps" -and ($TierLevel.EAMTierLevelTagValue -ne "1"))) `
                ) {
                    $AuParams.IsMemberManagementRestricted = $true
                    $body = $AuParams | ConvertTo-Json -Depth 10
                    try {
                        $CreatedAuObject = Invoke-EntraOpsMsGraphQuery -Method "POST" -Body $Body -Uri "/beta/administrativeUnits" -ThrowOnFailure
                    } catch {
                        Write-Warning "Can not create Administrative Unit $($AuParams.DisplayName)"
                    }
                } else {
                    $Body = $AuParams | ConvertTo-Json -Depth 10
                    try {
                        $CreatedAuObject = Invoke-EntraOpsMsGraphQuery -Method "POST" -Body $Body -Uri "/beta/administrativeUnits" -ThrowOnFailure
                    } catch {
                        Write-Warning "Can not create Administrative Unit $($AuParams.DisplayName)! Error: $_"
                    }

                }

                # Poll only after Administrative Unit creation returns an object ID.
                if ($CreatedAuObject.id) {
                    # Check if AU has been created successfully, wait for delay and retry if not available yet
                    $AdministrativeUnit = $null
                    $MaxPollSeconds = 60
                    for ($i = 0; $i -lt $MaxPollSeconds -and -not $AdministrativeUnit; $i++) {
                        $AdministrativeUnit = Invoke-EntraOpsMsGraphQuery -Method "GET" -Uri "/beta/administrativeUnits/$($CreatedAuObject.id)" -DisableCache -SuppressNotFoundWarning
                        if (-not $AdministrativeUnit) { Start-Sleep -Seconds 1 }
                    }
                    if ($AdministrativeUnit) {
                        Write-Host "$($AdministrativeUnit.displayName) has been created successfully" -ForegroundColor Green
                    } else {
                        Write-Warning "$($AuParams.DisplayName) not available after $MaxPollSeconds second(s)."
                    }
                }
            } else {
                Write-Host "Administrative Unit $($AdministrativeUnit) already exists"
            }
            #endregion
        }

    }
}