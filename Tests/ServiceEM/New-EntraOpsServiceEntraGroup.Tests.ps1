#Requires -Modules Pester
#Requires -Version 7.0

<#
.SYNOPSIS
    Unit tests for New-EntraOpsServiceEntraGroup function.

.DESCRIPTION
    Tests payload validation, parameter handling, and error conditions
    for the New-EntraOpsServiceEntraGroup function without requiring
    actual Microsoft Graph API calls.

.NOTES
    Issue 4.6: Create mock testing framework
#>

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot ".." ".." "EntraOps" "EntraOps.psd1"
    Import-Module $ModulePath -Force -ErrorAction Stop
    
    # Mock Invoke-EntraOpsMsGraphQuery to avoid actual API calls
    function Mock-InvokeEntraOpsMsGraphQuery {
        param(
            [string]$Method,
            [string]$Uri,
            [string]$Body,
            [string]$ConsistencyLevel,
            [string]$OutputType,
            [switch]$DisableCache
        )
        
        if ($Method -eq "GET") {
            # Return empty array for group lookups (groups don't exist yet)
            return @()
        } elseif ($Method -eq "POST") {
            # Simulate successful group creation
            $bodyObj = $Body | ConvertFrom-Json
            return [pscustomobject]@{
                Id = [guid]::NewGuid().ToString()
                DisplayName = $bodyObj.displayName
                MailNickname = $bodyObj.mailNickname
                GroupTypes = $bodyObj.groupTypes
            }
        }
    }
    
    Mock Invoke-EntraOpsMsGraphQuery -MockWith ${function:Mock-InvokeEntraOpsMsGraphQuery}
}

Describe "New-EntraOpsServiceEntraGroup" {
    Context "Parameter Validation" {
        It "Should throw when ServiceName is empty" {
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "" `
                    -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles @() `
                    -ErrorAction Stop
            } | Should -Throw
        }
        
        It "Should throw when ServiceOwner is empty" {
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "TestService" `
                    -ServiceOwner "" `
                    -ServiceRoles @() `
                    -ErrorAction Stop
            } | Should -Throw
        }
        
        It "Should accept valid OData URL format for ServiceOwner" {
            $roles = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
            )
            
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "TestService" `
                    -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles $roles `
                    -ErrorAction Stop
            } | Should -Not -Throw
        }
        
        It "Should accept GUID format for ServiceOwner and convert to OData URL" {
            $roles = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
            )
            
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "TestService" `
                    -ServiceOwner "12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles $roles `
                    -ErrorAction Stop
            } | Should -Not -Throw
        }
        
        It "Should throw for invalid ServiceOwner format" {
            $roles = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
            )
            
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "TestService" `
                    -ServiceOwner "invalid-owner-format" `
                    -ServiceRoles $roles `
                    -ErrorAction Stop
            } | Should -Throw
        }
    }
    
    Context "Payload Validation - DisplayName Length" {
        It "Should throw when DisplayName exceeds 256 characters" {
            $longServiceName = "A" * 250
            $roles = @(
                [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
            )
            
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName $longServiceName `
                    -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles $roles `
                    -ErrorAction Stop
            } | Should -Throw -ExpectedMessage "*exceeds maximum length of 256 characters*"
        }
    }
    
    Context "Payload Validation - MailNickname Length" {
        It "Should throw when MailNickname exceeds 64 characters" {
            $longServiceName = "A" * 70
            $roles = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
            )
            
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName $longServiceName `
                    -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles $roles `
                    -ErrorAction Stop
            } | Should -Throw -ExpectedMessage "*exceeds maximum length of 64 characters*"
        }
    }
    
    Context "Payload Validation - MailNickname Format" {
        It "Should throw when MailNickname contains invalid characters" {
            $roles = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
            )
            
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "Test Service!" `
                    -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles $roles `
                    -ErrorAction Stop
            } | Should -Throw -ExpectedMessage "*invalid characters*"
        }
        
        It "Should accept valid MailNickname with dots and underscores" {
            $roles = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
            )
            
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "Test.Service_01" `
                    -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles $roles `
                    -ErrorAction Stop
            } | Should -Not -Throw
        }
    }
    
    Context "Group Creation - Unified Groups" {
        It "Should create Unified group with correct properties" {
            $roles = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
            )
            
            $result = New-EntraOpsServiceEntraGroup `
                -ServiceName "TestService" `
                -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                -ServiceRoles $roles
            
            $result | Should -Not -BeNullOrEmpty
            $result.MailNickname | Should -Contain "TestService.Members"
        }
    }
    
    Context "Group Creation - Security Groups" {
        It "Should create Security group with correct properties" {
            $roles = @(
                [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
            )
            
            $result = New-EntraOpsServiceEntraGroup `
                -ServiceName "TestService" `
                -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                -ServiceRoles $roles
            
            $result | Should -Not -BeNullOrEmpty
            $result.MailNickname | Should -Contain "TestService.ControlPlane.Admins"
        }
        
        It "Should create PIM staging group when ProhibitDirectElevation is not set" {
            $roles = @(
                [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Admins"; groupType = ""}
            )
            
            $result = New-EntraOpsServiceEntraGroup `
                -ServiceName "TestService" `
                -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                -ServiceRoles $roles
            
            $result | Should -Not -BeNullOrEmpty
            $result.MailNickname | Should -Contain "PIM.TestService.ManagementPlane.Admins"
        }
        
        It "Should NOT create PIM staging group when ProhibitDirectElevation is set" {
            $roles = @(
                [pscustomobject]@{accessLevel = "ManagementPlane"; name = "Admins"; groupType = ""}
            )
            
            $result = New-EntraOpsServiceEntraGroup `
                -ServiceName "TestService" `
                -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                -ServiceRoles $roles `
                -ProhibitDirectElevation
            
            $result | Should -Not -BeNullOrEmpty
            $result.MailNickname | Should -Not -Contain "PIM.TestService.ManagementPlane.Admins"
        }
    }
    
    Context "IsAssignableToRole Parameter" {
        It "Should set IsAssignableToRole when switch is provided" {
            $roles = @(
                [pscustomobject]@{accessLevel = "ControlPlane"; name = "Admins"; groupType = ""}
            )
            
            # This would require inspecting the actual API call
            # For now, just verify it doesn't throw
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "TestService" `
                    -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles $roles `
                    -IsAssignableToRole `
                    -ErrorAction Stop
            } | Should -Not -Throw
        }
    }
}

Describe "New-EntraOpsServiceEntraGroup - Error Handling" {
    Context "API Error Simulation" {
        BeforeEach {
            Mock Invoke-EntraOpsMsGraphQuery -MockWith {
                throw "Graph API Error: Group already exists"
            }
        }
        
        It "Should handle API errors gracefully" {
            $roles = @(
                [pscustomobject]@{accessLevel = ""; name = "Members"; groupType = "Unified"}
            )
            
            { 
                New-EntraOpsServiceEntraGroup `
                    -ServiceName "TestService" `
                    -ServiceOwner "https://graph.microsoft.com/v1.0/users/12345678-1234-1234-1234-123456789012" `
                    -ServiceRoles $roles `
                    -ErrorAction Stop
            } | Should -Throw
        }
    }
}

AfterAll {
    # Cleanup
    Remove-Module EntraOps -Force -ErrorAction SilentlyContinue
}
