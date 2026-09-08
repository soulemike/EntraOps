<#
.SYNOPSIS
    Normalizes an arbitrary string (e.g. a Microsoft Graph displayName) into a single filesystem
    path segment that is safe to create, commit, and check out on Windows, Linux, and macOS.

.DESCRIPTION
    Tenant Governance (UTCM) snapshot resources are persisted in folders and files named after their
    resourceType and displayName. Display names returned by Graph regularly contain characters that
    are invalid or problematic in a path segment, which either breaks the export or - worse - produces
    a repository that cannot be checked out on Windows ("error: invalid path ...") even though the
    files were committed successfully from a Linux runner. This helper applies a single, portable
    normalization for all of them:

    - Unicode is normalized to form C so the same display name yields the same file name on macOS
      (which prefers decomposed form) and Windows/Linux.
    - Characters that are invalid in a file name on *any* supported platform are replaced with "_".
      This includes the Windows reserved set (< > : " / \ | ? *), both path separators, and control
      characters - regardless of the platform the export runs on, because
      [System.IO.Path]::GetInvalidFileNameChars() only reports the current platform's restrictions
      (on Linux it returns just "/" and NUL, so a ":" would pass through and break Windows clients).
    - PowerShell wildcard characters ("[" and "]") are replaced as well. They are legal file names,
      but cmdlets resolve -Path as a wildcard pattern, so a resource such as "[EMEA Device
      Administrator]" fails with "the wildcard path ... did not resolve to a file".
    - Leading/trailing whitespace and trailing dots are removed (Windows silently strips them, which
      would otherwise cause a mismatch between the intended and the created file name).
    - Windows reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9), including names followed
      by an extension, are prefixed with "_".
    - Empty results fall back to -FallbackName, and the segment length is capped through
      Limit-EntraOpsFilePathSegmentLength.

.PARAMETER Segment
    The raw path segment (folder or file name, without extension) to normalize.

.PARAMETER FallbackName
    Name to use when the segment is empty or consists only of characters that were removed.
    Default is "Unnamed".

.PARAMETER MaxLength
    Maximum allowed UTF-8 byte length of the returned segment. Default is 100.

.EXAMPLE
    ConvertTo-EntraOpsSafeFilePathSegment -Segment 'Admin 4: Require MFA'
    Returns "Admin 4_ Require MFA".

.EXAMPLE
    ConvertTo-EntraOpsSafeFilePathSegment -Segment '[EMEA Device Administrator]'
    Returns "_EMEA Device Administrator_".
#>
function ConvertTo-EntraOpsSafeFilePathSegment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [System.String]$Segment
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$FallbackName = 'Unnamed'
        ,
        [Parameter(Mandatory = $false)]
        [ValidateRange(9, 2147483647)]
        [System.Int32]$MaxLength = 100
    )

    if ([string]::IsNullOrWhiteSpace($Segment)) {
        return $FallbackName
    }

    $InvalidChars = @(
        [System.IO.Path]::GetInvalidFileNameChars()
        [System.IO.Path]::DirectorySeparatorChar
        [System.IO.Path]::AltDirectorySeparatorChar
        [char[]]'<>:"/\|?*[]'
        0..31 | ForEach-Object { [char]$_ }
    ) | Select-Object -Unique
    # Encode every character as \uXXXX so characters with a special meaning inside a character class
    # (e.g. "]" or "-") cannot terminate or alter the class.
    $InvalidCharsPattern = '[{0}]' -f (($InvalidChars | ForEach-Object { '\u{0:x4}' -f [int]$_ }) -join '')

    $SafeSegment = $Segment.Normalize([System.Text.NormalizationForm]::FormC)
    $SafeSegment = $SafeSegment -replace $InvalidCharsPattern, '_'
    # Windows drops trailing dots and spaces from file and folder names.
    $SafeSegment = $SafeSegment.Trim().TrimEnd('.', ' ')

    if ([string]::IsNullOrWhiteSpace($SafeSegment)) {
        return $FallbackName
    }

    # Windows treats device names as reserved even when they are followed by an extension. The
    # superscript variants are reserved for compatibility with the historical DOS device names too.
    if ($SafeSegment -match '^(CON|PRN|AUX|NUL|COM(?:[1-9]|[¹²³])|LPT(?:[1-9]|[¹²³]))(?:\..*)?$') {
        $SafeSegment = "_$SafeSegment"
    }

    return Limit-EntraOpsFilePathSegmentLength -Segment $SafeSegment -MaxLength $MaxLength
}
