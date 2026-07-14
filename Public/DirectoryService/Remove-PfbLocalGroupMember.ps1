function Remove-PfbLocalGroupMember {
    <#
    .SYNOPSIS
        Removes members from a local group on the FlashBlade.
    .DESCRIPTION
        Deletes one or more memberships from a local group. Endpoint:
        DELETE /directory-services/local/groups/members.
    .PARAMETER Group
        The name of the local group (sent as 'group_names').
    .PARAMETER Member
        One or more member names to remove (sent as 'member_names').
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbLocalGroupMember -Group "mydomain\share-admins" -Member "CORP\jdoe"

        Removes the external AD user CORP\jdoe from the local group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Group,
        [Parameter(Mandatory, Position = 1)] [string[]]$Member,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'group_names'  = $Group
        'member_names' = $Member -join ','
    }

    if ($PSCmdlet.ShouldProcess("$Group -> $($Member -join ', ')", 'Remove local group member(s)')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'directory-services/local/groups/members' -QueryParams $queryParams
    }
}
