function New-PfbLocalGroupMember {
    <#
    .SYNOPSIS
        Adds members (including external/AD users) to a local group on the FlashBlade.
    .DESCRIPTION
        Maps one or more members into a local group. Members may be external directory users
        (e.g. Active Directory accounts), which is the supported way to grant AD users NTFS
        access via a FlashBlade local group. Endpoint:
        POST /directory-services/local/groups/members.

        The group is identified with 'group_names'; the members are supplied in the request
        body as { members: [ { member: { name = "<member>" } } ] }.
    .PARAMETER Group
        The name of the local group to add members to (sent as 'group_names').
    .PARAMETER Member
        One or more member names to add. For external AD users use the fully-qualified form
        the array expects (e.g. "DOMAIN\\user" or "user@domain").
    .PARAMETER LocalDirectoryService
        Optional name of the local directory service that owns the group
        (sent as 'local_directory_service_names').
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbLocalGroupMember -Group "mydomain\share-admins" -Member "CORP\jdoe"

        Adds the external AD user CORP\jdoe to the local group.
    .EXAMPLE
        New-PfbLocalGroupMember -Group "mydomain\share-admins" -Member "CORP\jdoe","CORP\asmith"

        Adds multiple external users at once.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Group,
        [Parameter(Mandatory, Position = 1)] [string[]]$Member,
        [Parameter()] [string]$LocalDirectoryService,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $members = foreach ($m in $Member) { @{ member = @{ name = $m } } }
    # Force an array even when a single member is supplied.
    $body = @{ members = @($members) }

    $queryParams = @{ 'group_names' = $Group }
    if ($LocalDirectoryService) { $queryParams['local_directory_service_names'] = $LocalDirectoryService }

    if ($PSCmdlet.ShouldProcess("$Group <- $($Member -join ', ')", 'Add local group member(s)')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'directory-services/local/groups/members' -Body $body -QueryParams $queryParams
    }
}
