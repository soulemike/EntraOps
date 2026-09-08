<#
.SYNOPSIS
    Parses the raw 'errorDetails' string collection of a Tenant Governance (UTCM) snapshot job into
    structured, per-message objects.

.DESCRIPTION
    Each string in a configurationSnapshotJob's 'errorDetails' collection is a single blob for one
    resource type, formatted by the UTCM backend as either:
      "<resourceType>: Error exporting resource [<resourceType>]. exceptionMessage(s):<msg1> ,<msg2> ,...,"
    or a simpler connectivity failure, e.g.:
      "<resourceType>: Errors encountered while establishing connection with underlying workload"
    The individual messages packed into exceptionMessage(s) are delimited by a space+comma that is
    NOT followed by whitespace (internal commas within a message, e.g. "'<guid>', that is defined...",
    are always followed by a space and are therefore left untouched).

    This helper splits each blob into one object per individual message, and extracts the Graph
    error code (e.g. "Request_ResourceNotFound") and any referenced object Ids (GUIDs) found in the
    message text, plus a GUID-normalized version of the message that's useful for grouping/deduping
    near-identical messages that only differ by object Id (see Get-EntraOpsTenantGovernanceSnapshotReport).

.PARAMETER ErrorDetail
    One or more raw strings from a configurationSnapshotJob's 'errorDetails' collection.

.EXAMPLE
    $JobDetail.errorDetails | ConvertFrom-EntraOpsTenantGovernanceSnapshotErrorDetail
#>
function ConvertFrom-EntraOpsTenantGovernanceSnapshotErrorDetail {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyCollection()]
        [System.String[]]$ErrorDetail
    )

    begin {
        $GuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    }

    process {
        foreach ($Entry in $ErrorDetail) {
            if ([string]::IsNullOrWhiteSpace($Entry)) { continue }

            # Each entry is prefixed with "<resourceType>: <body>"
            $ResourceType = $null
            $Body = $Entry.Trim()
            $PrefixMatch = [regex]::Match($Entry, '^(?<ResourceType>microsoft\.[a-zA-Z0-9\.]+):\s*(?<Body>.*)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($PrefixMatch.Success) {
                $ResourceType = $PrefixMatch.Groups['ResourceType'].Value
                $Body = $PrefixMatch.Groups['Body'].Value.Trim()
            }

            $ErrorCategory = "Other"
            $RawMessages = @($Body)
            $ExceptionMatch = [regex]::Match($Body, '^Error exporting resource \[[^\]]+\]\.\s*exceptionMessage\(s\):\s*(?<Messages>.*)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($ExceptionMatch.Success) {
                $ErrorCategory = "ExportError"
                # Message boundaries are a space+comma that is immediately followed by a non-whitespace
                # character. Internal commas (e.g. "'<guid>', that is defined...") are always followed
                # by a space and are therefore not split on.
                $RawMessages = [regex]::Split($ExceptionMatch.Groups['Messages'].Value, '\s,(?=\S)')
            } elseif ($Body -match 'establishing connection with underlying workload') {
                $ErrorCategory = "ConnectionError"
            }

            foreach ($Message in $RawMessages) {
                $CleanMessage = $Message.Trim().TrimEnd(',').Trim()
                if ([string]::IsNullOrWhiteSpace($CleanMessage)) { continue }

                $ErrorCode = $null
                $CodeMatch = [regex]::Match($CleanMessage, '\[(?<Code>[A-Za-z_]+)\]')
                if ($CodeMatch.Success) { $ErrorCode = $CodeMatch.Groups['Code'].Value }

                $ReferencedObjectIds = @([regex]::Matches($CleanMessage, $GuidPattern) | ForEach-Object { $_.Value } | Select-Object -Unique)
                $NormalizedMessage = [regex]::Replace($CleanMessage, $GuidPattern, '<id>')

                [PSCustomObject]@{
                    ResourceType        = $ResourceType
                    ErrorCategory       = $ErrorCategory
                    ErrorCode           = $ErrorCode
                    Message             = $CleanMessage
                    NormalizedMessage   = $NormalizedMessage
                    ReferencedObjectIds = $ReferencedObjectIds
                }
            }
        }
    }
}
