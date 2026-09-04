<#
.SYNOPSIS
    Ingest EntraOps data to Log Analytics workspace using Ingest API.

.DESCRIPTION
    Ingesting data to Log Analytics workspace using Data Collection Rule and Data Collection Endpoint via Ingest API.

.PARAMETER JsonContent
    JSON content as plaintext to be ingested to Log Analytics workspace.

.PARAMETER DataCollectionRuleName
    Name of the Data Collection Rule in Azure Resource Manager.

.PARAMETER DataCollectionResourceGroupName
    Resource Group Name of the Data Collection Rule in Azure Resource Manager. Default is 'aadops-rg'.

.PARAMETER DataCollectionRuleSubscriptionId
    Subscription Id of the Data Collection Rule in Azure Resource Manager.

.PARAMETER TableName
    Custom Log Table name in Log Analytics workspace. Default is 'PrivilegedEAM_CL'.

.PARAMETER SampleDataOnly
    If set to $true, the function will return the JSON content with added timestamp. Default is $false.

.PARAMETER ApiVersion
    API version to be used for the ARM API request. Default is '2022-06-01'.

.EXAMPLE
    Ingest JSON data to Log Analytics Custom Log Table 'PrivilegedEAM_CL' in Log Analytics Workspace
    Push-EntraOpsLogIngestionAPI -JsonContent <VariableWithPlainJson> -DataCollectionRuleName "entraops-dcr" -DataCollectionResourceGroupName "entraops-rg" -DataCollectionRuleSubscriptionId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    Get schema to update data collection transformation rule
    Push-EntraOpsLogIngestionAPI -JsonContent <VariableWithPlainJson> -SampleDataOnly $true -DataCollectionRuleName "entraops-dcr" -DataCollectionResourceGroupName "entraops-rg" -DataCollectionRuleSubscriptionId "00000000-0000-0000-0000-000000000000"
 #>

