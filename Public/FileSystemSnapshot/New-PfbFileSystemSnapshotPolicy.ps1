function New-PfbFileSystemSnapshotPolicy {
    <#
    .SYNOPSIS
        Attaches a policy to a file system snapshot on the FlashBlade.
    .DESCRIPTION
        Associates an existing policy with a file system snapshot by specifying
        both the policy and snapshot names or IDs. The snapshot's name binds from
        the pipeline (property 'name', aliased to 'MemberName'), so
        `Get-PfbFileSystemSnapshot | New-PfbFileSystemSnapshotPolicy -PolicyName <p>` works.
    .PARAMETER PolicyName
        The name of the policy to attach.
    .PARAMETER PolicyId
        The ID of the policy to attach.
    .PARAMETER MemberName
        The name of the snapshot to attach the policy to. Binds from pipeline property 'name'.
    .PARAMETER MemberId
        The ID of the snapshot to attach the policy to.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbFileSystemSnapshotPolicy -PolicyName "replication-hourly" -MemberName "fs01.snap1"
        Attaches the 'replication-hourly' policy to snapshot 'fs01.snap1'.
    .EXAMPLE
        Get-PfbFileSystemSnapshot -SourceName fs1 | New-PfbFileSystemSnapshotPolicy -PolicyName "replication-hourly"
        Attaches the policy to every snapshot of fs1.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

        $target = if ($MemberName) { $MemberName } else { $MemberId }
        $policy = if ($PolicyName) { $PolicyName } else { $PolicyId }

        if ($PSCmdlet.ShouldProcess("$target", "Attach policy '$policy'")) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-snapshots/policies' -QueryParams $queryParams
        }
    }
}
