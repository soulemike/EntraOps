function Set-EntraOpsEAMClassificationJustification {
    <#
    .SYNOPSIS
        Adds or removes the Justification property on all Classification entries of EAM output objects.
    .DESCRIPTION
        Shared helper called as the last step of every Get-EntraOpsPrivilegedEAM<System> cmdlet to control
        whether the Justification property (documenting a manual classification overwrite) is present on
        the Classification arrays of the returned objects - both the object-level aggregated Classification
        property and the per-assignment Classification property nested under RoleAssignments.

        Justification is $null/empty unless the underlying classification entry was produced by a documented
        overwrite (Classification_RoleActionOverwrites.json, Classification_RoleDefinitionOverwrites.json or
        Classification_ApiPermissionOverwrites.json). By default the property is removed entirely from the
        export to avoid always-empty noise; pass -IncludeJustification to keep it (populated where an
        overwrite justification is available, $null otherwise).
    .PARAMETER EamData
        Array of standardized EAM output objects (as built by New-EntraOpsEAMOutputObject /
        Invoke-EntraOpsEAMClassificationAggregation, or the custom object shapes built by
        Get-EntraOpsPrivilegedEAMResourceApps) to process.
    .PARAMETER IncludeJustification
        If specified, ensures the Justification property is present on all Classification entries
        (defaulting to $null when not otherwise populated). If omitted (default), the property is removed.
    .OUTPUTS
        [array] The same EAM output objects, with Justification added or removed on all Classification entries.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyCollection()]
        [array]$EamData,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeJustification
    )

    begin {
        $Include = $IncludeJustification.IsPresent

        function Update-ClassificationEntryJustification {
            param (
                [array]$ClassificationEntries,
                [bool]$Include
            )

            foreach ($Entry in @($ClassificationEntries)) {
                if ($null -eq $Entry) { continue }

                if ($Include) {
                    if ($null -eq $Entry.PSObject.Properties['Justification']) {
                        $Entry | Add-Member -NotePropertyName 'Justification' -NotePropertyValue $null -Force
                    }
                } elseif ($null -ne $Entry.PSObject.Properties['Justification']) {
                    $Entry.PSObject.Properties.Remove('Justification')
                }
            }
        }
    }

    process {
        foreach ($Object in @($EamData)) {
            if ($null -eq $Object) { continue }

            Update-ClassificationEntryJustification -ClassificationEntries $Object.Classification -Include $Include

            foreach ($Assignment in @($Object.RoleAssignments)) {
                if ($null -ne $Assignment) {
                    Update-ClassificationEntryJustification -ClassificationEntries $Assignment.Classification -Include $Include
                }
            }

            $Object
        }
    }
}
