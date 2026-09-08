<#
.SYNOPSIS
    Recursively sorts object property names and selected collection elements alphabetically.

.DESCRIPTION
    Microsoft Graph / UTCM can return a captured resource's dynamic 'properties' bag with a
    different key order between two otherwise-identical calls (the underlying export mechanism
    appears to enumerate a non-ordered dictionary). Serializing that object as-is with
    ConvertTo-Json therefore produces a large, purely cosmetic Git diff on every run even when no
    property value actually changed (e.g. every single key of a role definition's 'properties'
    object reordered between two runs).

    This helper makes serialization deterministic without changing positional data: PSCustomObject
    and dictionary/hashtable property names are sorted alphabetically at every nesting level, while
    collection element order is preserved by default. Only collection paths explicitly supplied via
    CollectionPathsToSort are sorted. Their elements are normalized first and then compared by their
    compact JSON representation using a culture-independent, case-insensitive comparison with an
    ordinal tie-breaker.

    This opt-in behavior is intended for collections that are semantically sets and whose source
    order is unstable, such as the Members collection of an administrative unit. Positional
    collections such as approval stages remain in the order returned by Graph.

.PARAMETER InputObject
    The object (or array/hashtable/PSCustomObject) to sort. Typically a captured Tenant Governance
    resource object before it's passed to ConvertTo-Json.

.PARAMETER CollectionPathsToSort
    Dot-separated property paths whose collection elements should be sorted. All other collection
    element order is retained. Path matching is case-insensitive.

.EXAMPLE
    $SortedResource = ConvertTo-EntraOpsSortedObject -InputObject $Resource -CollectionPathsToSort 'properties.Members'
    $SortedResource | ConvertTo-Json -Depth 10 | Out-File -Path $ResourceFilePath -Encoding utf8
#>
function ConvertTo-EntraOpsSortedObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        $InputObject
        ,
        [Parameter(Mandatory = $false)]
        [System.String[]]$CollectionPathsToSort = @()
        ,
        [Parameter(Mandatory = $false, DontShow = $true)]
        [System.String]$CurrentPath = ''
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        # Ordinal key ordering. Sort-Object - with or without -CaseSensitive - compares using the
        # current culture, so the same snapshot can serialize in a different key order on a runner with
        # a different locale, producing a purely cosmetic diff. StringComparer::Ordinal compares by
        # code point and is therefore identical everywhere, which is the whole point of this helper.
        if ($InputObject -is [System.Collections.IDictionary]) {
            $Sorted = [ordered]@{}
            $OrderedKeys = [string[]]@($InputObject.Keys)
            [Array]::Sort($OrderedKeys, [StringComparer]::Ordinal)
            foreach ($Key in $OrderedKeys) {
                $ChildPath = if ([string]::IsNullOrEmpty($CurrentPath)) { $Key } else { "$CurrentPath.$Key" }
                $Sorted[$Key] = ConvertTo-EntraOpsSortedObject -InputObject $InputObject[$Key] -CollectionPathsToSort $CollectionPathsToSort -CurrentPath $ChildPath
            }
            return $Sorted
        }

        # PSCustomObject (typical shape for Graph SDK / Invoke-MgGraphRequest -OutputType PSObject
        # results): sort property names, recurse into values.
        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $Sorted = [ordered]@{}
            $OrderedNames = [string[]]@($InputObject.PSObject.Properties.Name)
            [Array]::Sort($OrderedNames, [StringComparer]::Ordinal)
            foreach ($PropertyName in $OrderedNames) {
                $ChildPath = if ([string]::IsNullOrEmpty($CurrentPath)) { $PropertyName } else { "$CurrentPath.$PropertyName" }
                $Sorted[$PropertyName] = ConvertTo-EntraOpsSortedObject -InputObject $InputObject.$PropertyName -CollectionPathsToSort $CollectionPathsToSort -CurrentPath $ChildPath
            }
            # Return the ordered dictionary as-is (same as the IDictionary branch above) instead of
            # casting to [PSCustomObject] - that cast throws "the value of the argument 'name' is not
            # valid" if any property name isn't a syntactically valid PS member name (e.g. an empty
            # string, which Graph/UTCM dynamic 'properties' bags can contain). ConvertTo-Json - the
            # only consumer of this function's output - serializes an ordered dictionary identically.
            return $Sorted
        }

        # Strings are IEnumerable (of chars) - return as-is, do not treat as a collection to recurse into.
        if ($InputObject -is [string]) {
            return $InputObject
        }

        # Arrays/collections: always recurse, but retain element order unless this exact property path
        # was explicitly identified as a semantically unordered collection.
        if ($InputObject -is [System.Collections.IEnumerable]) {
            $Result = [System.Collections.Generic.List[object]]::new()
            foreach ($Item in $InputObject) {
                $Result.Add((ConvertTo-EntraOpsSortedObject -InputObject $Item -CollectionPathsToSort $CollectionPathsToSort -CurrentPath $CurrentPath))
            }

            if ($CollectionPathsToSort -notcontains $CurrentPath) {
                # The leading comma prevents PowerShell from unrolling a single-element (or empty)
                # array back into a bare scalar/nothing when captured by the caller.
                return , $Result.ToArray()
            }

            # Sort selected collections by their canonical JSON forms. OrdinalIgnoreCase provides
            # expected alphabetical ordering for identity names; ordinal comparison breaks ties.
            $SortableItems = [System.Collections.Generic.List[object]]::new()
            foreach ($SortedItem in $Result) {
                $SortableItems.Add([PSCustomObject]@{
                        Value   = $SortedItem
                        # -InputObject rather than the pipeline: piping unrolls a nested collection,
                        # which would give @('a') and 'a' the same key and make their relative order
                        # depend on the input order again.
                        SortKey = (ConvertTo-Json -InputObject $SortedItem -Depth 100 -Compress)
                    })
            }

            $Comparison = [System.Comparison[object]] {
                param ($Left, $Right)

                $Result = [System.StringComparer]::OrdinalIgnoreCase.Compare($Left.SortKey, $Right.SortKey)
                if ($Result -eq 0) {
                    $Result = [System.StringComparer]::Ordinal.Compare($Left.SortKey, $Right.SortKey)
                }
                return $Result
            }
            $SortableItems.Sort($Comparison)

            $Result = [System.Collections.Generic.List[object]]::new()
            foreach ($SortableItem in $SortableItems) {
                $Result.Add($SortableItem.Value)
            }
            # The leading comma prevents PowerShell from unrolling a single-element (or empty) array
            # back into a bare scalar/nothing when this function's output is captured by the caller
            # (e.g. $Sorted[$PropertyName] = ConvertTo-EntraOpsSortedObject ...) - without it, a
            # 1-item array like @("/") would collapse to the bare string "/", silently corrupting data.
            return , $Result.ToArray()
        }

        # Primitive/scalar value (bool, int, string subtype, etc.) - return as-is.
        return $InputObject
    }
}