function Push-EntraOpsLogsIngestionAPI {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [object]$JsonContent
        ,
        [Parameter(Mandatory = $true)]
        [string]$DataCollectionRuleName
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$DataCollectionResourceGroupName = "aadops-rg"
        ,
        [Parameter(Mandatory = $true)]
        [System.String]$DataCollectionRuleSubscriptionId
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$TableName = "PrivilegedEAM_CL"
        ,
        [Parameter(Mandatory = $false)]
        [System.Boolean]$SampleDataOnly = $false
        ,
        [Parameter(Mandatory = $false)]
        [System.String]$ApiVersion = "2022-06-01"
    )

    $ErrorActionPreference = "Stop"

    Set-AzContext -SubscriptionId $DataCollectionRuleSubscriptionId | Out-Null

    Write-Verbose "Ingesting to Log Analytics Custom Log Table '$($TableName)'"
    Write-Verbose " DataCollectionRuleSubscriptionId '$($DataCollectionRuleSubscriptionId)'"
    Write-Verbose " DataCollectionRuleResourceGroup '$($DataCollectionResourceGroupName)'"
    Write-Verbose " DataCollectionRuleName: '$($DataCollectionRuleName)'"
    Write-Verbose " LogAnalyticsCustomLogTableName: '$($TableName)'"

    # Authentication
    $AccessToken = (Get-AzAccessToken -ResourceUrl "https://monitor.azure.com/" -AsSecureString).Token
    $headers = @{"Authorization" = "Bearer $($AccessToken | ConvertFrom-SecureString -AsPlainText)"; "Content-Type" = "application/json" }

    # Add Timestamp to JSON data
    try {
        $records = $JsonContent | ConvertFrom-Json -Depth 10
        if ($records -isnot [array]) {
            $records = @($records)
        }
        $records | ForEach-Object {
            $_ | Add-Member -NotePropertyName TimeGenerated -NotePropertyValue (Get-Date).ToUniversalTime().ToString("o") -Force
        }
    }
    catch {
        Write-Error "Cannot convert JSON content to JSON object"
        throw $_
    }

    if ($SampleDataOnly -eq $false) {

        # Get Data Collection Rule details and Uri
        $DcrArmUri = "https://management.azure.com/subscriptions/$($DataCollectionRuleSubscriptionId)/resourceGroups/$($DataCollectionResourceGroupName)/providers/Microsoft.Insights/dataCollectionRules/$($DataCollectionRuleName)?api-version=$($ApiVersion)"
        $Dcr = ((Invoke-AzRestMethod -Method "Get" -Uri $DcrArmUri).Content | ConvertFrom-Json)

        # Resolve the actual stream name from the DCR data flows.
        # The Logs Ingestion API URL requires the INPUT stream name from
        # dataFlows.streams, NOT outputStream (which is the destination table).
        # dataFlows is an array; each element has a 'streams' array of input names.
        $AvailableStreams = $Dcr.properties.dataflows.streams | ForEach-Object { $_ } | Select-Object -Unique
        Write-Verbose "Available DCR input streams: $($AvailableStreams -join ', ')"

        $ExpectedStream = "Custom-$($TableName)"
        if ($AvailableStreams -notcontains $ExpectedStream) {
            $ExpectedStreamWithSuffix = "Custom-$($TableName)_CL"
            if ($AvailableStreams -contains $ExpectedStreamWithSuffix) {
                $ExpectedStream = $ExpectedStreamWithSuffix
                Write-Verbose "Resolved DCR stream to $($ExpectedStream) (Azure auto-appended _CL suffix)."
            } else {
                Write-Error "Custom table $($TableName) does not match with any input stream in data collection rule $($DataCollectionRuleName)! Available streams: $($AvailableStreams -join ', ')"
            }
        }

        # Get Data Collection Endpoint details and Uri
        $DceEndpointId = $Dcr.properties.dataCollectionEndpointId
        $DceArmUri = "https://management.azure.com$($DceEndpointId)?api-version=$($ApiVersion)"
        $Dce = ((Invoke-AzRestMethod -Method "Get" -Uri $DceArmUri).Content | ConvertFrom-Json)
        $DceIngestEndpointUrl = $Dce.properties.logsIngestion.endpoint

        if ($null -eq $DceIngestEndpointUrl) {
            Write-Error "No Data Collection endpoint found!"
        }

        # Get Ingest API Uri
        $PostUri = "$DceIngestEndpointUrl/dataCollectionRules/$($Dcr.properties.immutableId)/streams/$($ExpectedStream)?api-version=2023-01-01"

        # Ingest data to Log Analytics in chunks to stay under the 1 MB request limit
        $maxBytes = 950KB
        $chunk = [System.Collections.Generic.List[object]]::new()

        for ($i = 0; $i -lt $records.Count; $i++) {
            $chunk.Add($records[$i])
            $chunkJson = $chunk | ConvertTo-Json -Depth 10
            $chunkSize = [System.Text.Encoding]::UTF8.GetByteCount($chunkJson)

            if ($chunkSize -gt $maxBytes) {
                if ($chunk.Count -eq 1) {
                    Write-Warning "Record $($i) exceeds maximum chunk size ($chunkSize bytes). Sending individually; API may reject."
                } else {
                    # Remove the last record and send the rest
                    $chunk.RemoveAt($chunk.Count - 1)
                    $chunkJson = $chunk | ConvertTo-Json -Depth 10
                    Invoke-RestMethod -Uri $PostUri -Method "Post" -Body $chunkJson -Headers $headers -Verbose
                    Write-Verbose "Sent chunk of $($chunk.Count) records ($([System.Text.Encoding]::UTF8.GetByteCount($chunkJson)) bytes)"
                    $chunk.Clear()
                    $i--  # Re-process the current record in the next chunk
                    continue
                }
            }

            # Last record — send the final chunk
            if ($i -eq $records.Count - 1 -and $chunk.Count -gt 0) {
                Invoke-RestMethod -Uri $PostUri -Method "Post" -Body $chunkJson -Headers $headers -Verbose
                Write-Verbose "Sent final chunk of $($chunk.Count) records ($([System.Text.Encoding]::UTF8.GetByteCount($chunkJson)) bytes)"
            }
        }

    }
    else {
        $json = $records | ConvertTo-Json -Depth 10
        return $json
    }
}