function Update-PfbQuotaUser {
    <#
    .SYNOPSIS
        Updates an existing user quota on a FlashBlade file system.
    .DESCRIPTION
        The Update-PfbQuotaUser cmdlet modifies the quota limit for an existing user quota
        entry on a FlashBlade file system. You can specify a new quota value in bytes or
        provide a complete attributes hashtable for advanced updates. Identity binds from
        the pipeline via flattened 'FileSystemName' / 'UserName' properties emitted by Get-PfbQuotaUser.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER FileSystemName
        The name of the file system containing the user quota to update. Binds from pipeline property 'FileSystemName'.
    .PARAMETER UserName
        The name of the user whose quota should be updated. Binds from pipeline property 'UserName'.
    .PARAMETER Quota
        The new quota limit in bytes. For example, 1073741824 equals 1 GiB.
    .PARAMETER Attributes
        A hashtable containing the full request body. When specified, the Quota parameter is ignored.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'jdoe' -Quota 10737418240
        Increases the user quota for 'jdoe' on 'fs-home' to 10 GiB.
    .EXAMPLE
        Get-PfbQuotaUser -FileSystemName 'fs-home' | Update-PfbQuotaUser -Quota 0
        Clears the quota limit for every user quota on 'fs-home'.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string]$FileSystemName,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string]$UserName,
        [Parameter()] [int64]$Quota,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($Quota -gt 0) { $body['quota'] = $Quota }
        }
        $q = @{ 'names' = $UserName; 'file_system_names' = $FileSystemName }
        if ($PSCmdlet.ShouldProcess("${FileSystemName}:${UserName}", 'Update user quota')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'quotas/users' -Body $body -QueryParams $q
        }
    }
}
