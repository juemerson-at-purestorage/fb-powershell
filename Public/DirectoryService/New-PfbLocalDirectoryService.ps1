function New-PfbLocalDirectoryService {
    <#
    .SYNOPSIS
        Creates a local directory service on the FlashBlade.
    .DESCRIPTION
        Creates a local directory service (the on-array user/group database used for SMB
        NTFS permissions). Local groups and their memberships live under a local directory
        service. Endpoint: POST /directory-services/local/directory-services.
    .PARAMETER Name
        The name of the local directory service to create (sent as 'names').
    .PARAMETER Domain
        Optional domain name presented for users and groups in this local directory service.
        Defaults to the name (without container/realm prefix) when not set.
    .PARAMETER Attributes
        Optional hashtable merged into the request body for any additional fields.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbLocalDirectoryService -Name "mydomain"

        Creates a local directory service named "mydomain".
    .EXAMPLE
        New-PfbLocalDirectoryService -Name "myrealm::mydomain" -Domain "mydomain"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter()] [string]$Domain,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes.Clone() } else { @{} }
    if ($Domain) { $body['domain'] = $Domain }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create local directory service')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'directory-services/local/directory-services' -Body $body -QueryParams $queryParams
    }
}
