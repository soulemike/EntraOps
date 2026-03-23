<#
.SYNOPSIS
    Update classification definition files for Microsoft Entra ID and/or Microsoft Intune (DeviceManagement) with fine-granular scope of Control Plane permissions based on privileged objects.

.DESCRIPTION
    Classification of Control Plane needs to consider the scope of sensitive permissions. For example, managing group membership of security groups should be managed as Control Plane by default.
    But this enforces to manage service-specific roles (e.g., Knowledge Administrator) as Control Plane. Protection of privileged objects by using Role-assignable groups (PRG), Entra ID Roles or Restricted Management Administrative Units (RMAU) allows to protect them by lower privileged roles with those permissions on directory-level.
    This function checks if privileged objects are protected by the previous mentoined methods and RMAUs with assigned privileged objects.
    A parameter file will be used to generate an updated classification definition file for Microsoft Entra ID and exclude directory roles without impact to privileged objects from Control Plane. All other assignments will be still managed as Control Plane.
    When DeviceManagement is included in ClassificationParameterScope, the function identifies privileged devices (owned by or associated with Control Plane and Management Plane users),
    resolves their transitive Entra ID group memberships, filters those groups to only include groups with Intune scope tag assignments, and replaces the group placeholders in the DeviceManagement classification parameter file.

.PARAMETER PrivilegedObjectClassificationSource
    Source of privileged objects to identify the scope of privileged objects and update the classification definition file for Microsoft Entra ID.
    Possible values are "All", "EntraOps", "PrivilegedObjectIds", "PrivilegedRolesFromAzGraph" and "PrivilegedEdgesFromExposureManagement".

.PARAMETER ClassificationParameterScope
    Array of RBAC systems whose classification parameter files should be parameterized. Default is ("EntraID").
    Possible values are "EntraID" and "DeviceManagement".

.PARAMETER EntraIdClassificationParameterFile
    Path to the classification parameter file for Microsoft Entra ID. Default is ./Classification/Templates/Classification_AadResources.Param.json.

.PARAMETER EntraIdCustomizedClassificationFile
    Path to the customized classification file for Microsoft Entra ID. Default is ./Classification/<TenantName>/Classification_AadResources.json.
    The file path will be recognized by the tenant name in the context of EntraOps and used for the classification.

.PARAMETER DeviceMgmtClassificationParameterFile
    Path to the classification parameter file for Microsoft Intune (DeviceManagement). Default is ./Classification/Templates/Classification_DeviceManagement.Param.json.

.PARAMETER DeviceMgmtCustomizedClassificationFile
    Path to the customized classification file for Microsoft Intune (DeviceManagement). Default is ./Classification/<TenantName>/Classification_DeviceManagement.json.

.PARAMETER EntraOpsEamFolder
    Path to the folder where the EntraOps classification definition files are stored. Default is ./Classification.

.PARAMETER EntraOpsScopes
    Array of EntraOps scopes which should be considered for the analysis. Default selection are all available scopes: Azure, AzureBilling, EntraID, IdentityGovernance, DeviceManagement and ResourceApps.

.PARAMETER AzureHighPrivilegedRoles
    Array of high privileged roles in Azure RBAC which should be considered for the analysis. Default selection are high-privileged roles: Owner, Role Based Access Control Administrator and User Access Administrator.

.PARAMETER AzureHighPrivilegedScopes
    Scope of high privileged roles in Azure RBAC which should be considered for the analysis. Default selection is all scopes including management groups.

.PARAMETER ExposureCriticalityLevel
    Criticality level of assets in Exposure Management which should be considered for the analysis. Default selection is criticality level <1.

.PARAMETER PrivilegedObjectIds
    Manual list of privileged object IDs to identify the scope of privileged objects and update the classification definition file for Microsoft Entra ID.

.PARAMETER DeviceMgmtPrivilegedTierScope
    Controls which privileged tiers and object types are included when building Device Management (Intune) scope tag assignments.
    "ControlPlaneAndManagementPlane" (default): Tier0 (ControlPlane) and Tier1 (ManagementPlane) devices and users are both included.
    "ControlPlaneDevicesOnly": Only devices owned by Tier0 (ControlPlane) users are included; Tier1 and user group memberships are skipped.

.EXAMPLE
    Get privileged objects from various Microsoft Entra RBACs and Microsoft Azure roles to identify the scope of privileged objects and update the classification definition file for Microsoft Entra ID.
    Update-EntraOpsClassificationControlPlaneScope -PrivilegedObjectClassificationSource "EntraOps" -RBACSystems ("Azure","EntraID","IdentityGovernance","DeviceManagement","ResourceApps")

.EXAMPLE
    Get exposure graph edges from Microsoft Security Exposure Management with relation of "has permissions to", "can authenticate as", "has role on", "has credentials of" or "affecting" to assets with criticality level <1.
    This identitfies objects with direct/indirect permissions which leads in attack/access paths to high sensitive assets which can be identified as Control Plane.
    Update-EntraOpsClassificationControlPlaneScope -PrivilegedObjectClassificationSource "PrivilegedEdgesFromExposureManagement" -ExposureCriticalityLevel = "<1"

.EXAMPLE
    Get permanent role assignments in Azure RBAC from Azure Resource Graph for high privileged roles (Owner, Role Based Access Control Administrator or User Access Administrator) on specific high-privileged scope ("/", "/providers/microsoft.management/managementgroups/8693dc7e-63c1-47ab-a7ee-acfe488bf52a").
    Update-EntraOpsClassificationControlPlaneScope -PrivilegedObjectClassificationSource "PrivilegedRolesFromAzGraph" -AzureHighPrivilegedRoles ("Owner", "Role Based Access Control Administrator", "User Access Administrator") -AzureHighPrivilegedScopes ("/", "/providers/microsoft.management/managementgroups/8693dc7e-63c1-47ab-a7ee-acfe488bf52a")

.EXAMPLE
    Use previous named data sources to identify high-privileged or sensitive objects from EntraOps, Azure RBAC and Exposure Management to update EntraOps classification definition file.
    Update-EntraOpsClassificationControlPlaneScope -PrivilegedObjectClassificationSource "All"

.EXAMPLE
    Get list of privileged object IDs to identify the scope of privileged objects and update the classification definition file for Microsoft Entra ID.
    $PrivilegedUser = Get-AzAdUser -filter "startswith(DisplayName,'adm')"
    $PrivilegedGroups = Get-AzAdGroup -filter "startswith(DisplayName,'prg')"
    $PrivilegedObjects = $PrivilegedUser + $PrivilegedGroups
    Update-EntraOpsClassificationControlPlaneScope -PrivilegedObjectClassificationSource "PrivilegedObjectIds" -PrivilegedObjectIds $PrivilegedObjects

.EXAMPLE
    Update classification for both Entra ID and DeviceManagement (Intune) RBAC systems. The DeviceManagement logic resolves privileged devices to scope tags.
    Update-EntraOpsClassificationControlPlaneScope -PrivilegedObjectClassificationSource "EntraOps" -ClassificationParameterScope ("EntraID", "DeviceManagement")

.EXAMPLE
    Update classification only for DeviceManagement (Intune) RBAC based on EntraOps data.
    Update-EntraOpsClassificationControlPlaneScope -PrivilegedObjectClassificationSource "EntraOps" -ClassificationParameterScope ("DeviceManagement")

.EXAMPLE
    Update DeviceManagement classification using only Tier0 (ControlPlane) owned devices - Tier1 and user group memberships are excluded.
    Update-EntraOpsClassificationControlPlaneScope -PrivilegedObjectClassificationSource "EntraOps" -ClassificationParameterScope ("DeviceManagement") -DeviceMgmtPrivilegedTierScope "ControlPlaneDevicesOnly"

#>

