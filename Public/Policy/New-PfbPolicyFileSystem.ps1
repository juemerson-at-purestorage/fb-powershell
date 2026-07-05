function New-PfbPolicyFileSystem {
    <#
    .SYNOPSIS
        Associates a policy with a file system on a FlashBlade array.
    .DESCRIPTION
        The New-PfbPolicyFileSystem cmdlet creates an association between a policy and a
        file system on the connected FlashBlade. Once attached, the array auto-creates
        snapshots for that file system on the policy's schedule. This is the correct way to
        put a file system under a snapshot policy; policies cannot be attached to individual
        snapshots after the fact.
    .PARAMETER PolicyName
        The policy name.
    .PARAMETER PolicyId
        The policy ID.
    .PARAMETER MemberName
        The file system name.
    .PARAMETER MemberId
        The file system ID.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbPolicyFileSystem -PolicyName "snap-daily" -MemberName "fs-share"

        Attaches the 'snap-daily' policy to file system 'fs-share'.
    .EXAMPLE
        New-PfbPolicyFileSystem -PolicyId "p-123" -MemberId "m-456"

        Attaches a policy to a file system using IDs.
    .EXAMPLE
        New-PfbPolicyFileSystem -PolicyName "snap-daily" -MemberName "fs-share" -WhatIf

        Shows what would happen without creating the association.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [string]$MemberName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add policy to file system')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'policies/file-systems' -QueryParams $queryParams
    }
}
