<#
.SYNOPSIS
    Creates Entra security and Microsoft 365 groups for each service role.

.DESCRIPTION
    Creates one Entra group per entry in the ServiceRoles object. Security groups
    are created for all roles with an empty or set groupType. Microsoft 365
    (Unified) groups are created for roles with groupType = "Unified".
    When ProhibitDirectElevation is not set, PIM staging groups (*-PIM-*) are
    also created for each non-Members admin group to support PIM for Groups.

    Group names follow the convention:
    <GroupPrefix><Delimiter><ServiceName><Delimiter><AccessLevel><Delimiter><RoleName>

    Idempotent: existing groups (matched by MailNickname prefix) are reused.
    Only called directly for custom implementations; New-EntraOpsServiceBootstrap
    is the standard entry point.

.PARAMETER ServiceName
    Name of the service. Forms the central segment of the group MailNickname
    and DisplayName.

.PARAMETER ServiceOwner
    Graph API owner URL for the group owner, in the form:
    "https://graph.microsoft.com/v1.0/users/<ObjectId>"
    
    This can also be provided as just the ObjectId (GUID), and the function
    will automatically construct the proper OData bind URL.

.PARAMETER GroupPrefix
    Prefix prepended to all group DisplayNames and MailNicknames. Defaults to "SG".

.PARAMETER GroupNamingDelimiter
    Delimiter between name segments. Defaults to "-".

.PARAMETER ServiceRoles
    EntraOps service roles object. Each row produces one group. The accessLevel,
    name, and groupType columns control the group variant.

.PARAMETER IsAssignableToRole
    When set, creates groups with IsAssignableToRole = $true, enabling them for
    Entra ID role assignment. Requires the calling identity to have the
    Privileged Role Administrator role.

.PARAMETER ProhibitDirectElevation
    When set, skips creation of PIM staging groups (*-PIM-*). Use this when PIM
    for Groups is not required (e.g. access-package-only elevation).

.PARAMETER logPrefix
    Text prepended to verbose messages. Defaults to the function name.