function Update-EntraOpsClassificationControlPlaneScope {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $False)]
        [ValidateSet("All", "EntraOps", "PrivilegedObjectIds", "PrivilegedRolesFromAzGraph", "PrivilegedEdgesFromExposureManagement")]
        [object]$PrivilegedObjectClassificationSource = "All"
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("EntraID", "DeviceManagement")]
        [object]$ClassificationParameterScope = ("EntraID", "DeviceManagement")
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$EntraIdClassificationParameterFile = "$DefaultFolderClassification\Templates\Classification_AadResources.Param.json"
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$EntraIdCustomizedClassificationFile = "$DefaultFolderClassification\$($TenantNameContext)\Classification_AadResources.json"
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$DeviceMgmtClassificationParameterFile = "$DefaultFolderClassification\Templates\Classification_DeviceManagement.Param.json"
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$DeviceMgmtCustomizedClassificationFile = "$DefaultFolderClassification\$($TenantNameContext)\Classification_DeviceManagement.json"
        ,
        [Parameter(Mandatory = $false)]
        [string]$EntraOpsEamFolder = "$DefaultFolderClassifiedEam"
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Azure", "AzureBilling", "EntraID", "IdentityGovernance", "DeviceManagement", "ResourceApps", "Defender")]
        [object]$EntraOpsScopes = ("Azure", "AzureBilling", "EntraID", "IdentityGovernance", "DeviceManagement", "ResourceApps", "Defender")
        ,
        [Parameter(Mandatory = $false)]
        [object]$AzureHighPrivilegedRoles = ("Owner", "Role Based Access Control Administrator", "User Access Administrator")
        ,
        [Parameter(Mandatory = $false)]
        [object]$AzureHighPrivilegedScopes = ("*")
        ,
        [Parameter(Mandatory = $false)]
        [string]$ExposureCriticalityLevel = "<1"
        ,
        [Parameter(Mandatory = $false)]
        [object]$PrivilegedObjectIds
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("ControlPlaneAndManagementPlane", "ControlPlaneDevicesOnly")]
        [string]$DeviceMgmtPrivilegedTierScope = "ControlPlaneAndManagementPlane"
    )

    $Parameters = @{
        PrivilegedObjectClassificationSource = $PrivilegedObjectClassificationSource
        EntraIdClassificationParameterFile   = $EntraIdClassificationParameterFile
        EntraIdCustomizedClassificationFile  = $EntraIdCustomizedClassificationFile
        EntraOpsEamFolder                    = $EntraOpsEamFolder
        EntraOpsScopes                       = $EntraOpsScopes 
        AzureHighPrivilegedRoles             = $AzureHighPrivilegedRoles
        AzureHighPrivilegedScopes            = $AzureHighPrivilegedScopes
        ExposureCriticalityLevel             = $ExposureCriticalityLevel
        PrivilegedObjectIds                  = $PrivilegedObjectIds
    }

    # Initialize tracking before any calls so captured warnings can be added immediately
    $ScopeSummary = [System.Collections.Generic.List[psobject]]::new()
    $WarningMessages = New-Object -TypeName "System.Collections.Generic.List[psobject]"

    $PrivilegedObjects = Get-EntraOpsClassificationControlPlaneObjects @Parameters -WarningVariable CollectedObjectWarnings -WarningAction SilentlyContinue

    # Classify and collect warnings from object resolution phase into the summary
    foreach ($Warn in $CollectedObjectWarnings) {
        $WarnText = $Warn.Message
        if ($WarnText -match 'No privileged objects found for .+ in EntraOps') {
            $WarningMessages.Add([PSCustomObject]@{ Type = "MissingEamData"; Message = $WarnText })
        } elseif ($WarnText -match 'not found|non-retryable|NotFound') {
            $WarningMessages.Add([PSCustomObject]@{ Type = "ObjectNotFound"; Message = $WarnText })
        } else {
            $WarningMessages.Add([PSCustomObject]@{ Type = "CollectedWarning"; Message = $WarnText })
        }
    }

    #region Get classification file and filter for unique privileged objects
    $DirectoryLevelAssignmentScope = @("/")
    $PrivilegedObjects = $PrivilegedObjects | sort-object ObjectType, ObjectDisplayName | Select-Object -Unique *

    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " EntraOps - Control Plane Scope Classification Update" -ForegroundColor Cyan
    Write-Host " Source : $PrivilegedObjectClassificationSource" -ForegroundColor Cyan
    Write-Host " RBAC Scope: $($ClassificationParameterScope -join ', ')" -ForegroundColor Cyan
    Write-Host " Objects identified: $(@($PrivilegedObjects).Count)" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""

    # Summary table: unique objects with all contributing sources listed per object
    Write-Host " Identified privileged objects by source:" -ForegroundColor White
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    $PrivilegedObjects | Sort-Object ObjectType, ObjectDisplayName | Group-Object -Property ObjectType | Sort-Object Name | ForEach-Object {
        Write-Host "  [$($_.Name)] ($($_.Count) object(s))" -ForegroundColor DarkCyan
        $_.Group | Sort-Object ObjectDisplayName | ForEach-Object {
            $Protection = @()
            if ($_.RestrictedManagementByRAG -eq $True) { $Protection += "RAG" }
            if ($_.RestrictedManagementByAadRole -eq $True) { $Protection += "AadRole" }
            if ($_.RestrictedManagementByRMAU -eq $True) { $Protection += "RMAU" }
            $ProtectionLabel = if ($Protection.Count -gt 0) { "[Protected: $($Protection -join ', ')]" } else { "[UNPROTECTED]" }
            $Color = if ($Protection.Count -gt 0) { "DarkGreen" } else { "Yellow" }
            $ObjSources = @($_.Classification.ClassificationSource | Select-Object -Unique | Sort-Object)
            $ObjSourceLabel = if ($ObjSources.Count -gt 0) { $ObjSources -join ', ' } else { $PrivilegedObjectClassificationSource }
            Write-Host "    $($_.ObjectDisplayName) ($($_.ObjectId)) | Source(s): $ObjSourceLabel | $ProtectionLabel" -ForegroundColor $Color
        }
    }
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host ""
    #endregion   

    #region EntraID RBAC Classification Parameter Scope
    if ($ClassificationParameterScope -contains "EntraID") {
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " Entra ID RBAC - Scope Parameter Update" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    $EntraIdRoleClassification = Get-Content -Path $EntraIdClassificationParameterFile

    #region Privileged User
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Privileged Users" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    $PrivilegedUsersAll = @($PrivilegedObjects | Where-Object { $_.ObjectType -eq "user" })
    $PrivilegedUsersWithoutProtection = @($PrivilegedUsersAll | Where-Object { $_.RestrictedManagementByRAG -eq $false -and $_.RestrictedManagementByAadRole -eq $False -and $_.RestrictedManagementByRMAU -eq $False })

    Write-Host "  Total users  : $($PrivilegedUsersAll.Count)" -ForegroundColor Gray
    Write-Host "  Unprotected  : $($PrivilegedUsersWithoutProtection.Count)" -ForegroundColor $(if ($PrivilegedUsersWithoutProtection.Count -gt 0) { 'Yellow' } else { 'DarkGreen' })

    # Include all Administrative Units because of Privileged Authentication Admin role assignment on (RM)AU level
    $PrivilegedUserWithAU = $PrivilegedObjects | Where-Object { $_.ObjectType -eq "user" -and $null -ne $_.AssignedAdministrativeUnits }
    $ScopeNamePrivilegedUsers = $PrivilegedUserWithAU.AssignedAdministrativeUnits | Select-Object -Unique id | ForEach-Object { "/administrativeUnits/$($_.id)" }
    if ($PrivilegedUsersWithoutProtection.Count -gt 0) {
        Write-Warning "  Control Plane users without protection - directory scope required!"
        $WarningMessages.Add([PSCustomObject]@{ Type = "UnprotectedUsers"; Message = "$($PrivilegedUsersWithoutProtection.Count) Control Plane user(s) without protection - directory scope required" })
        $PrivilegedUsersWithoutProtection | ForEach-Object {
            Write-Host "    [!] $($_.ObjectDisplayName) ($($_.ObjectId))" -ForegroundColor Yellow
        }
        $ScopeNamePrivilegedUsers += $DirectoryLevelAssignmentScope
    }

    if ($null -ne $ScopeNamePrivilegedUsers) {
        $ScopeNamePrivilegedUsers = @($ScopeNamePrivilegedUsers | Sort-Object -Unique)
        Write-Host "  Scope entries added:" -ForegroundColor Gray
        $ScopeNamePrivilegedUsers | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGreen }
        $ScopeNamePrivilegedUsersJSON = $ScopeNamePrivilegedUsers | ConvertTo-Json
        $ScopeNamePrivilegedUsersJSON = $ScopeNamePrivilegedUsersJSON.Replace('[', '').Replace(']', '')
        $ScopeNamePrivilegedUsersJSON = $ScopeNamePrivilegedUsersJSON -creplace '\s+', ' '
        $EntraIdRoleClassification = $EntraIdRoleClassification.replace('<ScopeNamePrivilegedUsers>', $ScopeNamePrivilegedUsersJSON)
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'ScopeNamePrivilegedUsers'; Entries = $ScopeNamePrivilegedUsers.Count; IncludesDirectory = ($ScopeNamePrivilegedUsers -contains '/'); Status = 'Updated' })
    } else {
        Write-Warning "  No privileged users require scope - placeholder cleared."
        $WarningMessages.Add([PSCustomObject]@{ Type = "EmptyScope"; Message = "No privileged users require scope - ScopeNamePrivilegedUsers placeholder cleared" })
        $EntraIdRoleClassification = $EntraIdRoleClassification.replace('<ScopeNamePrivilegedUsers>', '')
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'ScopeNamePrivilegedUsers'; Entries = 0; IncludesDirectory = $false; Status = 'Cleared' })
    }
    Write-Host ""
    #endregion

    #region Privileged Devices
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Privileged Devices" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    $PrivilegedUsersOwnedDevices = @($PrivilegedObjects | Where-Object { $_.ObjectType -eq "user" -and $null -ne $_.OwnedDevices } | Select-Object -ExpandProperty OwnedDevices)
    $PrivilegedUsersPawDevices = @($PrivilegedObjects | Where-Object { $_.ObjectType -eq "user" -and $null -ne $_.AssociatedPawDevice } | Select-Object -ExpandProperty AssociatedPawDevice)
    $PrivilegedUsersWithDevices = @($PrivilegedUsersOwnedDevices + $PrivilegedUsersPawDevices | Select-Object -Unique)
    Write-Host "  Devices of privileged users (OwnedDevices + AssociatedPawDevice): $(@($PrivilegedUsersWithDevices).Count)" -ForegroundColor Gray
    # Build per-device protection status. Devices not in any AU at all are unprotected but would be
    # invisible to a flat AU list - track HasRMAU per device to catch them.
    $PrivilegedDevicesProtection = @($PrivilegedUsersWithDevices | ForEach-Object {
            $DeviceId = $_
            $DeviceAUs = @(Invoke-EntraOpsMsGraphQuery -Method Get -Uri "/beta/devices/$DeviceId/memberOf/microsoft.graph.administrativeUnit" -OutputType PSObject | Where-Object { $null -ne $_.id } | Select-Object id, displayName, isMemberManagementRestricted)
            [PSCustomObject]@{
                DeviceId = $DeviceId
                AUs      = $DeviceAUs
                HasRMAU  = ($DeviceAUs | Where-Object { $_.isMemberManagementRestricted -eq $True }).Count -gt 0
            }
        })
    $PrivilegedDevicesWithoutProtection = @($PrivilegedDevicesProtection | Where-Object { $_.HasRMAU -eq $False })
    $ScopeNamePrivilegedDevices = $PrivilegedDevicesProtection | Where-Object { $_.HasRMAU -eq $True } | ForEach-Object { $_.AUs } | Where-Object { $_.isMemberManagementRestricted -eq $True } | Select-Object -Unique id | ForEach-Object { "/administrativeUnits/$($_.id)" }

    Write-Host "  Unprotected  : $($PrivilegedDevicesWithoutProtection.Count)" -ForegroundColor $(if ($PrivilegedDevicesWithoutProtection.Count -gt 0) { 'Yellow' } else { 'DarkGreen' })
    if ($PrivilegedDevicesWithoutProtection.Count -gt 0) {
        Write-Warning "  Control Plane devices without RMAU protection - directory scope required!"
        $WarningMessages.Add([PSCustomObject]@{ Type = "UnprotectedDevices"; Message = "$($PrivilegedDevicesWithoutProtection.Count) Control Plane device(s) without RMAU protection - directory scope required" })
        $PrivilegedDevicesWithoutProtection | ForEach-Object {
            Write-Host "    [!] Device $($_.DeviceId)" -ForegroundColor Yellow
        }
        $ScopeNamePrivilegedDevices += $DirectoryLevelAssignmentScope
    }
    if ($null -ne $ScopeNamePrivilegedDevices) {
        $ScopeNamePrivilegedDevices = @($ScopeNamePrivilegedDevices | Sort-Object -Unique)
        Write-Host "  Scope entries added:" -ForegroundColor Gray
        $ScopeNamePrivilegedDevices | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGreen }
        $ScopeNamePrivilegedDevicesJSON = $ScopeNamePrivilegedDevices | ConvertTo-Json
        $ScopeNamePrivilegedDevicesJSON = $ScopeNamePrivilegedDevicesJSON.Replace('[', '').Replace(']', '')
        $ScopeNamePrivilegedDevicesJSON = $ScopeNamePrivilegedDevicesJSON -creplace '\s+', ' '
        $EntraIdRoleClassification = $EntraIdRoleClassification.replace('<ScopeNamePrivilegedDevices>', $ScopeNamePrivilegedDevicesJSON)
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'ScopeNamePrivilegedDevices'; Entries = $ScopeNamePrivilegedDevices.Count; IncludesDirectory = ($ScopeNamePrivilegedDevices -contains '/'); Status = 'Updated' })
    } else {
        Write-Warning "  No privileged devices found - placeholder cleared."
        $WarningMessages.Add([PSCustomObject]@{ Type = "EmptyScope"; Message = "No privileged devices found - ScopeNamePrivilegedDevices placeholder cleared" })
        $EntraIdRoleClassification = $EntraIdRoleClassification.replace('<ScopeNamePrivilegedDevices>', '')
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'ScopeNamePrivilegedDevices'; Entries = 0; IncludesDirectory = $false; Status = 'Cleared' })
    }
    Write-Host ""
    #endregion

    #region Privileged Groups
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Privileged Groups" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    $PrivilegedGroupsAll = @($PrivilegedObjects | Where-Object { $_.ObjectType -eq "group" })
    $PrivilegedGroupsWithoutProtection = @($PrivilegedGroupsAll | Where-Object { $_.RestrictedManagementByRAG -eq $false -and $_.RestrictedManagementByAadRole -eq $False -and $_.RestrictedManagementByRMAU -eq $False })
    $PrivilegedGroupWithRMAU = @($PrivilegedGroupsAll | Where-Object { $_.RestrictedManagementByRMAU -eq $True })

    Write-Host "  Total groups : $($PrivilegedGroupsAll.Count)" -ForegroundColor Gray
    Write-Host "  Protected(RMAU): $($PrivilegedGroupWithRMAU.Count)" -ForegroundColor DarkGreen
    Write-Host "  Unprotected  : $($PrivilegedGroupsWithoutProtection.Count)" -ForegroundColor $(if ($PrivilegedGroupsWithoutProtection.Count -gt 0) { 'Yellow' } else { 'DarkGreen' })

    $ScopeNamePrivilegedGroups = $PrivilegedGroupWithRMAU.AssignedAdministrativeUnits | Select-Object -Unique id | ForEach-Object { "/administrativeUnits/$($_.id)" }
    if ($PrivilegedGroupsWithoutProtection.Count -gt 0) {
        Write-Warning "  Control Plane groups without RMAU protection - directory scope required!"
        $WarningMessages.Add([PSCustomObject]@{ Type = "UnprotectedGroups"; Message = "$($PrivilegedGroupsWithoutProtection.Count) Control Plane group(s) without RMAU protection - directory scope required" })
        $PrivilegedGroupsWithoutProtection | ForEach-Object {
            Write-Host "    [!] $($_.ObjectDisplayName) ($($_.ObjectId))" -ForegroundColor Yellow
        }
        $ScopeNamePrivilegedGroups += $DirectoryLevelAssignmentScope
    }
    if ($null -ne $ScopeNamePrivilegedGroups) {
        $ScopeNamePrivilegedGroups = @($ScopeNamePrivilegedGroups | Sort-Object -Unique)
        Write-Host "  Scope entries added:" -ForegroundColor Gray
        $ScopeNamePrivilegedGroups | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGreen }
        $ScopeNamePrivilegedGroupsJSON = $ScopeNamePrivilegedGroups | ConvertTo-Json
        $ScopeNamePrivilegedGroupsJSON = $ScopeNamePrivilegedGroupsJSON.Replace('[', '').Replace(']', '')
        $ScopeNamePrivilegedGroupsJSON = $ScopeNamePrivilegedGroupsJSON -creplace '\s+', ' '
        $EntraIdRoleClassification = $EntraIdRoleClassification.replace('<ScopeNamePrivilegedGroups>', $ScopeNamePrivilegedGroupsJSON)
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'ScopeNamePrivilegedGroups'; Entries = $ScopeNamePrivilegedGroups.Count; IncludesDirectory = ($ScopeNamePrivilegedGroups -contains '/'); Status = 'Updated' })
    } else {
        Write-Warning "  No privileged groups require scope - placeholder cleared."
        $WarningMessages.Add([PSCustomObject]@{ Type = "EmptyScope"; Message = "No privileged groups require scope - ScopeNamePrivilegedGroups placeholder cleared" })
        $EntraIdRoleClassification = $EntraIdRoleClassification.replace('<ScopeNamePrivilegedGroups>', '')
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'ScopeNamePrivilegedGroups'; Entries = 0; IncludesDirectory = $false; Status = 'Cleared' })
    }
    Write-Host ""
    #endregion

    #region Privileged Service Principals
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Privileged Service Principals & Applications" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    $PrivilegedServicePrincipals = @($PrivilegedObjects | Where-Object { $_.ObjectType -eq "servicePrincipal" })
    $PrivilegedApplicationObjects = @($PrivilegedObjects | Where-Object { $_.ObjectType -eq "application" })
    Write-Host "  Service Principals : $($PrivilegedServicePrincipals.Count)" -ForegroundColor Gray
    Write-Host "  Application objects: $($PrivilegedApplicationObjects.Count)" -ForegroundColor Gray
    
    if ($PrivilegedServicePrincipals.Count -gt 0 -or $PrivilegedApplicationObjects.Count -gt 0) {
        # Get list of object-level role assignment scope which includes Control Plane Service Principals
        $ScopeNameServicePrincipalObject = $PrivilegedServicePrincipals | ForEach-Object { "/$($_.ObjectId)" }

        # Get current tenant ID to identify single-tenant apps
        $CurrentTenantId = (Get-AzContext).Tenant.Id

        # Initialize array for application object scopes
        $ScopeNameApplicationObject = @()

        # Process direct application objects from EntraOps
        if ($PrivilegedApplicationObjects.Count -gt 0) {
            Write-Host "  Processing $($PrivilegedApplicationObjects.Count) direct application objects from EntraOps..." -ForegroundColor Gray
            foreach ($AppObj in $PrivilegedApplicationObjects) {
                $ScopeNameApplicationObject += "/$($AppObj.ObjectId)"
                Write-Host "  [+] Direct app object: $($AppObj.ObjectDisplayName) -> /$($AppObj.ObjectId)" -ForegroundColor DarkGreen
            }
        }

        # Filter for applications only (exclude managed identities and other types)
        $PrivilegedApplications = $PrivilegedServicePrincipals | Where-Object { $_.ObjectSubType -eq "Application" }
        
        # Get unique service principal object IDs for batch lookup
        $SpObjectIds = $PrivilegedApplications.ObjectId | Select-Object -Unique
        
        # Batch fetch service principal details for all at once to check appOwnerOrganizationId
        # This is much more efficient than individual requests
        $AppOwnershipInfo = @{}
        if ($SpObjectIds.Count -gt 0) {
            Write-Verbose "Fetching ownership information for $($SpObjectIds.Count) service principals..."
            foreach ($SpId in $SpObjectIds) {
                $Uri = "/v1.0/servicePrincipals/$($SpId)?`$select=id,appId,appOwnerOrganizationId,servicePrincipalType"
                try {
                    $SpDetails = Invoke-EntraOpsMsGraphQuery -Method Get -Uri $Uri -OutputType PSObject
                    if ($null -ne $SpDetails) {
                        $AppOwnershipInfo[$SpId] = $SpDetails
                        Write-Verbose "Fetched service principal details for: $SpId"
                    }
                } catch {
                    Write-Warning "Failed to fetch service principal details for $SpId : $_"
                }
            }
        }

        # Get application object IDs only for single-tenant apps owned by current tenant
        # Managed identities and multi-tenant apps are automatically excluded
        foreach ($App in $PrivilegedApplications) {
            $SpDetails = $AppOwnershipInfo[$App.ObjectId]
            
            # Only process if we have details and it's owned by current tenant (single-tenant app)
            if ($null -ne $SpDetails -and 
                $SpDetails.servicePrincipalType -ne "ManagedIdentity" -and 
                $SpDetails.appOwnerOrganizationId -eq $CurrentTenantId) {
                
                try {
                    $AppUri = "/v1.0/applications?`$filter=appId eq '$($SpDetails.appId)'&`$select=id,appId"
                    $AppObjects = Invoke-EntraOpsMsGraphQuery -Method Get -Uri $AppUri -OutputType PSObject
                    
                    if ($null -ne $AppObjects) {
                        # Handle both single object and collection responses
                        $AppObjectList = if ($AppObjects -is [System.Collections.IEnumerable] -and $AppObjects -isnot [string]) { $AppObjects } else { @($AppObjects) }
                        
                        foreach ($AppObject in $AppObjectList) {
                            if ($null -ne $AppObject.id) {
                                $ScopeNameApplicationObject += "/$($AppObject.id)"
                                Write-Host "  [+] App object resolved: $($App.ObjectDisplayName) ($($SpDetails.appId)) -> /$($AppObject.id)" -ForegroundColor DarkGreen
                            }
                        }
                    }
                } catch {
                    Write-Warning "  [!] Failed to fetch application object for appId $($SpDetails.appId): $_"
                    $WarningMessages.Add([PSCustomObject]@{ Type = "ApiError"; Message = "Failed to fetch application object for appId $($SpDetails.appId): $_" })
                }
            } else {
                if ($null -ne $SpDetails) {
                    Write-Host "  [~] Skipped: $($App.ObjectDisplayName) - Type: $($SpDetails.servicePrincipalType), Owner: $(if ($SpDetails.appOwnerOrganizationId -ne $CurrentTenantId) { 'External tenant' } else { $SpDetails.appOwnerOrganizationId })" -ForegroundColor DarkGray
                }
            }
        }

        $PrivilegedServicePrincipalWithAU = $PrivilegedObjects | Where-Object { $_.ObjectType -eq "servicePrincipal" -and $null -ne $_.AssignedAdministrativeUnits.id }
        $PrivilegedServicePrincipalWithAU = $PrivilegedServicePrincipalWithAU.AssignedAdministrativeUnits | Select-Object -Unique id | ForEach-Object { "/administrativeUnits/$($_.id)" }

        # Always add also directory level assignment scope because of missing protection of service principal by RAG, AAD Role or RMAU assignment
        $ScopeNamePrivilegedServicePrincipals = $ScopeNameServicePrincipalObject + $ScopeNameApplicationObject + $DirectoryLevelAssignmentScope + $PrivilegedServicePrincipalWithAU

        Write-Host "  Scope entries added:" -ForegroundColor Gray
        $ScopeNamePrivilegedServicePrincipals | Sort-Object -Unique | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGreen }
    } else {
        Write-Warning "  No privileged applications found - defaulting to directory scope '/'"
        $WarningMessages.Add([PSCustomObject]@{ Type = "EmptyScope"; Message = "No privileged applications found - ScopeNamePrivilegedServicePrincipals defaulting to directory scope '/'" })
        $EntraIdRoleClassification = $EntraIdRoleClassification.replace('<ScopeNamePrivilegedServicePrincipals>', '"/"')
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'ScopeNamePrivilegedServicePrincipals'; Entries = 1; IncludesDirectory = $true; Status = 'Default(/)' })
    }

    if ($null -ne $ScopeNamePrivilegedServicePrincipals) {
        $ScopeNamePrivilegedServicePrincipals = @($ScopeNamePrivilegedServicePrincipals | Sort-Object -Unique)
        $ScopeNamePrivilegedServicePrincipalsJSON = $ScopeNamePrivilegedServicePrincipals | ConvertTo-Json
        $ScopeNamePrivilegedServicePrincipalsJSON = $ScopeNamePrivilegedServicePrincipalsJSON.Replace('[', '').Replace(']', '')
        $ScopeNamePrivilegedServicePrincipalsJSON = $ScopeNamePrivilegedServicePrincipalsJSON -creplace '\s+', ' '
        $EntraIdRoleClassification = $EntraIdRoleClassification.replace('<ScopeNamePrivilegedServicePrincipals>', $ScopeNamePrivilegedServicePrincipalsJSON)
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'ScopeNamePrivilegedServicePrincipals'; Entries = $ScopeNamePrivilegedServicePrincipals.Count; IncludesDirectory = ($ScopeNamePrivilegedServicePrincipals -contains '/'); Status = 'Updated' })
    }
    Write-Host ""
    #endregion

    $EntraIdRoleClassification = $EntraIdRoleClassification | ConvertFrom-Json -Depth 10 | ConvertTo-Json -Depth 10 | Out-File -FilePath $EntraIdCustomizedClassificationFile -Force
    Write-Host "  Output file: $EntraIdCustomizedClassificationFile" -ForegroundColor Cyan

    } # end if EntraID
    #endregion

    #region DeviceManagement (Intune) RBAC Classification Parameter Scope
    if ($ClassificationParameterScope -contains "DeviceManagement") {
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " DeviceManagement (Intune) RBAC - Scope Parameter Update" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan

    $DeviceMgmtRoleClassification = Get-Content -Path $DeviceMgmtClassificationParameterFile

    #region Collect privileged devices from Control Plane and Management Plane
    Write-Host ""
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Privileged Devices for Intune Group Classification" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan

    # Collect all ControlPlane (Tier 0) and ManagementPlane (Tier 1) objects from EntraOps data
    $EntraOpsAllPrivilegedForDeviceMgmt = foreach ($Scope in $EntraOpsScopes) {
        try {
            Get-Content -Path "$EntraOpsEamFolder\$($Scope)\$($Scope).json" -ErrorAction Stop | ConvertFrom-Json -Depth 10
        } catch {
            Write-Verbose "No data for ${Scope}: $_"
        }
    }

    # Tier 0 - ControlPlane devices: devices owned by or associated (PAW) with ControlPlane users
    $Tier0Users = @($EntraOpsAllPrivilegedForDeviceMgmt | Where-Object { $_.ObjectAdminTierLevelName -eq "ControlPlane" -and $_.ObjectType -eq "user" } | Select-Object -Unique ObjectId, ObjectDisplayName, OwnedDevices, AssociatedPawDevice)
    $Tier0OwnedDeviceIds = @($Tier0Users | Where-Object { $null -ne $_.OwnedDevices } | Select-Object -ExpandProperty OwnedDevices)
    $Tier0PawDeviceIds = @($Tier0Users | Where-Object { $null -ne $_.AssociatedPawDevice } | Select-Object -ExpandProperty AssociatedPawDevice)
    $Tier0DeviceIds = @($Tier0OwnedDeviceIds + $Tier0PawDeviceIds | Select-Object -Unique)

    # Tier 1 - ManagementPlane devices: devices owned by or associated (PAW) with ManagementPlane users (only for ControlPlaneAndManagementPlane scope)
    if ($DeviceMgmtPrivilegedTierScope -eq "ControlPlaneAndManagementPlane") {
        $Tier1Users = @($EntraOpsAllPrivilegedForDeviceMgmt | Where-Object { $_.ObjectAdminTierLevelName -eq "ManagementPlane" -and $_.ObjectType -eq "user" } | Select-Object -Unique ObjectId, ObjectDisplayName, OwnedDevices, AssociatedPawDevice)
        $Tier1OwnedDeviceIds = @($Tier1Users | Where-Object { $null -ne $_.OwnedDevices } | Select-Object -ExpandProperty OwnedDevices)
        $Tier1PawDeviceIds = @($Tier1Users | Where-Object { $null -ne $_.AssociatedPawDevice } | Select-Object -ExpandProperty AssociatedPawDevice)
        $Tier1DeviceIds = @($Tier1OwnedDeviceIds + $Tier1PawDeviceIds | Select-Object -Unique)
        # Remove Tier 0 devices from Tier 1 to avoid double classification (Tier 0 takes precedence)
        $Tier1DeviceIds = @($Tier1DeviceIds | Where-Object { $_ -notin $Tier0DeviceIds })
    } else {
        $Tier1Users = @()
        $Tier1DeviceIds = @()
    }

    Write-Host "  Scope mode               : $DeviceMgmtPrivilegedTierScope" -ForegroundColor Cyan
    Write-Host "  Tier 0 (ControlPlane)   : $($Tier0Users.Count) user(s), $($Tier0DeviceIds.Count) device(s)" -ForegroundColor Gray
    Write-Host "  Tier 1 (ManagementPlane): $($Tier1Users.Count) user(s), $($Tier1DeviceIds.Count) device(s)" -ForegroundColor $(if ($DeviceMgmtPrivilegedTierScope -eq "ControlPlaneDevicesOnly") { 'DarkGray' } else { 'Gray' })

    # Verbose: per-user device detail (OwnedDevices + AssociatedPawDevice)
    Write-Verbose "  Tier 0 device associations:"
    $Tier0Users | ForEach-Object {
        $UserOwnedDevs = @(if ($null -ne $_.OwnedDevices) { $_.OwnedDevices } else { @() })
        $UserPawDevs = @(if ($null -ne $_.AssociatedPawDevice) { $_.AssociatedPawDevice } else { @() })
        $AllDevs = @($UserOwnedDevs + $UserPawDevs | Select-Object -Unique)
        if ($AllDevs.Count -gt 0) {
            $OwnedLabel = if ($UserOwnedDevs.Count -gt 0) { "Owned: $($UserOwnedDevs -join ', ')" } else { $null }
            $PawLabel = if ($UserPawDevs.Count -gt 0) { "PAW: $($UserPawDevs -join ', ')" } else { $null }
            $DetailLabel = @($OwnedLabel, $PawLabel) | Where-Object { $null -ne $_ }
            Write-Verbose "    $($_.ObjectDisplayName) ($($_.ObjectId)) -> $($DetailLabel -join ' | ')"
        }
    }
    if ($Tier0DeviceIds.Count -eq 0) { Write-Verbose "    (none)" }

    Write-Verbose "  Tier 1 device associations:"
    $Tier1Users | ForEach-Object {
        $UserOwnedDevs = @(if ($null -ne $_.OwnedDevices) { $_.OwnedDevices } else { @() })
        $UserPawDevs = @(if ($null -ne $_.AssociatedPawDevice) { $_.AssociatedPawDevice } else { @() })
        $AllDevs = @($UserOwnedDevs + $UserPawDevs | Select-Object -Unique | Where-Object { $_ -notin $Tier0DeviceIds })
        if ($AllDevs.Count -gt 0) {
            $OwnedLabel = if ($UserOwnedDevs.Count -gt 0) { "Owned: $($UserOwnedDevs -join ', ')" } else { $null }
            $PawLabel = if ($UserPawDevs.Count -gt 0) { "PAW: $($UserPawDevs -join ', ')" } else { $null }
            $DetailLabel = @($OwnedLabel, $PawLabel) | Where-Object { $null -ne $_ }
            Write-Verbose "    $($_.ObjectDisplayName) ($($_.ObjectId)) -> $($DetailLabel -join ' | ')"
        }
    }
    if ($Tier1DeviceIds.Count -eq 0) { Write-Verbose "    (none)" }
    #endregion

    #region Resolve transitive group memberships for privileged devices and users
    Write-Host ""
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Resolving Transitive Group Memberships for Devices" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan

    # Helper: Get all groups a directory object belongs to (including nested/transitive membership)
    function Get-TransitiveGroupMembership {
        param(
            [string]$ObjectId,
            [ValidateSet("devices", "users")]
            [string]$ObjectType = "devices"
        )
        $Groups = @()
        try {
            $MemberOf = Invoke-EntraOpsMsGraphQuery -Method Get -Uri "/beta/$ObjectType/$ObjectId/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName" -OutputType PSObject
            if ($null -ne $MemberOf) {
                $Groups = @($MemberOf | Where-Object { $null -ne $_.id } | Select-Object id, displayName)
            }
        } catch {
            Write-Warning "  Failed to resolve group membership for $ObjectType $ObjectId : $_"
        }
        return $Groups
    }

    # Resolve Tier 0 device groups
    $Tier0DeviceGroups = @{}
    foreach ($DeviceId in $Tier0DeviceIds) {
        $Groups = Get-TransitiveGroupMembership -ObjectId $DeviceId -ObjectType "devices"
        if ($Groups.Count -gt 0) {
            $Tier0DeviceGroups[$DeviceId] = $Groups
        }
    }
    $Tier0DeviceUniqueGroupIds = @($Tier0DeviceGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id | ForEach-Object { $_.id })

    # Resolve Tier 1 device groups
    $Tier1DeviceGroups = @{}
    foreach ($DeviceId in $Tier1DeviceIds) {
        $Groups = Get-TransitiveGroupMembership -ObjectId $DeviceId -ObjectType "devices"
        if ($Groups.Count -gt 0) {
            $Tier1DeviceGroups[$DeviceId] = $Groups
        }
    }
    $Tier1DeviceUniqueGroupIds = @($Tier1DeviceGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id | ForEach-Object { $_.id })

    Write-Verbose "  Tier 0 unique device groups: $($Tier0DeviceUniqueGroupIds.Count)"
    Write-Verbose "  Tier 1 unique device groups: $($Tier1DeviceUniqueGroupIds.Count)"

    # Initialize user group collections - populated below only when scope includes user group memberships
    $Tier0UserGroups = @{}
    $Tier0UserUniqueGroupIds = @()
    $Tier1UserGroups = @{}
    $Tier1UserUniqueGroupIds = @()

    #region Resolve transitive group memberships for privileged users
    if ($DeviceMgmtPrivilegedTierScope -eq "ControlPlaneAndManagementPlane") {
    Write-Host ""
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Resolving Transitive Group Memberships for Users" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan

    # Resolve Tier 0 user groups
    foreach ($User in $Tier0Users) {
        $Groups = Get-TransitiveGroupMembership -ObjectId $User.ObjectId -ObjectType "users"
        if ($Groups.Count -gt 0) {
            $Tier0UserGroups[$User.ObjectId] = $Groups
        }
    }
    $Tier0UserUniqueGroupIds = @($Tier0UserGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id | ForEach-Object { $_.id })

    # Resolve Tier 1 user groups (exclude groups already in Tier 0)
    $Tier1UserGroups = @{}
    foreach ($User in $Tier1Users) {
        $Groups = Get-TransitiveGroupMembership -ObjectId $User.ObjectId -ObjectType "users"
        if ($Groups.Count -gt 0) {
            $Tier1UserGroups[$User.ObjectId] = $Groups
        }
    }
    $Tier1UserUniqueGroupIds = @($Tier1UserGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id | ForEach-Object { $_.id })

    Write-Verbose "  Tier 0 unique user groups: $($Tier0UserUniqueGroupIds.Count)"
    Write-Verbose "  Tier 1 unique user groups: $($Tier1UserUniqueGroupIds.Count)"

    # Verbose: per-user group detail
    Write-Verbose "  Tier 0 user group memberships:"
    foreach ($UserId in $Tier0UserGroups.Keys) {
        $UserName = ($Tier0Users | Where-Object { $_.ObjectId -eq $UserId }).ObjectDisplayName
        $UserGroupNames = @($Tier0UserGroups[$UserId] | ForEach-Object { $_.displayName }) -join ', '
        Write-Verbose "    $UserName ($UserId) -> Groups: $UserGroupNames"
    }
    if ($Tier0UserGroups.Count -eq 0) { Write-Verbose "    (none)" }

    Write-Verbose "  Tier 1 user group memberships:"
    foreach ($UserId in $Tier1UserGroups.Keys) {
        $UserName = ($Tier1Users | Where-Object { $_.ObjectId -eq $UserId }).ObjectDisplayName
        $UserGroupNames = @($Tier1UserGroups[$UserId] | ForEach-Object { $_.displayName }) -join ', '
        Write-Verbose "    $UserName ($UserId) -> Groups: $UserGroupNames"
    }
    if ($Tier1UserGroups.Count -eq 0) { Write-Verbose "    (none)" }

    } # end if ControlPlaneAndManagementPlane (user groups)
    #endregion

    # Merge device and user groups into combined unique group IDs per tier
    if ($DeviceMgmtPrivilegedTierScope -eq "ControlPlaneDevicesOnly") {
        $Tier0UniqueGroupIds = @($Tier0DeviceUniqueGroupIds | Select-Object -Unique)
        $Tier1UniqueGroupIds = @()
    } else {
        $Tier0UniqueGroupIds = @($Tier0DeviceUniqueGroupIds + $Tier0UserUniqueGroupIds | Select-Object -Unique)
        $Tier1UniqueGroupIds = @($Tier1DeviceUniqueGroupIds + $Tier1UserUniqueGroupIds | Select-Object -Unique)
        # Groups containing members from both tiers intentionally appear in both lists
        # so they are included in both <Tier0IncludedGroupIds> and <Tier1IncludedGroupIds>
    }

    Write-Host ""
    Write-Host "  Combined unique groups (devices + users):" -ForegroundColor White
    Write-Host "  Tier 0 (ControlPlane)   : $($Tier0UniqueGroupIds.Count) group(s) total (devices: $($Tier0DeviceUniqueGroupIds.Count), users: $($Tier0UserUniqueGroupIds.Count))" -ForegroundColor Gray
    Write-Host "  Tier 1 (ManagementPlane): $($Tier1UniqueGroupIds.Count) group(s) total (devices: $($Tier1DeviceUniqueGroupIds.Count), users: $($Tier1UserUniqueGroupIds.Count))" -ForegroundColor Gray
    #endregion

    #region Map groups to Intune scope tags
    Write-Host ""
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Filtering Groups by Intune Scope Tag Assignments" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan

    # Fetch scope tag display names for reporting
    $IntuneScopeTags = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/beta/deviceManagement/roleScopeTags" -OutputType PSObject
    $ScopeTagNameLookup = @{}
    foreach ($ScopeTag in $IntuneScopeTags) {
        $ScopeTagNameLookup["$($ScopeTag.Id)"] = $ScopeTag.DisplayName
    }

    # Use roleManagement/deviceManagement/roleAssignments to get all groups (directoryScopeIds)
    # mapped to scope tags (appScopeIds). The roleScopeTags/{id}/assignments API does not return
    # all group IDs, whereas directoryScopeIds from roleAssignments provides the complete set.
    $DeviceMgmtRoleAssignments = Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/beta/roleManagement/deviceManagement/roleAssignments" -OutputType PSObject
    $IntuneScopeTagAssignments = foreach ($RoleAssignment in $DeviceMgmtRoleAssignments) {
        if ($null -eq $RoleAssignment.appScopeIds -or $RoleAssignment.appScopeIds.Count -eq 0) { continue }
        # directoryScopeIds contains the group IDs in scope for this role assignment
        $GroupIds = @($RoleAssignment.directoryScopeIds | Where-Object { $_ -ne "/" -and -not [string]::IsNullOrEmpty($_) })
        if ($GroupIds.Count -eq 0) { continue }
        foreach ($AppScopeId in $RoleAssignment.appScopeIds) {
            $ScopeTagName = $ScopeTagNameLookup["$AppScopeId"]
            if ([string]::IsNullOrEmpty($ScopeTagName)) { $ScopeTagName = "ScopeTag-$AppScopeId" }
            foreach ($GroupId in $GroupIds) {
                Write-Verbose "  ScopeTag '$ScopeTagName' (ID: $AppScopeId) -> GroupId: $GroupId (from roleAssignment $($RoleAssignment.Id))"
                [PSCustomObject]@{
                    ScopeTagName = $ScopeTagName
                    ScopeTagId   = $AppScopeId
                    GroupId      = $GroupId
                }
            }
        }
    }

    # Build set of all group IDs that are in scope of any Intune role assignment with a scope tag
    $AllScopeTagGroupIds = @($IntuneScopeTagAssignments | Select-Object -Unique GroupId | ForEach-Object { $_.GroupId })
    Write-Verbose "  Total unique groups in scope of Intune role assignments: $($AllScopeTagGroupIds.Count)"

    # Build a unified group-name lookup across devices and users for both tiers
    $AllGroupNameLookup = @{}
    foreach ($Groups in (@($Tier0DeviceGroups.Values) + @($Tier0UserGroups.Values) + @($Tier1DeviceGroups.Values) + @($Tier1UserGroups.Values))) {
        foreach ($Grp in $Groups) {
            if ($null -ne $Grp.id -and -not $AllGroupNameLookup.ContainsKey($Grp.id)) {
                $AllGroupNameLookup[$Grp.id] = $Grp.displayName
            }
        }
    }

    # Filter Tier 0 groups: only keep groups that are assigned to at least one Intune scope tag
    $Tier0FilteredGroupIds = @()
    $Tier0FilteredGroupDetails = @()
    foreach ($GroupId in $Tier0UniqueGroupIds) {
        if ($GroupId -in $AllScopeTagGroupIds) {
            $Tier0FilteredGroupIds += $GroupId
            $GroupName = $AllGroupNameLookup[$GroupId]
            $MatchedTags = @($IntuneScopeTagAssignments | Where-Object { $_.GroupId -eq $GroupId })
            $EamTier = if ($Tier0DeviceUniqueGroupIds -contains $GroupId) { 'ControlPlane (device)' } else { 'ControlPlane (user)' }
            $Tier0FilteredGroupDetails += [PSCustomObject]@{
                GroupId          = $GroupId
                GroupName        = $GroupName
                EAMTierLevelName = $EamTier
                ScopeTagNames    = ($MatchedTags | Select-Object -Unique ScopeTagName | ForEach-Object { $_.ScopeTagName }) -join ', '
            }
        }
    }

    # Filter Tier 1 groups: only keep groups that are assigned to at least one Intune scope tag
    $Tier1FilteredGroupIds = @()
    $Tier1FilteredGroupDetails = @()
    foreach ($GroupId in $Tier1UniqueGroupIds) {
        if ($GroupId -in $AllScopeTagGroupIds) {
            $Tier1FilteredGroupIds += $GroupId
            $GroupName = $AllGroupNameLookup[$GroupId]
            $MatchedTags = @($IntuneScopeTagAssignments | Where-Object { $_.GroupId -eq $GroupId })
            $EamTier = if ($Tier1DeviceUniqueGroupIds -contains $GroupId) { 'ManagementPlane (device)' } else { 'ManagementPlane (user)' }
            $Tier1FilteredGroupDetails += [PSCustomObject]@{
                GroupId          = $GroupId
                GroupName        = $GroupName
                EAMTierLevelName = $EamTier
                ScopeTagNames    = ($MatchedTags | Select-Object -Unique ScopeTagName | ForEach-Object { $_.ScopeTagName }) -join ', '
            }
        }
    }

    # Display Tier 0 groups filtered by scope tag presence
    Write-Host ""
    Write-Host "  Tier 0 (ControlPlane) groups with scope tag assignments:" -ForegroundColor White
    if ($Tier0FilteredGroupDetails.Count -gt 0) {
        $Tier0FilteredGroupDetails | Sort-Object GroupName | ForEach-Object {
            Write-Host "    $($_.GroupName) ($($_.GroupId)) [EAMTierLevelName: $($_.EAMTierLevelName)] -> ScopeTag(s): $($_.ScopeTagNames)" -ForegroundColor DarkGreen
        }
    } else {
        Write-Host "    (none - no Tier 0 groups are assigned to any Intune scope tags)" -ForegroundColor Yellow
        $WarningMessages.Add([PSCustomObject]@{ Type = "DeviceMgmtScope"; Message = "No Tier 0 (ControlPlane) groups are assigned to any Intune scope tags" })
    }
    $Tier0SkippedGroups = @($Tier0UniqueGroupIds | Where-Object { $_ -notin $Tier0FilteredGroupIds })
    if ($Tier0SkippedGroups.Count -gt 0) {
        Write-Verbose "  Tier 0 groups skipped (no scope tag assignment):"
        foreach ($SkippedId in $Tier0SkippedGroups) {
            Write-Verbose "    $($AllGroupNameLookup[$SkippedId]) ($SkippedId)"
        }
    }

    # Display Tier 1 groups filtered by scope tag presence
    Write-Host "  Tier 1 (ManagementPlane) groups with scope tag assignments:" -ForegroundColor White
    if ($Tier1FilteredGroupDetails.Count -gt 0) {
        $Tier1FilteredGroupDetails | Sort-Object GroupName | ForEach-Object {
            Write-Host "    $($_.GroupName) ($($_.GroupId)) [EAMTierLevelName: $($_.EAMTierLevelName)] -> ScopeTag(s): $($_.ScopeTagNames)" -ForegroundColor DarkGreen
        }
    } else {
        Write-Host "    (none - no Tier 1 groups are assigned to any Intune scope tags)" -ForegroundColor Yellow
        $WarningMessages.Add([PSCustomObject]@{ Type = "DeviceMgmtScope"; Message = "No Tier 1 (ManagementPlane) groups are assigned to any Intune scope tags" })
    }
    $Tier1SkippedGroups = @($Tier1UniqueGroupIds | Where-Object { $_ -notin $Tier1FilteredGroupIds })
    if ($Tier1SkippedGroups.Count -gt 0) {
        Write-Verbose "  Tier 1 groups skipped (no scope tag assignment):"
        foreach ($SkippedId in $Tier1SkippedGroups) {
            Write-Verbose "    $($AllGroupNameLookup[$SkippedId]) ($SkippedId)"
        }
    }
    #endregion

    #region Replace placeholders in DeviceManagement classification parameter file
    Write-Host ""
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Replacing DeviceManagement Scope Placeholders (GroupIds)" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan

    # Replace <Tier0IncludedGroupIds> with Tier 0 group IDs (filtered by scope tag presence)
    if ($Tier0FilteredGroupIds.Count -gt 0) {
        $Tier0GroupIdsJSON = ($Tier0FilteredGroupIds | Sort-Object -Unique | ForEach-Object { "`"$_`"" }) -join ', '
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('"<Tier0IncludedGroupIds>"', $Tier0GroupIdsJSON)
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('<Tier0IncludedGroupIds>', $Tier0GroupIdsJSON)
        Write-Host "  <Tier0IncludedGroupIds> -> $Tier0GroupIdsJSON" -ForegroundColor DarkGreen
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'Tier0IncludedGroupIds'; Entries = $Tier0FilteredGroupIds.Count; IncludesDirectory = $false; Status = 'Updated (GroupIds)' })
    } else {
        Write-Warning "  No Tier 0 groups with scope tag assignments found - placeholder cleared."
        $WarningMessages.Add([PSCustomObject]@{ Type = "EmptyScope"; Message = "No Tier 0 groups with scope tag assignments found - Tier0IncludedGroupIds placeholder cleared" })
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('"<Tier0IncludedGroupIds>",', '')
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('"<Tier0IncludedGroupIds>"', '')
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('<Tier0IncludedGroupIds>,', '')
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('<Tier0IncludedGroupIds>', '')
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'Tier0IncludedGroupIds'; Entries = 0; IncludesDirectory = $false; Status = 'Cleared' })
    }

    # Replace <Tier1IncludedGroupIds> with Tier 1 group IDs (filtered by scope tag presence)
    if ($Tier1FilteredGroupIds.Count -gt 0) {
        $Tier1GroupIdsJSON = ($Tier1FilteredGroupIds | Sort-Object -Unique | ForEach-Object { "`"$_`"" }) -join ', '
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('"<Tier1IncludedGroupIds>"', $Tier1GroupIdsJSON)
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('<Tier1IncludedGroupIds>', $Tier1GroupIdsJSON)
        Write-Host "  <Tier1IncludedGroupIds> -> $Tier1GroupIdsJSON" -ForegroundColor DarkGreen
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'Tier1IncludedGroupIds'; Entries = $Tier1FilteredGroupIds.Count; IncludesDirectory = $false; Status = 'Updated (GroupIds)' })
    } else {
        Write-Warning "  No Tier 1 groups with scope tag assignments found - placeholder cleared."
        $WarningMessages.Add([PSCustomObject]@{ Type = "EmptyScope"; Message = "No Tier 1 groups with scope tag assignments found - Tier1IncludedGroupIds placeholder cleared" })
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('"<Tier1IncludedGroupIds>",', '')
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('"<Tier1IncludedGroupIds>"', '')
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('<Tier1IncludedGroupIds>,', '')
        $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification.replace('<Tier1IncludedGroupIds>', '')
        $ScopeSummary.Add([PSCustomObject]@{ Placeholder = 'Tier1IncludedGroupIds'; Entries = 0; IncludesDirectory = $false; Status = 'Cleared' })
    }

    # Tier2EnterpriseDeviceScopeTagId is no longer needed - ManagementPlane uses "/*" wildcard
    # with ExcludedRoleAssignmentScopeName to cover all scopes not in Tier 0/1

    $DeviceMgmtRoleClassification = $DeviceMgmtRoleClassification | ConvertFrom-Json -Depth 10 | ConvertTo-Json -Depth 10 | Out-File -FilePath $DeviceMgmtCustomizedClassificationFile -Force
    Write-Host "  Output file: $DeviceMgmtCustomizedClassificationFile" -ForegroundColor Cyan
    #endregion

    #region DeviceManagement Summary: Groups and Devices
    Write-Host ""
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " DeviceManagement Classification Summary" -ForegroundColor DarkCyan
    Write-Host "---------------------------------------------------------" -ForegroundColor DarkCyan

    # Summary: all unique groups in scope with their EAMTierLevelName reason
    $AllTierGroupSummary = @()
    $AllTierGroupSummary += $Tier0DeviceGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id, displayName | ForEach-Object {
        [PSCustomObject]@{ GroupName = $_.displayName; GroupId = $_.id; EAMTierLevelName = 'ControlPlane'; ObjectType = 'device' }
    }
    $AllTierGroupSummary += $Tier0UserGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id, displayName | ForEach-Object {
        [PSCustomObject]@{ GroupName = $_.displayName; GroupId = $_.id; EAMTierLevelName = 'ControlPlane'; ObjectType = 'user' }
    }
    $AllTierGroupSummary += $Tier1DeviceGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id, displayName | ForEach-Object {
        [PSCustomObject]@{ GroupName = $_.displayName; GroupId = $_.id; EAMTierLevelName = 'ManagementPlane'; ObjectType = 'device' }
    }
    $AllTierGroupSummary += $Tier1UserGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id, displayName | ForEach-Object {
        [PSCustomObject]@{ GroupName = $_.displayName; GroupId = $_.id; EAMTierLevelName = 'ManagementPlane'; ObjectType = 'user' }
    }

    Write-Host ""
    Write-Host "  Groups in scope (reason = EAMTierLevelName of members):" -ForegroundColor White
    if ($AllTierGroupSummary.Count -gt 0) {
        $AllTierGroupSummary | Where-Object { $null -ne $_ } | Group-Object GroupId | Sort-Object { ($_.Group | Select-Object -First 1).EAMTierLevelName }, { ($_.Group | Select-Object -First 1).GroupName } | ForEach-Object {
            $EamLabels = ($_.Group | Select-Object -Unique EAMTierLevelName, ObjectType | ForEach-Object { "$($_.EAMTierLevelName) ($($_.ObjectType))" }) -join ', '
            $GroupEntry = $_.Group[0]
            Write-Host "    $($GroupEntry.GroupName) ($($GroupEntry.GroupId)) [EAMTierLevelName: $EamLabels]" -ForegroundColor DarkGreen
        }
    } else {
        Write-Host "    (none)" -ForegroundColor DarkGray
    }

    # Verbose: per-device and per-user detail
    Write-Verbose "  Tier 0 (ControlPlane) device groups in scope:"
    if ($Tier0DeviceUniqueGroupIds.Count -gt 0) {
        $Tier0AllDeviceGroupDetails = $Tier0DeviceGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id, displayName | Sort-Object displayName
        foreach ($Grp in $Tier0AllDeviceGroupDetails) {
            $DevicesInGroup = @($Tier0DeviceGroups.GetEnumerator() | Where-Object { $_.Value.id -contains $Grp.id } | ForEach-Object { $_.Key })
            Write-Verbose "    $($Grp.displayName) ($($Grp.id)) <- Devices: $($DevicesInGroup -join ', ')"
        }
    } else { Write-Verbose "    (none)" }

    Write-Verbose "  Tier 0 (ControlPlane) user groups in scope:"
    if ($Tier0UserUniqueGroupIds.Count -gt 0) {
        $Tier0AllUserGroupDetails = $Tier0UserGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id, displayName | Sort-Object displayName
        foreach ($Grp in $Tier0AllUserGroupDetails) {
            $UsersInGroup = @($Tier0UserGroups.GetEnumerator() | Where-Object { $_.Value.id -contains $Grp.id } | ForEach-Object { $_.Key })
            Write-Verbose "    $($Grp.displayName) ($($Grp.id)) <- Users: $($UsersInGroup -join ', ')"
        }
    } else { Write-Verbose "    (none)" }

    Write-Verbose "  Tier 1 (ManagementPlane) device groups in scope:"
    if ($Tier1DeviceUniqueGroupIds.Count -gt 0) {
        $Tier1AllDeviceGroupDetails = $Tier1DeviceGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id, displayName | Sort-Object displayName
        foreach ($Grp in $Tier1AllDeviceGroupDetails) {
            $DevicesInGroup = @($Tier1DeviceGroups.GetEnumerator() | Where-Object { $_.Value.id -contains $Grp.id } | ForEach-Object { $_.Key })
            Write-Verbose "    $($Grp.displayName) ($($Grp.id)) <- Devices: $($DevicesInGroup -join ', ')"
        }
    } else { Write-Verbose "    (none)" }

    Write-Verbose "  Tier 1 (ManagementPlane) user groups in scope:"
    if ($Tier1UserUniqueGroupIds.Count -gt 0) {
        $Tier1AllUserGroupDetails = $Tier1UserGroups.Values | ForEach-Object { $_ } | Select-Object -Unique id, displayName | Sort-Object displayName
        foreach ($Grp in $Tier1AllUserGroupDetails) {
            $UsersInGroup = @($Tier1UserGroups.GetEnumerator() | Where-Object { $_.Value.id -contains $Grp.id } | ForEach-Object { $_.Key })
            Write-Verbose "    $($Grp.displayName) ($($Grp.id)) <- Users: $($UsersInGroup -join ', ')"
        }
    } else { Write-Verbose "    (none)" }

    Write-Verbose "  Devices that led to classification (OwnedDevices + AssociatedPawDevice):"
    Write-Verbose "    Tier 0 (ControlPlane):"
    foreach ($User in $Tier0Users) {
        $UserOwnedDevs = @(if ($null -ne $User.OwnedDevices) { $User.OwnedDevices } else { @() })
        $UserPawDevs = @(if ($null -ne $User.AssociatedPawDevice) { $User.AssociatedPawDevice } else { @() })
        $AllUserDevs = @($UserOwnedDevs + $UserPawDevs | Select-Object -Unique)
        foreach ($DevId in $AllUserDevs) {
            $Source = @()
            if ($DevId -in $UserOwnedDevs) { $Source += 'Owned' }
            if ($DevId -in $UserPawDevs) { $Source += 'PAW' }
            $GroupNames = @($Tier0DeviceGroups[$DevId] | ForEach-Object { $_.displayName }) -join ', '
            $GroupLabel = if ($GroupNames) { " -> Groups: $GroupNames" } else { " -> (no group memberships found)" }
            Write-Verbose "      Device $DevId [$($Source -join ',')] (User: $($User.ObjectDisplayName))$GroupLabel"
        }
    }
    if ($Tier0DeviceIds.Count -eq 0) { Write-Verbose "      (none)" }

    Write-Verbose "    Tier 1 (ManagementPlane):"
    foreach ($User in $Tier1Users) {
        $UserOwnedDevs = @(if ($null -ne $User.OwnedDevices) { $User.OwnedDevices } else { @() })
        $UserPawDevs = @(if ($null -ne $User.AssociatedPawDevice) { $User.AssociatedPawDevice } else { @() })
        $AllUserDevs = @($UserOwnedDevs + $UserPawDevs | Select-Object -Unique | Where-Object { $_ -notin $Tier0DeviceIds })
        foreach ($DevId in $AllUserDevs) {
            $Source = @()
            if ($DevId -in $UserOwnedDevs) { $Source += 'Owned' }
            if ($DevId -in $UserPawDevs) { $Source += 'PAW' }
            $GroupNames = @($Tier1DeviceGroups[$DevId] | ForEach-Object { $_.displayName }) -join ', '
            $GroupLabel = if ($GroupNames) { " -> Groups: $GroupNames" } else { " -> (no group memberships found)" }
            Write-Verbose "      Device $DevId [$($Source -join ',')] (User: $($User.ObjectDisplayName))$GroupLabel"
        }
    }
    if ($Tier1DeviceIds.Count -eq 0) { Write-Verbose "      (none)" }
    Write-Host ""
    #endregion

    } # end if DeviceManagement
    #endregion

    # Final summary
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " Classification Update Complete" -ForegroundColor Cyan
    Write-Host " RBAC Scope: $($ClassificationParameterScope -join ', ')" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
    Show-EntraOpsWarningSummary -WarningMessages $WarningMessages
    $ScopeSummary | Format-Table -AutoSize -Property Placeholder,
    @{Name = 'ScopeEntries'; Expression = { $_.Entries }; Align = 'Right' },
    @{Name = 'Dir(/)'; Expression = { if ($_.IncludesDirectory) { 'YES' } else { 'no' } }; Align = 'Center' },
    Status
}
