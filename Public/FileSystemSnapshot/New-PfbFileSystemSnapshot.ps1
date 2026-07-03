function New-PfbFileSystemSnapshot {
    <#
    .SYNOPSIS
        Creates a snapshot of one or more file systems.
    .DESCRIPTION
        Creates a snapshot of a file system. FlashBlade's snapshot-creation endpoint accepts
        only one source file system per call (confirmed against a real array: passing more
        than one name in a single request fails with "Cannot process more than one source at
        a time"), so when multiple names are supplied -- either explicitly or via the pipeline
        -- one API call is issued per file system.
    .PARAMETER SourceName
        Name of the source file system(s) to snapshot. Accepts pipeline input by property
        name (aliased to 'Name'), so `Get-PfbFileSystem | New-PfbFileSystemSnapshot` snapshots
        every piped file system, one API call per file system.
    .PARAMETER Suffix
        Custom suffix appended to the snapshot name. The resulting snapshot is named
        `{source}.{suffix}`. If omitted, FlashBlade generates a timestamp suffix.
    .PARAMETER Send
        If true, replicate the snapshot to associated targets after creation.
    .PARAMETER Targets
        Names of replication targets to send the snapshot to. Implies -Send.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        New-PfbFileSystemSnapshot -SourceName fs1
        Creates `fs1.{auto-timestamp}`.
    .EXAMPLE
        New-PfbFileSystemSnapshot -SourceName fs1 -Suffix daily-backup
        Creates `fs1.daily-backup`.
    .EXAMPLE
        Get-PfbFileSystem | New-PfbFileSystemSnapshot -Suffix nightly
        Snapshots every file system on the array (one API call per file system).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]$SourceName,

        [Parameter()]
        [string]$Suffix,

        [Parameter()]
        [switch]$Send,

        [Parameter()]
        [string[]]$Targets,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        foreach ($name in $SourceName) {
            $queryParams = @{ 'source_names' = $name }
            if ($Send)                              { $queryParams['send']    = 'true' }
            if ($Targets -and $Targets.Count -gt 0) { $queryParams['targets'] = $Targets -join ',' }

            # FlashBlade's POST /file-system-snapshots takes `suffix` in the request body
            # (FileSystemSnapshotPost schema), NOT as a query parameter. Passing it via query
            # is silently ignored and the FB falls back to an auto-generated timestamp suffix.
            $body = $null
            if ($Suffix) { $body = @{ suffix = $Suffix } }

            if ($PSCmdlet.ShouldProcess($name, 'Create file system snapshot')) {
                Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-snapshots' -QueryParams $queryParams -Body $body
            }
        }
    }
}
