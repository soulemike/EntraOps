<#
.SYNOPSIS
    Tests whether a path resolves to a location inside a root directory.

.DESCRIPTION
    Guards the destructive and import boundaries of EntraOps against misconfigured paths. A plain
    string prefix comparison accepts a sibling that only shares the root's text ("/data/EntraOps"
    also matches "/data/EntraOps-escape"), which matters because the caller may recursively delete
    the accepted folder afterwards. Existing symbolic links and junctions in both paths are resolved
    before the root is compared with a trailing directory separator, so only real descendants are
    accepted. Path comparison is deliberately case-sensitive on every platform: rejecting an unusual
    case spelling is safer than accepting a different directory on a case-sensitive volume.

.PARAMETER Path
    Candidate path. Does not need to exist.

.PARAMETER Root
    Root directory the candidate has to stay within. Does not need to exist.

.PARAMETER AllowRoot
    Accept the root itself. Off by default so callers cannot delete or overwrite the root.

.EXAMPLE
    Test-EntraOpsPathWithinRoot -Path "/data/EntraOps/PrivilegedEAM" -Root "/data/EntraOps"
#>
function Test-EntraOpsPathWithinRoot {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [System.String]$Path,

        [Parameter(Mandatory = $true)]
        [System.String]$Root,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRoot
    )

    function Resolve-EntraOpsCanonicalDirectoryPath {
        param (
            [Parameter(Mandatory = $true)]
            [System.String]$InputPath
        )

        # Do not call GetFullPath on the complete input: it collapses "link/.." lexically even
        # though the filesystem resolves ".." relative to the link target. Make relative paths
        # absolute without removing their segments, then process those segments in filesystem order.
        $AbsolutePath = if ([System.IO.Path]::IsPathFullyQualified($InputPath)) {
            $InputPath
        } else {
            [System.IO.Path]::Combine([System.IO.Path]::GetFullPath((Get-Location).ProviderPath), $InputPath)
        }
        $PathRoot = [System.IO.Path]::GetPathRoot($AbsolutePath)
        if ([string]::IsNullOrEmpty($PathRoot)) {
            throw "Unable to determine the filesystem root for path '$InputPath'."
        }

        $CurrentPath = $PathRoot
        $RelativePath = $AbsolutePath.Substring($PathRoot.Length)
        $Separators = [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $Segments = $RelativePath.Split($Separators, [System.StringSplitOptions]::RemoveEmptyEntries)

        foreach ($Segment in $Segments) {
            if ($Segment -eq '.') {
                continue
            }
            if ($Segment -eq '..') {
                $Parent = [System.IO.Directory]::GetParent($CurrentPath)
                if ($null -ne $Parent) {
                    $CurrentPath = $Parent.FullName
                }
                continue
            }

            $CurrentPath = [System.IO.Path]::Combine($CurrentPath, $Segment)
            $DirectoryInfo = [System.IO.DirectoryInfo]::new($CurrentPath)

            # LinkTarget also identifies a broken link, for which Exists is false. Fail closed when
            # such a link cannot be resolved instead of falling back to its unsafe lexical path.
            if ($null -ne $DirectoryInfo.LinkTarget) {
                $LinkTarget = $DirectoryInfo.ResolveLinkTarget($true)
                if ($null -eq $LinkTarget) {
                    throw "Unable to resolve filesystem link '$CurrentPath'."
                }
                $CurrentPath = $LinkTarget.FullName
            }
        }

        return [System.IO.Path]::TrimEndingDirectorySeparator($CurrentPath)
    }

    $ResolvedRoot = Resolve-EntraOpsCanonicalDirectoryPath -InputPath $Root
    $ResolvedPath = Resolve-EntraOpsCanonicalDirectoryPath -InputPath $Path
    $Comparison = [System.StringComparison]::Ordinal

    if ($ResolvedPath.Equals($ResolvedRoot, $Comparison)) {
        return $AllowRoot.IsPresent
    }

    return $ResolvedPath.StartsWith($ResolvedRoot + [System.IO.Path]::DirectorySeparatorChar, $Comparison)
}
