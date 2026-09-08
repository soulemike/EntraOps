<#
.SYNOPSIS
    Install all required modules for EntraOps PowerShell Module

.DESCRIPTION
    Wrapper function to check if all required modules for EntraOps PowerShell Module are installed and install them if not.

.EXAMPLE
    Verify if all required modules are installed with the required version
    Install-EntraOpsAllRequiredModules
#>

function Install-EntraOpsAllRequiredModules {

    $ErrorActionPreference = "Stop"

    $RequiredModules = @(
        @{
            ModuleName    = 'Az.Accounts'
            ModuleVersion = '5.1.1'
        }
        @{
            ModuleName    = 'Az.Resources'
            ModuleVersion = '10.2.0'
        }
        @{
            ModuleName    = 'Microsoft.Graph.Authentication'
            ModuleVersion = '2.18.0'
        }
    )

    foreach ($RequiredModule in $RequiredModules) {
        Install-EntraOpsRequiredModule -ModuleName $RequiredModule.ModuleName -MinimalVersion $RequiredModule.ModuleVersion
    }
}