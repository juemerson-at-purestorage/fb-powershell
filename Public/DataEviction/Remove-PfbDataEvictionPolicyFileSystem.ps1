function Remove-PfbDataEvictionPolicyFileSystem {
    <#
    .SYNOPSIS
        Detaches one or more file systems from a data eviction policy.
    .PARAMETER PolicyName
        Policy name to detach from.
    .PARAMETER PolicyId
        Policy ID to detach from.
    .PARAMETER MemberName
        File system name(s) to detach.
    .PARAMETER MemberId
        File system ID(s) to detach.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Remove-PfbDataEvictionPolicyFileSystem -PolicyName 'tier-out-100tb' -MemberName 'fs1'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPolicyName')]
        [string]$PolicyName,

        [Parameter(Mandatory, ParameterSetName = 'ByPolicyId')]
        [string]$PolicyId,

        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }

    $policy = if ($PolicyName) { $PolicyName } else { $PolicyId }
    $members = if ($MemberName) { $MemberName -join ', ' } elseif ($MemberId) { $MemberId -join ', ' } else { '(all)' }
    if ($PSCmdlet.ShouldProcess("$members from $policy", 'Detach file system(s) from data eviction policy')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'data-eviction-policies/file-systems' -QueryParams $queryParams
    }
}
