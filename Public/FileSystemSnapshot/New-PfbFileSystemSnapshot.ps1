function New-PfbFileSystemSnapshot {
    <#
    .SYNOPSIS
        Creates a snapshot of one or more file systems.
    .PARAMETER SourceName
        Name of the source file system(s) to snapshot. Accepts pipeline input by
        property name (aliased to 'Name'), so `Get-PfbFileSystem | New-PfbFileSystemSnapshot`
        snapshots every piped file system in a single request.
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
        Snapshots every file system on the array in one request.
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
        $allSourceNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($SourceName) {
            foreach ($n in $SourceName) { $allSourceNames.Add($n) }
        }
    }

    end {
        $queryParams = @{ 'source_names' = $allSourceNames -join ',' }
        if ($Send)                              { $queryParams['send']    = 'true' }
        if ($Targets -and $Targets.Count -gt 0) { $queryParams['targets'] = $Targets -join ',' }

        # FlashBlade's POST /file-system-snapshots takes `suffix` in the request body
        # (FileSystemSnapshotPost schema), NOT as a query parameter. Passing it via query
        # is silently ignored and the FB falls back to an auto-generated timestamp suffix.
        $body = $null
        if ($Suffix) { $body = @{ suffix = $Suffix } }

        if ($PSCmdlet.ShouldProcess(($allSourceNames -join ', '), 'Create file system snapshot')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-snapshots' -QueryParams $queryParams -Body $body
        }
    }
}
