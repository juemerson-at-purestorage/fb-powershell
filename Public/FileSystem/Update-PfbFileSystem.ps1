function Update-PfbFileSystem {
    <#
    .SYNOPSIS
        Updates an existing file system on the FlashBlade.
    .DESCRIPTION
        Modifies file system attributes such as size, protocol settings, and policies.
    .PARAMETER Name
        The name of the file system to update.
    .PARAMETER Id
        The ID of the file system to update.
    .PARAMETER Provisioned
        The new provisioned size in bytes.
    .PARAMETER HardLimitEnabled
        Enable or disable hard limit on provisioned size.
    .PARAMETER NfsEnabled
        Enable or disable NFS protocol access.
    .PARAMETER NfsRules
        NFS export rules.
    .PARAMETER NfsExportPolicy
        Name of an existing NFS Export Policy to attach.
    .PARAMETER SmbEnabled
        Enable or disable SMB protocol access.
    .PARAMETER SmbSharePolicy
        Name of an existing SMB Share Policy to attach. Used by the lockdown->production
        flip pattern: create the FS with a restrictive policy, then PATCH to the production
        policy after applying NTFS ACLs.
    .PARAMETER SmbClientPolicy
        Name of an existing SMB Client Policy (IP / hostname allowlist) to attach.
    .PARAMETER HttpEnabled
        Enable or disable HTTP protocol access.
    .PARAMETER Destroyed
        Set to $true to destroy or $false to recover the file system.
    .PARAMETER RequestedPromotionState
        The requested promotion state of the file system: 'promoted' (read-write) or
        'demoted' (read-only replication target). Demoting is only allowed when the file
        system is in a replica-link relationship and requires -DiscardNonSnapshottedData.
        Mutually exclusive with -Attributes (supply the field via -Attributes instead if you
        are already passing a raw attribute hashtable).
    .PARAMETER DiscardNonSnapshottedData
        When demoting a file system (requested_promotion_state = 'demoted'), acknowledge and
        discard any data written since the last replicated snapshot. Sent as the
        discard_non_snapshotted_data=true query parameter. Has no effect on a promote.
    .PARAMETER Attributes
        A hashtable of attributes to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbFileSystem -Name "fs1" -Provisioned 2147483648
    .EXAMPLE
        Update-PfbFileSystem -Name "fs1" -Attributes @{ provisioned = 2147483648 }
    .EXAMPLE
        # Demote a file system to a read-only replication target, discarding un-replicated writes
        Update-PfbFileSystem -Name "fs1" -RequestedPromotionState demoted -DiscardNonSnapshottedData
    .EXAMPLE
        # Equivalent demote using a raw attribute hashtable
        Update-PfbFileSystem -Name "fs1" -Attributes @{ requested_promotion_state = 'demoted' } -DiscardNonSnapshottedData
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [int64]$Provisioned,

        [Parameter()]
        [Nullable[bool]]$HardLimitEnabled,

        [Parameter()]
        [Nullable[bool]]$NfsEnabled,

        [Parameter()]
        [string]$NfsRules,

        [Parameter()]
        [string]$NfsExportPolicy,

        [Parameter()]
        [Nullable[bool]]$SmbEnabled,

        [Parameter()]
        [string]$SmbSharePolicy,

        [Parameter()]
        [string]$SmbClientPolicy,

        [Parameter()]
        [Nullable[bool]]$HttpEnabled,

        [Parameter()]
        [Nullable[bool]]$Destroyed,

        [Parameter()]
        [ValidateSet('promoted', 'demoted')]
        [string]$RequestedPromotionState,

        [Parameter()]
        [switch]$DiscardNonSnapshottedData,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes -and $RequestedPromotionState) {
            throw "-Attributes and -RequestedPromotionState are mutually exclusive. Set 'requested_promotion_state' inside -Attributes, or use -RequestedPromotionState on its own."
        }

        if ($Attributes) {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($Provisioned -gt 0)          { $body['provisioned'] = $Provisioned }
            if ($PSBoundParameters.ContainsKey('HardLimitEnabled')) { $body['hard_limit_enabled'] = [bool]$HardLimitEnabled }
            if ($PSBoundParameters.ContainsKey('Destroyed'))        { $body['destroyed'] = [bool]$Destroyed }

            # NFS - local var name avoids collision with parameters (same as New-PfbFileSystem)
            $nfsBody = @{}
            if ($PSBoundParameters.ContainsKey('NfsEnabled')) { $nfsBody['v3_enabled'] = [bool]$NfsEnabled; $nfsBody['v4_1_enabled'] = [bool]$NfsEnabled }
            if ($NfsRules)                                    { $nfsBody['rules'] = $NfsRules }
            if ($NfsExportPolicy)                             { $nfsBody['export_policy'] = @{ name = $NfsExportPolicy } }
            if ($nfsBody.Count -gt 0)                         { $body['nfs'] = $nfsBody }

            # SMB - flip share / client policy here (lockdown -> production workflow)
            $smbBody = @{}
            if ($PSBoundParameters.ContainsKey('SmbEnabled')) { $smbBody['enabled'] = [bool]$SmbEnabled }
            if ($SmbSharePolicy)                              { $smbBody['share_policy']  = @{ name = $SmbSharePolicy } }
            if ($SmbClientPolicy)                             { $smbBody['client_policy'] = @{ name = $SmbClientPolicy } }
            if ($smbBody.Count -gt 0)                         { $body['smb'] = $smbBody }

            if ($PSBoundParameters.ContainsKey('HttpEnabled')) { $body['http'] = @{ enabled = [bool]$HttpEnabled } }

            if ($RequestedPromotionState) { $body['requested_promotion_state'] = $RequestedPromotionState }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        if ($DiscardNonSnapshottedData) { $queryParams['discard_non_snapshotted_data'] = 'true' }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update file system')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'file-systems' -Body $body -QueryParams $queryParams
        }
    }
}
