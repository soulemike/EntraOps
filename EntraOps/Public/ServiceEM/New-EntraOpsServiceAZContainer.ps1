<#
.SYNOPSIS
    Creates an Azure Resource Group and assigns EAM-aligned RBAC/PIM authorizations.

.DESCRIPTION
    Creates (or looks up) an Azure Resource Group named "RG-<ServiceName>" and
    assigns Azure RBAC and/or PIM eligible role assignments to the EAM security
    groups produced by New-EntraOpsServiceBootstrap. The following assignments
    are created by default (rbacModel=PIM):

    - WorkloadPlane-Admins: permanent Reader
    - ManagementPlane-Members: permanent Reader (skipped if inherited from parent scope)
    - ManagementPlane-Admins: PIM eligible Contributor (skipped if inherited)
    - ControlPlane-Admins: PIM eligible User Access Administrator (skipped when
      SkipControlPlaneDelegation is set)

    Constrained delegation settings are read from
    EntraOpsConfig.ServiceEM.ConstrainedDelegation when available.

.PARAMETER ServiceName
    Name of the service. The resource group will be created as "RG-<ServiceName>".

.PARAMETER ServiceGroups
    The Entra group objects produced by New-EntraOpsServiceBootstrap / New-EntraOpsServiceEntraGroup.
    Groups are matched by DisplayName patterns (e.g. *-ControlPlane-Admins).

.PARAMETER rbacModel
    Controls which assignment type is created. Accepted values:
    - PIM  (default): PIM eligible assignments only.
    - Azure: Permanent Azure RBAC assignments only.
    - Both: Creates both permanent and PIM eligible assignments.

.PARAMETER SkipControlPlaneDelegation
    When set, skips the PIM eligible User Access Administrator assignment for the
    ControlPlane-Admins group. Set automatically by Bootstrap when a delegated
    ControlPlaneDelegationGroupId is provided.

.PARAMETER pimForGroups
    When set together with rbacModel Azure or Both, assigns Owner permanently to
    the PIM staging group (*-PIM-*). Not used in the default PIM-only model.

.PARAMETER Location
    Azure region for the resource group (e.g. "westeurope", "northeurope").

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsServiceAZContainer -ServiceName "MyService" -ServiceGroups $groups `
        -Location "westeurope"

    Creates RG-MyService in West Europe and assigns default PIM eligible roles to
    ManagementPlane-Admins (Contributor) and ControlPlane-Admins (User Access
    Administrator), plus permanent Reader to WorkloadPlane-Admins.

.EXAMPLE
    New-EntraOpsServiceAZContainer -ServiceName "MyService" -ServiceGroups $groups `
        -Location "westeurope" -SkipControlPlaneDelegation

    Same as above but omits the User Access Administrator PIM eligible assignment,
    used when ControlPlane is delegated to an external group.

