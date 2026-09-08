function Test-EntraOpsRemovalSafetyThreshold {
    <#
    .SYNOPSIS
        Decides whether a planned bulk removal exceeds the removal safety threshold.
    .DESCRIPTION
        Shared brake for the mutation cmdlets that reconcile protections from classified EAM data
        (Conditional Access groups, Administrative Units, RMAUs, ELM catalog privilege levels).
        A partially degraded or poisoned classification file recomputes a "desired" state that
        would strip protections wholesale; refusing to remove more than RemovalSafetyThreshold of
        the current protected set in one run bounds that damage. The caller aborts removals before
        mutating the target and reports, and a -Force... switch exists for reviewed reconciliation, because
        a drifted target can never converge on its own - every run recomputes the same delta.

        Mirrors the threshold originally implemented inline in
        Update-EntraOpsPrivilegedConditionalAccessGroup.
    .PARAMETER CurrentCount
        Number of currently protected members/objects.
    .PARAMETER RemovalCount
        Number of removals the run is about to perform.
    .PARAMETER RemovalSafetyThreshold
        Fraction (0..1) of CurrentCount that may be removed in one run. Default 0.5.
    .OUTPUTS
        [pscustomobject] with Exceeds ([bool]), RemovalThreshold ([int]) and ThresholdPercent ([int]).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$CurrentCount,

        [Parameter(Mandatory = $true)]
        [int]$RemovalCount,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 1)]
        [double]$RemovalSafetyThreshold = 0.5

    )

    $RemovalThreshold = [Math]::Ceiling($CurrentCount * $RemovalSafetyThreshold)
    [pscustomobject]@{
        Exceeds          = ($RemovalCount -gt $RemovalThreshold)
        RemovalThreshold = [int]$RemovalThreshold
        ThresholdPercent = [int][Math]::Round($RemovalSafetyThreshold * 100)
    }
}
