function Remove-PfbFileSystemSnapshotPolicy {
    <#
    .SYNOPSIS
        Detaches a policy from a file system snapshot on the FlashBlade.
    .DESCRIPTION
        Removes the association between a policy and a file system snapshot by
        specifying both the policy and snapshot names or IDs. The snapshot's name
        binds from the pipeline (property 'name', aliased to 'MemberName').
    .PARAMETER PolicyName
        The name of the policy to detach.
    .PARAMETER PolicyId
        The ID of the policy to detach.
    .PARAMETER MemberName
        The name of the snapshot to detach the policy from. Binds from pipeline property 'name'.
    .PARAMETER MemberId
        The ID of the snapshot to detach the policy from.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbFileSystemSnapshotPolicy -PolicyName "replication-hourly" -MemberName "fs01.snap1"
        Detaches the 'replication-hourly' policy from snapshot 'fs01.snap1'.
    .EXAMPLE
        Get-PfbFileSystemSnapshot -SourceName fs1 | Remove-PfbFileSystemSnapshotPolicy -PolicyName "replication-hourly"
        Detaches the policy from every snapshot of fs1.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ValueFromPipelineByPropertyName)] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter(ValueFromPipelineByPropertyName)] [Alias('Name')] [string]$MemberName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if (-not $PolicyName -and -not $PolicyId) {
            throw 'You must supply either -PolicyName or -PolicyId.'
        }
        if (-not $MemberName -and -not $MemberId) {
            throw 'You must supply either -MemberName or -MemberId.'
        }

        $queryParams = @{}
        if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
        if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
        if ($MemberName) { $queryParams['member_names'] = $MemberName }
        if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

        $target = "${PolicyName}:${MemberName}"

        if ($PSCmdlet.ShouldProcess($target, 'Detach policy from snapshot')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-snapshots/policies' -QueryParams $queryParams
        }
    }
}
