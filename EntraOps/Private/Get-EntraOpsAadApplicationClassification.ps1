function Get-EntraOpsAadApplicationClassification {
    <#
    .SYNOPSIS
        Classifies an AadApplication access package resource from ResourceApps EAM data.
    .DESCRIPTION
        AadApplication originIds are service-principal object IDs; the tier is resolved from the
        service principal's own ResourceApps (workload identity) classification.

        The resulting tier is a PROXY: an app role assignment grants access to the application,
        not the application's API permissions. The heuristic is that access to an app which
        itself holds privileged permissions is equivalent exposure (the app is an escalation
        vector for whoever can use it). A known app without privileged classifications is
        UserAccess; an unresolved service principal fails closed to ControlPlane with a warning.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalObjectId,

        [Parameter(Mandatory = $true)]
        [hashtable]$ClassificationCache,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [string]$ContextLabel,

        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.List[psobject]]$WarningMessages
    )

    $ResourceAppsIndex = $ClassificationCache['ResourceApps:ByObjectId']
    $MatchedApplications = if ($null -ne $ResourceAppsIndex) { @($ResourceAppsIndex[$ServicePrincipalObjectId]) } else { @() }
    if ($MatchedApplications.Count -eq 0) {
        if ($null -ne $WarningMessages) {
            $WarningMessages.Add([pscustomobject]@{
                    Type    = 'Unresolved AadApplication'
                    Message = "AadApplication '$DisplayName' ($ServicePrincipalObjectId) in $ContextLabel was not found in ResourceApps classification - treated as ControlPlane (conservative)."
                    Target  = $ServicePrincipalObjectId
                })
        }
        return [pscustomobject]@{
            AdminTierLevel     = '0'
            AdminTierLevelName = 'ControlPlane'
            Service            = 'Application Access'
        }
    }

    # Real ResourceApps exports carry explicit 'Unclassified' entries (including apps whose ONLY
    # entries are Unclassified). Those are deliberately dropped here: an explicitly-Unclassified-only
    # app IS a "known app without privileged classifications" per this helper's contract and maps to
    # UserAccess - it is not dropped data, the ResourceApps pipeline reviewed the app and classified
    # none of its permissions as privileged. Only real tier classifications are returned.
    $Classifications = @($MatchedApplications | ForEach-Object { $_.Classification } | Where-Object { $null -ne $_ -and $_.AdminTierLevelName -and "$($_.AdminTierLevelName)" -ne 'Unclassified' })
    if ($Classifications.Count -eq 0) {
        return [pscustomobject]@{
            AdminTierLevel     = '2'
            AdminTierLevelName = 'UserAccess'
            Service            = 'Application Access'
        }
    }

    return $Classifications
}