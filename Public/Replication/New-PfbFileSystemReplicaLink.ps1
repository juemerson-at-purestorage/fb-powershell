function New-PfbFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Creates a file system replica link between a local file system and a remote array.
    .DESCRIPTION
        Establishes a replication relationship from a local file system on this FlashBlade
        to a target file system on a remote array. Prerequisite: an active ArrayConnection
        must already exist to the remote array (see Get-PfbArrayConnection /
        New-PfbArrayConnection).

        After the link is created, any snapshot of the local file system is automatically
        replicated to the remote. Use New-PfbFileSystemSnapshot to trigger one. Use
        Get-PfbFileSystemReplicaLinkTransfer to poll transfer status.

        Note: The misleadingly-named New-PfbFileSystemReplicaLinkPolicy cmdlet attaches a
        policy to an existing replica link (POST /file-system-replica-links/policies); it
        does NOT create the link itself. This cmdlet is the one you want for that.
    .PARAMETER LocalFileSystemName
        Name of the local file system to replicate.
    .PARAMETER RemoteArrayName
        Name of the remote FlashBlade (as it appears in Get-PfbArrayConnection.remote.name).
    .PARAMETER RemoteFileSystemName
        Name of the target file system on the remote array. If omitted, the FlashBlade
        will name it after the local file system.
    .PARAMETER RemoteDefaultExports
        If true, create default NFS/SMB exports on the remote file system after replication.
    .PARAMETER Array
        FlashBlade connection (the source/local array).
    .EXAMPLE
        New-PfbFileSystemReplicaLink -Array $sourceFb `
            -LocalFileSystemName 'project-data' `
            -RemoteArrayName 'nypure009'
    .EXAMPLE
        New-PfbFileSystemReplicaLink -Array $sourceFb `
            -LocalFileSystemName 'fs01' -RemoteArrayName 'nypure009' `
            -RemoteFileSystemName 'fs01-dr'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalFileSystemName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RemoteArrayName,

        [Parameter()]
        [string]$RemoteFileSystemName,

        [Parameter()]
        [switch]$RemoteDefaultExports,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'local_file_system_names' = $LocalFileSystemName
        'remote_names'            = $RemoteArrayName
    }
    if ($RemoteFileSystemName)   { $queryParams['remote_file_system_names'] = $RemoteFileSystemName }
    if ($RemoteDefaultExports)   { $queryParams['remote_default_exports']    = 'true' }

    # POST /file-system-replica-links requires a body even if empty
    $body = @{}

    $target = "$LocalFileSystemName -> $RemoteArrayName"
    if ($PSCmdlet.ShouldProcess($target, 'Create file system replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-replica-links' -QueryParams $queryParams -Body $body
    }
}
