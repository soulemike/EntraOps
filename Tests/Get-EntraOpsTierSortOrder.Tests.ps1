#Requires -Modules Pester

BeforeAll {
    . "$PSScriptRoot/../EntraOps/Private/Get-EntraOpsTierSortOrder.ps1"
}

Describe "Get-EntraOpsTierSortOrder" {
    It "returns numeric tier values unchanged" {
        Get-EntraOpsTierSortOrder -TierValue 1 | Should -Be 1
        Get-EntraOpsTierSortOrder -TierValue "3" | Should -Be 3
    }

    It "sorts unclassified, missing, and unknown values after numeric tiers" {
        Get-EntraOpsTierSortOrder -TierValue "Unclassified" | Should -Be ([int]::MaxValue)
        Get-EntraOpsTierSortOrder -TierValue $null | Should -Be ([int]::MaxValue)
        Get-EntraOpsTierSortOrder -TierValue "future" | Should -Be ([int]::MaxValue)
    }
}