<#
.SYNOPSIS
    Recursively converts PSCustomObjects (e.g. from Invoke-RestMethod) to case-insensitive hashtables.

.DESCRIPTION
    Invoke-MgGraphRequest -OutputType HashTable returns case-INsensitive hashtables, while
    ConvertFrom-Json -AsHashtable creates case-SENSITIVE OrderedHashtables. Consumers across the
    module access Graph properties with varying casing (e.g. $_.Id for the JSON key "id"), which
    works against the Graph SDK output but silently returns $null on a case-sensitive hashtable.
    The Invoke-RestMethod code path (UseInvokeRestMethodOnly) therefore must deliver its HashTable
    output through this converter to behave identically to the Graph SDK.

.PARAMETER InputObject
    Object graph to convert: dictionaries and PSCustomObjects become case-insensitive hashtables,
    arrays are converted element-wise, scalars pass through unchanged.
#>
function ConvertTo-EntraOpsCaseInsensitiveHashtable {
    param (
        [Parameter(Mandatory = $false)]
        $InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $Converted = @{}
        foreach ($Key in $InputObject.Keys) {
            $Converted[$Key] = ConvertTo-EntraOpsCaseInsensitiveHashtable -InputObject $InputObject[$Key]
        }
        return $Converted
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $Converted = @{}
        foreach ($Property in $InputObject.PSObject.Properties) {
            $Converted[$Property.Name] = ConvertTo-EntraOpsCaseInsensitiveHashtable -InputObject $Property.Value
        }
        return $Converted
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        # Comma operator keeps the array intact (a bare return would unroll it in the pipeline
        # and collapse single-element or empty arrays)
        return , @($InputObject | ForEach-Object { ConvertTo-EntraOpsCaseInsensitiveHashtable -InputObject $_ })
    }

    return $InputObject
}
