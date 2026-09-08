<#
.SYNOPSIS
    Truncates a single filesystem path segment (folder or file name, without extension) to a safe
    maximum UTF-8 byte length, appending a short content hash to avoid collisions when truncation
    happens.

.DESCRIPTION
    Most filesystems (e.g. ext4 on the Linux GitHub Actions runners) reject any single path
    component longer than 255 bytes ("File name too long" / "path is too long, or a component of
    the specified path is too long"). Tenant Governance (UTCM) snapshot resources are expected to
    expose a human-readable 'displayName', but some resource types (e.g.
    microsoft.entra.crossTenantAccessPolicyConfigurationPartner, which is keyed by PartnerTenantId
    rather than DisplayName) have been observed to return a malformed/garbled displayName value from
    the Graph service (e.g. containing concatenated ".ToString()" representations of nested
    hashtables) that can be hundreds of characters long. This helper defensively caps the length of
    any path segment derived from such values, regardless of the root cause, so
    Save-EntraOpsTenantGovernanceSnapshotJson never fails to persist a captured resource because of
    an oversized file or folder name. The limit is measured in UTF-8 bytes rather than .NET string
    characters because filesystems such as ext4 enforce their component limit in bytes. Truncation
    occurs only between Unicode text elements, so surrogate pairs and combining sequences remain
    intact.

.PARAMETER Segment
    The path segment (folder or file name, without extension) to check/truncate.

.PARAMETER MaxLength
    Maximum allowed UTF-8 byte length of the segment. Default is 100 (well under the 255-byte
    filesystem limit, leaving headroom for the parent path and, for file names, the ".json"
    extension). Must be at least 9 bytes to accommodate the content-hash suffix.

.EXAMPLE
    Limit-EntraOpsFilePathSegmentLength -Segment $SafeFileNameSegment
#>
function Limit-EntraOpsFilePathSegmentLength {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]$Segment
        ,
        [Parameter(Mandatory = $false)]
        [ValidateRange(9, 2147483647)]
        [System.Int32]$MaxLength = 100
    )

    $Utf8Encoding = [System.Text.UTF8Encoding]::new($false)
    if ($Utf8Encoding.GetByteCount($Segment) -le $MaxLength) {
        return $Segment
    }

    # Append a short content hash so different overlong values that share the same prefix don't
    # collide/overwrite each other once truncated.
    $HashBytes = [System.Security.Cryptography.MD5]::HashData($Utf8Encoding.GetBytes($Segment))
    $HashSuffix = ([System.BitConverter]::ToString($HashBytes) -replace '-', '').Substring(0, 8)

    $Suffix = "_$HashSuffix"
    $PrefixByteBudget = $MaxLength - $Utf8Encoding.GetByteCount($Suffix)
    $PrefixBuilder = [System.Text.StringBuilder]::new()
    $PrefixByteCount = 0
    $TextElementEnumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Segment)

    while ($TextElementEnumerator.MoveNext()) {
        $TextElement = [System.String]$TextElementEnumerator.Current
        $TextElementByteCount = $Utf8Encoding.GetByteCount($TextElement)
        if (($PrefixByteCount + $TextElementByteCount) -gt $PrefixByteBudget) {
            break
        }

        [void]$PrefixBuilder.Append($TextElement)
        $PrefixByteCount += $TextElementByteCount
    }

    return "$($PrefixBuilder.ToString().TrimEnd())$Suffix"
}
