function New-PfbLocalGroup {
    <#
    .SYNOPSIS
        Creates a local group on the FlashBlade.
    .DESCRIPTION
        Creates a local group under a local directory service. Local groups are used to grant
        NTFS permissions on SMB shares; external (e.g. Active Directory) users are added to them
        with New-PfbLocalGroupMember. Endpoint: POST /directory-services/local/groups.
    .PARAMETER Name
        The name of the local group to create (sent as 'names').
    .PARAMETER Email
        Optional email address for the local group.
    .PARAMETER Gid
        Optional POSIX group ID (GID) for the local group.
    .PARAMETER Attributes
        Optional hashtable merged into the request body for any additional fields.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbLocalGroup -Name "mydomain\share-admins"

        Creates a local group.
    .EXAMPLE
        New-PfbLocalGroup -Name "mydomain\share-admins" -Gid 20001
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter()] [string]$Email,
        [Parameter()] [int]$Gid,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes.Clone() } else { @{} }
    if ($Email)                              { $body['email'] = $Email }
    if ($PSBoundParameters.ContainsKey('Gid')) { $body['gid'] = $Gid }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create local group')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'directory-services/local/groups' -Body $body -QueryParams $queryParams
    }
}
