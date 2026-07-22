function Remove-PfbFileSystemSession {
    <#
    .SYNOPSIS
        Terminates one or more file system sessions on the FlashBlade.
    .DESCRIPTION
        Forces the termination of active client session(s). This is a disruptive operation
        that disconnects the client(s) and may cause in-progress operations to fail.

        Two mutually exclusive modes are supported, matching the real REST endpoint's own
        rules (live-confirmed: the server rejects combining `names` with any other query
        parameter, including `protocols`):
        - -Name: terminates one specific session, identified by the session's own generated
          name (as returned in the Name property of Get-PfbFileSystemSession's output) --
          NOT a file system name.
        - -Protocol: bulk-terminates every active session using the given protocol(s),
          across the entire array, regardless of file system or client. Cannot be combined
          with -Name. The server requires an internal "disruptive" flag for this
          single-filter bulk mode, which this cmdlet sets automatically -- there is no
          narrower per-client/per-user filter exposed here, so any use of -Protocol affects
          every matching session array-wide. Because of that blast radius, -Protocol also
          requires -Force -- independent of $ConfirmPreference/-Confirm, so a caller who has
          globally lowered their confirm preference still cannot trigger a bulk purge without
          explicitly opting in.
    .PARAMETER Name
        The session's own generated name to terminate (as returned by
        Get-PfbFileSystemSession's Name property) -- NOT the name of a file system.
        Mandatory in the ByName parameter set; cannot be combined with -Protocol.
    .PARAMETER Protocol
        Bulk-terminates every active session using one or more specific protocols, across
        the entire array. Valid values are "nfs" and "smb". Cannot be combined with -Name --
        the server rejects that combination. This is an array-wide, cross-client operation;
        there is no narrower filter exposed by this cmdlet. Requires -Force.
    .PARAMETER Force
        Required alongside -Protocol to acknowledge the array-wide, cross-client blast radius
        of that bulk-terminate mode. This check is independent of $ConfirmPreference/-Confirm
        -- it cannot be bypassed by lowering the session's confirm preference, unlike the
        standard SupportsShouldProcess prompt this cmdlet also honors.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbFileSystemSession -Name "22517998136858346-smb"
        Terminates the single session with that session name.
    .EXAMPLE
        Remove-PfbFileSystemSession -Protocol 'smb' -Force -Confirm:$false
        Bulk-terminates every active SMB session on the array.
    .EXAMPLE
        Remove-PfbFileSystemSession -Name "22517998136858346-smb" -Confirm:$false
        Terminates the session without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByProtocol', Mandatory)]
        [ValidateSet('nfs', 'smb')]
        [string[]]$Protocol,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        $action = 'Terminate file system session'

        if ($PSCmdlet.ParameterSetName -eq 'ByProtocol') {
            if (-not $Force) {
                throw "Remove-PfbFileSystemSession -Protocol bulk-terminates EVERY active session using that protocol, across the entire array, for every client -- pass -Force to acknowledge this before it will run (independent of `$ConfirmPreference/-Confirm)."
            }
            $queryParams['protocols'] = $Protocol -join ','
            $queryParams['disruptive'] = 'true'
            $target = $Protocol -join ', '
            $action = 'Bulk-terminate ALL file system sessions using protocol(s)'
        }
        else {
            $queryParams['names'] = $Name
            $target = $Name
        }

        if ($PSCmdlet.ShouldProcess($target, $action)) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems/sessions' -QueryParams $queryParams
        }
    }
}
