function Add-PfbDataEvictionPolicyFileSystem {
    <#
    .SYNOPSIS
        Attaches one or more file systems to a data eviction policy.
    .DESCRIPTION
        Creates a file-system-to-policy membership. Once attached, the policy's
        `keep_size` threshold governs the file system's tiered-storage behavior.
    .PARAMETER PolicyName
        Policy name to attach to.
    .PARAMETER PolicyId
        Policy ID to attach to.
    .PARAMETER MemberName
        File system name(s) to attach.
    .PARAMETER MemberId
        File system ID(s) to attach.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Add-PfbDataEvictionPolicyFileSystem -PolicyName 'tier-out-100tb' -MemberName 'fs1','fs2'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

    if (-not $MemberName -and -not $MemberId) {
        throw 'Provide -MemberName or -MemberId to identify the file system(s) to attach.'
    }

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }

    $policy = if ($PolicyName) { $PolicyName } else { $PolicyId }
    $members = if ($MemberName) { $MemberName -join ', ' } else { $MemberId -join ', ' }
    if ($PSCmdlet.ShouldProcess("$members -> $policy", 'Attach file system(s) to data eviction policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'data-eviction-policies/file-systems' -QueryParams $queryParams
    }
}