.EXAMPLE
    New-EntraOpsServiceEntraGroup `
        -ServiceName "MyService" `
        -ServiceOwner "https://graph.microsoft.com/v1.0/users/00000000-0000-0000-0000-000000000001" `
        -ServiceRoles $roles

    Creates all security and Microsoft 365 groups for "MyService", including PIM
    staging groups. Returns all group objects.

.EXAMPLE
    New-EntraOpsServiceEntraGroup `
        -ServiceName "MyService" `
        -ServiceOwner "https://graph.microsoft.com/v1.0/users/00000000-0000-0000-0000-000000000001" `
        -ServiceRoles $roles `
        -ProhibitDirectElevation

    Creates groups without PIM staging groups.

#>
function New-EntraOpsServiceEntraGroup {
    [OutputType([psobject[]])]
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [string]$ServiceOwner,

        [string]$GroupPrefix = "SG",
        [string]$GroupNamingDelimiter = "-",

        [Parameter(Mandatory)]
        [psobject[]]$ServiceRoles,

        [Parameter()]
        [switch]$IsAssignableToRole,

        [switch]$ProhibitDirectElevation,

        [string]$logPrefix = "[$($MyInvocation.MyCommand)]"
    )

    begin {
        # Issue 4.1: Validate and normalize ServiceOwner to proper OData bind format
        if ([string]::IsNullOrWhiteSpace($ServiceOwner)) {
            throw "ServiceOwner parameter is required. Provide either a full OData URL (https://graph.microsoft.com/v1.0/users/<ObjectId>) or just the user ObjectId (GUID)."
        }
        
        # Check if ServiceOwner is already in OData URL format
        if ($ServiceOwner -match '^https://graph\.microsoft\.com/v1\.0/users/') {
            $ownerUri = $ServiceOwner
            Write-Verbose "$logPrefix ServiceOwner provided as OData URL: $ownerUri"
        } else {
            # Assume it's just an ObjectId and construct the OData URL
            # Validate it looks like a GUID
            if ($ServiceOwner -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                $ownerUri = "https://graph.microsoft.com/v1.0/users/$ServiceOwner"
                Write-Verbose "$logPrefix ServiceOwner converted to OData URL: $ownerUri"
            } else {
                throw "ServiceOwner must be either a valid GUID (ObjectId) or a full OData URL (https://graph.microsoft.com/v1.0/users/<ObjectId>). Received: $ServiceOwner"
            }
        }
        
        try{
            #Groups
            $groups = @()
            Write-Verbose "$logPrefix Looking up Groups"
            $groups += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/groups?`$search=`"mailNickname:$ServiceName.`"" -ConsistencyLevel "eventual" -OutputType PSObject
            if(-not $ProhibitDirectElevation){
                $groups += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/groups?`$search=`"mailNickname:PIM.$ServiceName.`"" -ConsistencyLevel "eventual" -OutputType PSObject
            }
        }catch{
            Write-Verbose "$logPrefix Failed processing Groups"
            Write-Error $_
        }
        $groupParams = @{
            description = ""
            securityEnabled = $true
            isAssignableToRole = [bool]$IsAssignableToRole
            "owners@odata.bind" = @($ownerUri)
        }
        $unifiedParams = $groupParams + @{
            displayName = ""
            mailNickname = ""
            groupTypes = @("Unified")
            mailEnabled = $true
            #"members@odata.bind" = $members
        }
        $secParams = $groupParams + @{
            displayName = ""
            mailNickname = ""
            mailEnabled = $false
        }
    }

    process {
        Write-Verbose "$logPrefix Processing $(($ServiceRoles|Measure-Object).Count) Groups"
        foreach($ServiceRole in $ServiceRoles){
            # Issue 4.2: Validate and sanitize parameters
            $validationErrors = @()
            
            # Validate ServiceRole properties
            if ([string]::IsNullOrWhiteSpace($ServiceRole.Name)) {
                $validationErrors += "ServiceRole.Name is required"
            }
            
            # Construct names
            $unifiedParams.Description = "Team $(($ServiceRole.accessLevel +" "+ $ServiceRole.name).trim()) supporting $ServiceName"
            $unifiedParams.DisplayName = "$ServiceName $($ServiceRole.Name)"
            $unifiedParams.MailNickname = "$ServiceName.$($ServiceRole.Name)"
            $secParams.Description = "Team $(($ServiceRole.accessLevel +" "+ $ServiceRole.name).trim()) supporting $ServiceName"
            if([string]::IsNullOrEmpty($ServiceRole.accessLevel)){
                $secParams.DisplayName = "$GroupPrefix$($GroupNamingDelimiter)$ServiceName$($GroupNamingDelimiter)$($ServiceRole.Name)"
                $secParams.MailNickname = "$ServiceName.$($ServiceRole.Name)"
            }else{
                $secParams.DisplayName = "$GroupPrefix$($GroupNamingDelimiter)$ServiceName$($GroupNamingDelimiter)$($ServiceRole.accessLevel)$($GroupNamingDelimiter)$($ServiceRole.Name)"
                $secParams.MailNickname = "$ServiceName.$($ServiceRole.accessLevel).$($ServiceRole.Name)"
            }
            
            # Validate displayName length (max 256 chars)
            if ($secParams.DisplayName.Length -gt 256) {
                $validationErrors += "DisplayName '$($secParams.DisplayName)' exceeds maximum length of 256 characters (current: $($secParams.DisplayName.Length))"
            }
            if ($unifiedParams.DisplayName.Length -gt 256) {
                $validationErrors += "DisplayName '$($unifiedParams.DisplayName)' exceeds maximum length of 256 characters (current: $($unifiedParams.DisplayName.Length))"
            }
            
            # Validate mailNickname length (max 64 chars) and format
            $mailNicknamePattern = '^[a-zA-Z0-9_.-]+$'
            if ($secParams.MailNickname.Length -gt 64) {
                $validationErrors += "MailNickname '$($secParams.MailNickname)' exceeds maximum length of 64 characters (current: $($secParams.MailNickname.Length))"
            }
            if ($secParams.MailNickname -notmatch $mailNicknamePattern) {
                $validationErrors += "MailNickname '$($secParams.MailNickname)' contains invalid characters. Only alphanumeric, underscore, dot, and hyphen allowed."
            }
            if ($unifiedParams.MailNickname.Length -gt 64) {
                $validationErrors += "MailNickname '$($unifiedParams.MailNickname)' exceeds maximum length of 64 characters (current: $($unifiedParams.MailNickname.Length))"
            }
            if ($unifiedParams.MailNickname -notmatch $mailNicknamePattern) {
                $validationErrors += "MailNickname '$($unifiedParams.MailNickname)' contains invalid characters. Only alphanumeric, underscore, dot, and hyphen allowed."
            }
            
            # Check for duplicate mailNickname in current batch
            $currentNicknames = $groups | ForEach-Object { $_.MailNickname }
            if ($currentNicknames -contains $secParams.MailNickname) {
                $validationErrors += "MailNickname '$($secParams.MailNickname)' is already used by another group in this deployment"
            }
            if ($currentNicknames -contains $unifiedParams.MailNickname) {
                $validationErrors += "MailNickname '$($unifiedParams.MailNickname)' is already used by another group in this deployment"
            }
            
            # Throw if validation errors found
            if ($validationErrors.Count -gt 0) {
                throw "VALIDATION FAILED for ServiceRole '$($ServiceRole.Name)':`n  - $($validationErrors -join "`n  - ")"
            }
            
            # Issue 4.2: Log payload for debugging
            Write-Verbose "$logPrefix Validated group parameters for '$($ServiceRole.Name)'"
            try{
                if($ServiceRole.groupType -eq "Unified" -and $groups.MailNickname -notcontains $unifiedParams.MailNickname){
                    Write-Verbose "$logPrefix $($unifiedParams|ConvertTo-Json -Compress)"
                    $groups += Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/groups" -Body ($unifiedParams | ConvertTo-Json -Depth 10) -OutputType PSObject
                }elseif($ServiceRole.groupType -like "" -and $groups.MailNickname -notcontains $secParams.MailNickname){
                    Write-Verbose "$logPrefix $($secParams|ConvertTo-Json -Compress)"
                    $groups += Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/groups" -Body ($secParams | ConvertTo-Json -Depth 10) -OutputType PSObject
                    if($ServiceRole.accessLevel -eq "ManagementPlane" -and $ServiceRole.name -eq "Admins" -and -not $ProhibitDirectElevation){
                        $secParams.DisplayName = "$($GroupPrefix)$($GroupNamingDelimiter)PIM$($GroupNamingDelimiter)$ServiceName$($GroupNamingDelimiter)$($ServiceRole.accessLevel)$($GroupNamingDelimiter)$($ServiceRole.Name)"
                        $secParams.MailNickname = "PIM.$ServiceName.$($ServiceRole.accessLevel).$($ServiceRole.Name)"
                        $groups += Invoke-EntraOpsMsGraphQuery -Method POST -Uri "/v1.0/groups" -Body ($secParams | ConvertTo-Json -Depth 10) -OutputType PSObject
                    }
                }
            }catch{
                Write-Verbose "$logPrefix Failed processing Groups"
                Write-Error $_
            }
        }
    }

    end {
        $confirmed = $false
        $i = 0
        Write-Verbose "$logPrefix Verifying Groups are available"
        while(-not $confirmed){
            Start-Sleep -Seconds ([Math]::Pow(2,$i)-1)
            $checkGroups = @()
            $checkGroups += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/groups?`$search=`"mailNickname:$ServiceName.`"" -ConsistencyLevel "eventual" -OutputType PSObject -DisableCache
            if(-not $ProhibitDirectElevation){
                $checkGroups += Invoke-EntraOpsMsGraphQuery -Method GET -Uri "/v1.0/groups?`$search=`"mailNickname:PIM.$ServiceName.`"" -ConsistencyLevel "eventual" -OutputType PSObject -DisableCache
            }
            $refIds = @($groups.id | Where-Object { $_ })
            $chkIds = @($checkGroups.id | Where-Object { $_ })
            if($refIds.Count -gt 0 -and $chkIds.Count -ge $refIds.Count -and (Compare-Object $refIds $chkIds | Measure-Object).Count -eq 0){
                Write-Verbose "$logPrefix Graph consistency found confirming"
                $confirmed = $true
                continue
            }
            $i++
            if($i -gt 5){
                throw "Group object consistency with Entra not achieved"
            }
            Write-Verbose "$logPrefix Graph objects are not available, sleeping $([Math]::Pow(2,$i)-1) seconds"
        }
        return [psobject[]]$checkGroups
    }
}
