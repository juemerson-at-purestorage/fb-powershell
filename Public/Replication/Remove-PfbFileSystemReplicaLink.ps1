function Remove-PfbFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Removes a file system replica link.
    .DESCRIPTION
        Deletes the replication relationship between a local file system and a remote
        target. Does NOT delete the file systems themselves on either side. By default,
        in-progress transfers are allowed to complete; pass -CancelInProgressTransfers
        to abort them.
    .PARAMETER LocalFileSystemName
        Local file system name whose replica link should be removed.
    .PARAMETER RemoteArrayName
        Remote array name. Together with -LocalFileSystemName uniquely identifies a link.
    .PARAMETER RemoteFileSystemName
        Remote file system name (optional, for further disambiguation).
    .PARAMETER Id
        Replica link ID. Alternative to the name-based parameters.
    .PARAMETER CancelInProgressTransfers
        Cancel any in-progress replication transfers when removing the link.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Remove-PfbFileSystemReplicaLink -LocalFileSystemName fs01 -RemoteArrayName nypure009
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$LocalFileSystemName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$RemoteArrayName,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$RemoteFileSystemName,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()]
        [switch]$CancelInProgressTransfers,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $queryParams['local_file_system_names'] = $LocalFileSystemName
        $queryParams['remote_names']            = $RemoteArrayName
        if ($RemoteFileSystemName) { $queryParams['remote_file_system_names'] = $RemoteFileSystemName }
        $target = "$LocalFileSystemName -> $RemoteArrayName"
    } else {
        $queryParams['ids'] = $Id
        $target = $Id
    }
    if ($CancelInProgressTransfers) { $queryParams['cancel_in_progress_transfers'] = 'true' }

    if ($PSCmdlet.ShouldProcess($target, 'Remove file system replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-replica-links' -QueryParams $queryParams
    }
}
