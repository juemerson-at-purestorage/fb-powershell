function New-PfbFileSystemSnapshot {
    <#
    .SYNOPSIS
        Creates a snapshot of one or more file systems.
    .PARAMETER SourceName
        Name of the source file system(s) to snapshot.
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
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
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

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{ 'source_names' = $SourceName -join ',' }
    if ($Send)                           { $queryParams['send']    = 'true' }
    if ($Targets -and $Targets.Count -gt 0) { $queryParams['targets'] = $Targets -join ',' }

    # FlashBlade's POST /file-system-snapshots takes `suffix` in the request body
    # (FileSystemSnapshotPost schema), NOT as a query parameter. Passing it via query
    # is silently ignored and the FB falls back to an auto-generated timestamp suffix.
    $body = $null
    if ($Suffix) { $body = @{ suffix = $Suffix } }

    if ($PSCmdlet.ShouldProcess(($SourceName -join ', '), 'Create file system snapshot')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-snapshots' -QueryParams $queryParams -Body $body
    }
}
