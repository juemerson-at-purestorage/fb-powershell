function Remove-PfbQuotaUser {
    <#
    .SYNOPSIS
        Removes a user quota from a FlashBlade file system.
    .DESCRIPTION
        The Remove-PfbQuotaUser cmdlet deletes a user quota entry from the specified file system
        on the FlashBlade. This operation has a high confirm impact and will prompt for confirmation
        by default. Use -Confirm:$false to suppress the prompt. Identity binds from the pipeline via
        flattened 'FileSystemName' / 'UserName' properties emitted by Get-PfbQuotaUser.
    .PARAMETER FileSystemName
        The name of the file system containing the user quota to remove. Binds from pipeline property 'FileSystemName'.
    .PARAMETER UserName
        The name of the user whose quota should be removed. Binds from pipeline property 'UserName'.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'jdoe'
        Removes the user quota for 'jdoe' on 'fs-home' after prompting for confirmation.
    .EXAMPLE
        Get-PfbQuotaUser -FileSystemName 'fs-home' | Remove-PfbQuotaUser -Confirm:$false
        Removes every user quota on 'fs-home'.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string]$FileSystemName,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string]$UserName,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $q = @{ 'user_names' = $UserName; 'file_system_names' = $FileSystemName }
        if ($PSCmdlet.ShouldProcess("${FileSystemName}:${UserName}", 'Remove user quota')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'quotas/users' -QueryParams $q
        }
    }
}
