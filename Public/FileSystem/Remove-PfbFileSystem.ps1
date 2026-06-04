function Remove-PfbFileSystem {
    <#
    .SYNOPSIS
        Removes (destroys or eradicates) a file system from the FlashBlade.
    .DESCRIPTION
        Destroys a file system (soft delete) or eradicates a previously destroyed file system
        (permanent delete). Destroyed file systems can be recovered within 24 hours using
        Update-PfbFileSystem -Name "fs1" -Destroyed $false.
    .PARAMETER Name
        The name of the file system to remove.
    .PARAMETER Id
        The ID of the file system to remove.
    .PARAMETER Eradicate
        Permanently eradicate a destroyed file system. Cannot be undone.
    .PARAMETER DeleteLinkOnEradication
        When eradicating a file system that participates in a replica link, ALSO delete
        the link as part of the eradication. Without this, the FB refuses the eradicate
        with "Please specify delete-link-on-eradication". Only meaningful with -Eradicate.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbFileSystem -Name "fs1"
    .EXAMPLE
        Remove-PfbFileSystem -Name "fs1" -Eradicate
    .EXAMPLE
        Remove-PfbFileSystem -Name "fs1" -Eradicate -DeleteLinkOnEradication
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()]
        [switch]$Eradicate,

        [Parameter()]
        [switch]$DeleteLinkOnEradication,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }


    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if (-not $Eradicate) {
            # Soft delete: first disable all protocols, then PATCH destroyed = true.
            # FB requires `delete_link_on_eradication=true` here too when the file system
            # has a replica link - the destroy is the point at which FB warns the link
            # will be removed at eradication time.
            $destroyQuery = @{} + $queryParams
            if ($DeleteLinkOnEradication) { $destroyQuery['delete_link_on_eradication'] = 'true' }

            if ($PSCmdlet.ShouldProcess($target, 'Destroy file system')) {
                $disableBody = @{
                    nfs  = @{ v3_enabled = $false; v4_1_enabled = $false }
                    smb  = @{ enabled = $false }
                    http = @{ enabled = $false }
                }
                try {
                    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'file-systems' -Body $disableBody -QueryParams $queryParams | Out-Null
                } catch { }
                $body = @{ destroyed = $true }
                Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'file-systems' -Body $body -QueryParams $destroyQuery
            }
        }
        else {
            # Hard delete: DELETE. Tear down replica links as part of eradication if requested.
            if ($DeleteLinkOnEradication) { $queryParams['delete_link_on_eradication'] = 'true' }
            if ($PSCmdlet.ShouldProcess($target, 'Eradicate file system (PERMANENT)')) {
                Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems' -QueryParams $queryParams
            }
        }
    }
}