#>
function New-EntraOpsServiceAZContainer {
    [OutputType([psobject])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [psobject[]]$ServiceGroups,

        [ValidateSet("Azure","PIM","Both")]
        [string]$rbacModel = "PIM",

        [switch]$SkipControlPlaneDelegation,

        [switch]$pimForGroups,

        [string]$Location,

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        try{
            Write-Verbose "$logPrefix Looking up Azure Resource Group"
            $resourceGroup = Get-AzResourceGroup -Name "RG-$serviceName" -ErrorAction Stop
        }catch{
            if($_.Exception.Message -like "*not exist."){
                Write-Verbose "$logPrefix Azure Resource Group not found, creating"
                $resourceGroup = New-AzResourceGroup -Name "RG-$serviceName" -Location $Location
                $confirmed = $false
                $i = 0
                while(-not $confirmed){
                    Start-Sleep -Seconds ([Math]::Pow(2,$i)-1)
                    $checkResourceGroup = Get-AzResourceGroup -Name "RG-$serviceName"
                    if(($checkResourceGroup|Measure-Object).Count -eq 1){
                        Write-Verbose "$logPrefix Azure consistency found confirming"
                        $confirmed = $true
                        continue
                    }
                    $i++
                    if($i -gt 10){
                        throw "Resource Group consistency with Azure not achieved"
                    }
                    Write-Verbose "$logPrefix Azure resources not available, sleeping $([Math]::Pow(2,$i)-1) seconds"
                }
            }else{
                Write-Verbose "$logPrefix Failed to lookup Azure Resource Group"
                Write-Error $_
            }
        }
        try{
            $owner           = Get-AzRoleDefinition -Name Owner
            $reader          = Get-AzRoleDefinition -Name Reader
            $userAccessAdmin = Get-AzRoleDefinition -Name "User Access Administrator"
            $contributor     = Get-AzRoleDefinition -Name Contributor
            $rbacAdmin       = Get-AzRoleDefinition -Name "Role Based Access Control Administrator"
        }catch{
            Write-Verbose "$logPrefix Failed to find role definitions"
            Write-Error $_
        }
        $pimAdmins  = $ServiceGroups|Where-Object{$_.DisplayName -like "*-PIM-*"}
        $members    = $ServiceGroups|Where-Object{$_.DisplayName -like "*-ManagementPlane-Members"}
        if ($SkipControlPlaneDelegation) {
            Write-Verbose "$logPrefix Skipping Control Plane delegation setup"
        } else {
            $control    = $ServiceGroups|Where-Object{$_.DisplayName -like "*-ControlPlane-Admins"}
        }
        $management     = $ServiceGroups|Where-Object{$_.DisplayName -like "*-ManagementPlane-Admins"}
        $workloadAdmins = $ServiceGroups|Where-Object{$_.DisplayName -like "*-WorkloadPlane-Admins"}
        $workloadUsers  = $ServiceGroups|Where-Object{$_.DisplayName -like "*-WorkloadPlane-Users"}
        
        # Load constrained delegation configuration from global config
        $constrainedDelegationConfig = $null
        if ($Global:EntraOpsConfig.ServiceEM.ConstrainedDelegation) {
            $constrainedDelegationConfig = $Global:EntraOpsConfig.ServiceEM.ConstrainedDelegation
            Write-Verbose "$logPrefix Loaded constrained delegation configuration from EntraOpsConfig"
        } else {
            Write-Warning "$logPrefix No constrained delegation configuration found in EntraOpsConfig.ServiceEM.ConstrainedDelegation"
        }
        
        $scheduleRequestParams = @{
            Name = ""
            RoleDefinitionId = ""
            PrincipalId = ""
            Scope = $resourceGroup.ResourceId
            RequestType = "AdminAssign"
            Justification = "Initial Bootstrap"
            #ExpirationDuration = "P1Y"
            ExpirationType = "NoExpiration" #AfterDuration
            ScheduleInfoStartDateTime = (Get-Date -Format o)
        }
        $roleDefinitionPrefix = "/Subscriptions/$((Get-AzContext).Subscription.Id)/providers/Microsoft.Authorization/roleDefinitions/"
        $rbacSet = @()
        $eligibleRbacSet = @()
        $toAdd = @()
    }

    process {
        if($rbacModel -in ("Azure","Both")){
            $rbacSet = @()
            try{
                Write-Verbose "$logPrefix Looking up Role Assignments for ID: $($resourceGroup.ResourceId)"
                $rbacSet += Get-AzRoleAssignment -Scope $resourceGroup.ResourceId
            }catch{
                Write-Verbose "$logPrefix Failed to get Role Assignments"
                Write-Error $_
            }
            $rbacSplat = @{
                ResourceGroupName = $resourceGroup.ResourceGroupName
            }
            if($pimForGroups -and "$($pimAdmins.Id)_$($owner.Id)" -notin ($rbacSet|ForEach-Object{"$($_.ObjectId)_$($_.RoleDefinitionId)"})){
                $rbacSplat.RoleDefinitionName = $owner.Name
                $rbacSplat.ObjectId = $pimAdmins.Id
                try{
                    Write-Verbose "$logPrefix Creating Role Assignment for ID: $($pimAdmins.Id)"
                    Write-Verbose "$logPrefix $($rbacSplat|ConvertTo-Json -Compress)"
                    $rbacSet += New-AzRoleAssignment @rbacSplat
                }catch{
                    Write-Verbose "$logPrefix Failed to create role assignment"
                    Write-Error $_
                }
            }

            # Permanent Reader for ManagementPlane-Admins (with inheritance check)
            if($management){
                $skipReaderForMgmt = $false
                try {
                    Write-Verbose "$logPrefix Checking for inherited Reader assignment for ManagementPlane-Admins at subscription scope"
                    $subscriptionScope = "/subscriptions/$((Get-AzContext).Subscription.Id)"
                    $inheritedReaderAssignments = Get-AzRoleAssignment -Scope $subscriptionScope -ObjectId $management.Id | Where-Object {
                        $_.RoleDefinitionName -eq $reader.Name -and $_.Scope -ne $resourceGroup.ResourceId
                    }
                    if($inheritedReaderAssignments) {
                        Write-Verbose "$logPrefix ManagementPlane-Admins already has Reader at a higher scope — skipping RG assignment"
                        $skipReaderForMgmt = $true
                    }
                } catch {
                    Write-Verbose "$logPrefix Failed to check inherited Reader assignments for ManagementPlane-Admins: $_"
                }

                if(-not $skipReaderForMgmt -and "$($management.Id)_$($reader.Id)" -notin ($rbacSet|ForEach-Object{"$($_.ObjectId)_$($_.RoleDefinitionId)"})){
                    $rbacSplat.RoleDefinitionName = $reader.Name
                    $rbacSplat.ObjectId = $management.Id
                    try{
                        Write-Verbose "$logPrefix Creating permanent Reader assignment for ManagementPlane-Admins: $($management.Id)"
                        Write-Verbose "$logPrefix $($rbacSplat|ConvertTo-Json -Compress)"
                        $rbacSet += New-AzRoleAssignment @rbacSplat
                    }catch{
                        Write-Verbose "$logPrefix Failed to create role assignment"
                        Write-Error $_
                    }
                }
            }
        }

        # Permanent Reader for WorkloadPlane-Admins — always assigned regardless of rbacModel.
        # WorkloadPlane-Admins need read visibility into the RG even in the default PIM-only model.
        if($workloadAdmins){
            $wlExisting = @()
            try {
                $wlExisting = Get-AzRoleAssignment -Scope $resourceGroup.ResourceId -ObjectId $workloadAdmins.Id
            } catch {
                Write-Verbose "$logPrefix Failed to check existing Reader assignment for WorkloadPlane-Admins: $_"
            }
            if("$($workloadAdmins.Id)_$($reader.Id)" -notin ($wlExisting | ForEach-Object { "$($_.ObjectId)_$($_.RoleDefinitionId)" })){
                try {
                    Write-Verbose "$logPrefix Creating permanent Reader assignment for WorkloadPlane-Admins: $($workloadAdmins.Id)"
                    New-AzRoleAssignment -ResourceGroupName $resourceGroup.ResourceGroupName -RoleDefinitionName $reader.Name -ObjectId $workloadAdmins.Id | Out-Null
                } catch {
                    Write-Verbose "$logPrefix Failed to create Reader assignment for WorkloadPlane-Admins"
                    Write-Error $_
                }
            }
        }

        if($rbacModel -in ("PIM","Both")){
            try{
                Write-Verbose "$logPrefix Getting PIM Eligible Assignments"
                $existing = Get-AzRoleEligibilitySchedule -Scope $resourceGroup.ResourceId
                $eligibleRbacSet += $existing|Select-Object @{n="c";e={$_.RoleDefinitionDisplayName + "_" + $_.PrincipalId}}|ForEach-Object c
            }catch{
                Write-Verbose "$logPrefix Failed to get PIM Eligible Assignments"
                Write-Error $_
            }

            # Check for inherited PIM eligible assignments at parent scopes (Subscription, MG, Tenant Root)
            # so we skip redundant RG-level assignments for Contributor and UAA.
            $subscriptionScope = "/subscriptions/$((Get-AzContext).Subscription.Id)"
            $inheritedEligible = @()

            # Check ManagementPlane-Admins for inherited Contributor eligibility
            $skipContributorForMgmt = $false
            if ($management) {
                try {
                    Write-Verbose "$logPrefix Checking inherited PIM eligible assignments for ManagementPlane-Admins ($($management.Id))"
                    $mgmtInherited = Get-AzRoleEligibilityScheduleInstance -Scope $subscriptionScope `
                        -Filter "principalId eq '$($management.Id)'" -ErrorAction Stop
                    if ($mgmtInherited | Where-Object {
                        $_.RoleDefinitionDisplayName -eq $contributor.Name -and
                        $_.Scope -ne $resourceGroup.ResourceId
                    }) {
                        Write-Verbose "$logPrefix ManagementPlane-Admins already has Contributor eligible at a higher scope — skipping RG assignment"
                        $skipContributorForMgmt = $true
                    }
                } catch {
                    Write-Verbose "$logPrefix Failed to check inherited eligible assignments for ManagementPlane-Admins: $_"
                }
            }

            # Check ControlPlane-Admins for inherited UAA eligibility
            $skipUaaForControl = $false
            if ($control -and -not $SkipControlPlaneDelegation) {
                try {
                    Write-Verbose "$logPrefix Checking inherited PIM eligible assignments for ControlPlane-Admins ($($control.Id))"
                    $ctrlInherited = Get-AzRoleEligibilityScheduleInstance -Scope $subscriptionScope `
                        -Filter "principalId eq '$($control.Id)'" -ErrorAction Stop
                    if ($ctrlInherited | Where-Object {
                        $_.RoleDefinitionDisplayName -eq $userAccessAdmin.Name -and
                        $_.Scope -ne $resourceGroup.ResourceId
                    }) {
                        Write-Verbose "$logPrefix ControlPlane-Admins already has User Access Administrator eligible at a higher scope — skipping RG assignment"
                        $skipUaaForControl = $true
                    }
                } catch {
                    Write-Verbose "$logPrefix Failed to check inherited eligible assignments for ControlPlane-Admins: $_"
                }
            }

            if(-not $skipContributorForMgmt -and "$($contributor.Name)_$($management.Id)" -notin $eligibleRbacSet){
                $toAdd += @{
                    RoleDefinitionId = "$roleDefinitionPrefix/$($contributor.Id)"
                    RoleId = $contributor.Id
                    PrincipalId = $management.Id
                }
            }
            if(-not $skipUaaForControl -and "$($userAccessAdmin.Name)_$($control.Id)" -notin $eligibleRbacSet -and -not $SkipControlPlaneDelegation){
                $toAdd += @{
                    RoleDefinitionId = "$roleDefinitionPrefix/$($userAccessAdmin.Id)"
                    RoleId = $userAccessAdmin.Id
                    PrincipalId = $control.Id
                }
            }
            if($workloadAdmins -and "$($contributor.Name)_$($workloadAdmins.Id)" -notin $eligibleRbacSet){
                $toAdd += @{
                    RoleDefinitionId = "$roleDefinitionPrefix/$($contributor.Id)"
                    RoleId = $contributor.Id
                    PrincipalId = $workloadAdmins.Id
                }
            }

            # Constrained RBAC Administrator for ManagementPlane-Admins
            # May assign any role EXCEPT high-privileged roles, only to the WorkloadPlane-Admins group
            if ($workloadAdmins -and $management -and
                "$($rbacAdmin.Name)_$($management.Id)" -notin $eligibleRbacSet) {
                
                # Load excluded role IDs from configuration or use defaults
                $highPrivRoleIds = @(
                    "8e3af657-a8ff-443c-a75c-2fe8c4bcb635",  # Owner
                    "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9",  # User Access Administrator
                    "f58310d9-a9f6-439a-9e8d-f62e7b41a168"   # Role Based Access Control Administrator
                )
                if ($constrainedDelegationConfig -and $constrainedDelegationConfig.ManagementPlane.ExcludedRoleDefinitionIds) {
                    $highPrivRoleIds = $constrainedDelegationConfig.ManagementPlane.ExcludedRoleDefinitionIds
                    Write-Verbose "$logPrefix Using ManagementPlane excluded role IDs from configuration: $($highPrivRoleIds -join ', ')"
                }
                
                $excludeRolesStr = ($highPrivRoleIds -join ", ")
                $mgmtCondition = (
                    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'}))" +
                    " OR " +
                    "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAllOfAnyValues:GuidNotEquals {$excludeRolesStr}" +
                    " AND " +
                    "@Request[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAnyValues:GuidEquals {$($workloadAdmins.Id)}))" +
                    " AND " +
                    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}))" +
                    " OR " +
                    "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAllOfAnyValues:GuidNotEquals {$excludeRolesStr}" +
                    " AND " +
                    "@Resource[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAnyValues:GuidEquals {$($workloadAdmins.Id)}))"
                )
                $toAdd += @{
                    RoleDefinitionId = "$roleDefinitionPrefix/$($rbacAdmin.Id)"
                    RoleId           = $rbacAdmin.Id
                    PrincipalId      = $management.Id
                    Condition        = $mgmtCondition
                    ConditionVersion = "2.0"
                }
            }

            # Constrained RBAC Administrator for WorkloadPlane-Admins
            # May assign only data-plane roles (Key Vault, Storage) to the WorkloadPlane-Users group
            if ($workloadAdmins -and $workloadUsers -and
                "$($rbacAdmin.Name)_$($workloadAdmins.Id)" -notin $eligibleRbacSet) {
                
                # Load allowed role IDs from configuration or use defaults
                $dataPlaneRoleIds = @(
                    # Key Vault
                    "00482a5a-887f-4fb3-b363-3b7fe8e74483",  # Key Vault Administrator
                    "a4417e6f-fecd-4de8-b567-7b0420556985",  # Key Vault Certificates Officer
                    "14b46e9e-c2b7-41b4-b07b-48a6ebf60603",  # Key Vault Crypto Officer
                    "12338af0-0e69-4776-bea7-57ae8d297424",  # Key Vault Crypto User
                    "21090545-7ca7-4776-b22c-e363652d74d2",  # Key Vault Reader
                    "b86a8fe4-44ce-4948-aee5-eccb2c155cd7",  # Key Vault Secrets Officer
                    "4633458b-17de-408a-b874-0445c86b69e6",  # Key Vault Secrets User
                    # Storage
                    "ba92f5b4-2d11-453d-a403-e96b0029c9fe",  # Storage Blob Data Contributor
                    "b7e6dc6d-f1e8-4753-8033-0f276bb0955b",  # Storage Blob Data Owner
                    "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1",  # Storage Blob Data Reader
                    "0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3",  # Storage Table Data Contributor
                    "76199698-9eea-4c19-bc75-cec21354c6b6",  # Storage Table Data Reader
                    "974c5e8b-45b9-4653-ba55-5f855dd0fb88",  # Storage Queue Data Contributor
                    "19e7f393-937e-4f77-808e-94535e297925",  # Storage Queue Data Reader
                    "8a0f0c08-91a1-4084-bc3d-661d67233fed",  # Storage Queue Data Message Processor
                    "c6a89b2d-59bc-44d0-9896-0f6e12d7b80a"   # Storage Queue Data Message Sender
                )
                if ($constrainedDelegationConfig -and $constrainedDelegationConfig.WorkloadPlane.AllowedRoleDefinitionIds) {
                    $dataPlaneRoleIds = $constrainedDelegationConfig.WorkloadPlane.AllowedRoleDefinitionIds
                    Write-Verbose "$logPrefix Using WorkloadPlane allowed role IDs from configuration: $($dataPlaneRoleIds.Count) roles"
                }
                
                $allowRolesStr = ($dataPlaneRoleIds -join ", ")
                $wlCondition = (
                    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'}))" +
                    " OR " +
                    "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$allowRolesStr}" +
                    " AND " +
                    "@Request[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAnyValues:GuidEquals {$($workloadUsers.Id)}))" +
                    " AND " +
                    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}))" +
                    " OR " +
                    "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$allowRolesStr}" +
                    " AND " +
                    "@Resource[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAnyValues:GuidEquals {$($workloadUsers.Id)}))"
                )
                $toAdd += @{
                    RoleDefinitionId = "$roleDefinitionPrefix/$($rbacAdmin.Id)"
                    RoleId           = $rbacAdmin.Id
                    PrincipalId      = $workloadAdmins.Id
                    Condition        = $wlCondition
                    ConditionVersion = "2.0"
                }
            }

            foreach($add in $toAdd){
                $scheduleRequestParams.Name = [guid]::NewGuid()
                $scheduleRequestParams.RoleDefinitionId = $add.RoleDefinitionId
                $scheduleRequestParams.PrincipalId = $add.PrincipalId

                if ($add.Condition) {
                    $scheduleRequestParams.Condition = $add.Condition
                    $scheduleRequestParams.ConditionVersion = $add.ConditionVersion
                } else {
                    $scheduleRequestParams.Remove('Condition') | Out-Null
                    $scheduleRequestParams.Remove('ConditionVersion') | Out-Null
                }

                try{
                    Write-Verbose "$logPrefix Getting role management policy for: $($add.RoleId)"
                    $policy = Get-AzRoleManagementPolicy -Scope $scheduleRequestParams.Scope -Name $add.RoleId
                }catch{
                    Write-Verbose "$logPrefix Failed to get role management policy"
                    Write-Error $_
                }
                if(($policy.Rule|Where-Object{$_.Id -eq "Expiration_Admin_Eligibility"}).IsExpirationRequired){
                    Write-Verbose "$logPrefix Policy requires eligible expiration, updating"
                    $roleManagementPolicySplat = @{
                        Scope = $resourceGroup.ResourceId
                        Name = $add.RoleId
                        Rule = @{
                            id = "Expiration_Admin_Eligibility"
                            IsExpirationRequired = $false
                            ruleType = "RoleManagementPolicyExpirationRule"
                        }
                    }
                    try{
                        Update-AzRoleManagementPolicy @roleManagementPolicySplat
                    }catch{
                        Write-Verbose "$logPrefix Failed to update role management policy rules"
                        Write-Error $_
                    }
                }

                try{
                    Write-Verbose "$logPrefix Creating PIM Eligible Assignment for PrincipalId: $($add.PrincipalId)"
                    $rbacSet += New-AzRoleEligibilityScheduleRequest @scheduleRequestParams
                }catch{
                    Write-Verbose "$logPrefix Failed to create PIM Eligible Assignment"
                    Write-Error $_
                }
            }
        }
    }

    end {
        return [psobject]$resourceGroup
    }
}