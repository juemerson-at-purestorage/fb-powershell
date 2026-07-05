function New-PfbQuotaUser {
    <#
    .SYNOPSIS
        Creates a new user quota on a Pure Storage FlashBlade file system.
    .DESCRIPTION
        The New-PfbQuotaUser cmdlet creates a user quota entry that limits the amount of
        storage a specific user can consume on a given file system. Identify the user by name
        (-UserName, requires a configured directory service for name-to-id resolution) or by
        numeric UID (-UserId). Specify exactly one. You can set the quota size in bytes with
        -Quota or provide a complete body hashtable with -Attributes for advanced use.
        Supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER FileSystemName
        The name of the file system on which to create the user quota.
    .PARAMETER UserName
        The name of the user to apply the quota to. Requires a configured directory service so
        the array can map the name to a UID. Mutually exclusive with -UserId.
    .PARAMETER UserId
        The numeric UID of the user to apply the quota to. Mutually exclusive with -UserName.
    .PARAMETER Quota
        The quota limit in bytes. For example, 1073741824 equals 1 GiB.
    .PARAMETER Attributes
        A hashtable containing the full request body. When specified, it overrides the body
        built from -Quota. The user/file-system identity is always taken from the -FileSystemName
        and -UserName/-UserId parameters (sent as query parameters), not from this hashtable.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'jdoe' -Quota 5368709120

        Creates a 5 GiB user quota for user 'jdoe' on 'fs-home'.
    .EXAMPLE
        New-PfbQuotaUser -FileSystemName 'fs-home' -UserId '1001' -Quota 1073741824

        Creates a 1 GiB user quota for UID 1001 on 'fs-home'.
    .EXAMPLE
        New-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'asmith' -Quota 10737418240 -WhatIf

        Shows what would happen without actually creating the quota.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory)] [string]$FileSystemName,
        [Parameter(Mandatory, ParameterSetName = 'ByName')] [string]$UserName,
        [Parameter(Mandatory, ParameterSetName = 'ById')] [string]$UserId,
        [Parameter()] [int64]$Quota,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        if ($Quota -le 0) {
            throw 'Provide -Quota (a positive value) or -Attributes to specify the quota body.'
        }
        $body = @{ quota = $Quota }
    }

    $q = @{ 'file_system_names' = $FileSystemName }
    if ($UserName) { $q['user_names'] = $UserName }
    if ($UserId)   { $q['uids']       = $UserId }

    $target = if ($UserName) { $UserName } else { $UserId }
    if ($PSCmdlet.ShouldProcess("${FileSystemName}:${target}", 'Create user quota')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'quotas/users' -Body $body -QueryParams $q
    }
}
