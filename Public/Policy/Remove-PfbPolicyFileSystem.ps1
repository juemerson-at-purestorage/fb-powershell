function Remove-PfbPolicyFileSystem {
    <#
    .SYNOPSIS
        Removes the association between a policy and a file system on a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbPolicyFileSystem cmdlet detaches a policy from a file system on the
        connected FlashBlade. This stops the policy from producing new snapshots for that
        file system; existing snapshots are not deleted.
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
        Remove-PfbPolicyFileSystem -PolicyName "snap-daily" -MemberName "fs-share"

        Detaches the 'snap-daily' policy from file system 'fs-share' after prompting.
    .EXAMPLE
        Remove-PfbPolicyFileSystem -PolicyName "snap-daily" -MemberName "fs-share" -Confirm:$false

        Detaches the policy without prompting.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [string]$MemberName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [PSCustomObject]$Array
    )

    if (-not $PolicyName -and -not $PolicyId) {
        throw 'You must supply either -PolicyName or -PolicyId.'
    }
    if (-not $MemberName -and -not $MemberId) {
        throw 'You must supply either -MemberName or -MemberId.'
    }

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }
    $member = if ($MemberName) { $MemberName } else { $MemberId }

    if ($PSCmdlet.ShouldProcess("${target}:${member}", 'Remove policy from file system')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'policies/file-systems' -QueryParams $queryParams
    }
}
