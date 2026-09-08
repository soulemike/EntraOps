function Select-EntraOpsAzureRbacPrincipal {
    [CmdletBinding()]
    param (
        # AllowEmptyCollection: a pure filter function's natural contract is empty-in/empty-out -
        # a tenant with no Azure RBAC principals in scope must not fail parameter binding here.
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Array]$UniqueObjects,

        [Parameter(Mandatory = $true)]
        [hashtable]$ObjectDetailsCache,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Keep', 'Filter')]
        [string]$DeletedPrincipalAssignmentHandling = 'Filter'
    )

    if ($DeletedPrincipalAssignmentHandling -eq 'Keep') {
        return $UniqueObjects
    }

    $UniqueObjects | Where-Object {
        $ObjectDetailsCache[$_.ObjectId].ResolutionStatus -ne 'NotFound'
    }
}