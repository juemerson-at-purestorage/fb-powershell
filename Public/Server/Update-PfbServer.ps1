function Update-PfbServer {
    <#
    .SYNOPSIS
        Updates an existing server on the FlashBlade.
    .DESCRIPTION
        Modifies server attributes: DNS config and local directory service.
    .PARAMETER Name
        Name of the server to update.
    .PARAMETER Id
        ID of the server to update.
    .PARAMETER DnsName
        Name(s) of DNS configs to attach. FlashBlade accepts at most one.
    .PARAMETER LocalDirectoryService
        Name of the Local Directory Service to associate.
    .PARAMETER Attributes
        Full request body as a hashtable. Mutually exclusive with typed parameters.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Update-PfbServer -Name "server5" -DnsName "management"
    .EXAMPLE
        Update-PfbServer -Name "server5" -LocalDirectoryService "newds"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'IndividualByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'IndividualByName', ValueFromPipelineByPropertyName)]
        [Parameter(Mandatory, ParameterSetName = 'AttributesByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'IndividualById')]
        [Parameter(Mandatory, ParameterSetName = 'AttributesById')]
        [string]$Id,

        [Parameter(ParameterSetName = 'IndividualByName')]
        [Parameter(ParameterSetName = 'IndividualById')]
        [string[]]$DnsName,

        [Parameter(ParameterSetName = 'IndividualByName')]
        [Parameter(ParameterSetName = 'IndividualById')]
        [string]$LocalDirectoryService,

        [Parameter(Mandatory, ParameterSetName = 'AttributesByName')]
        [Parameter(Mandatory, ParameterSetName = 'AttributesById')]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($PSCmdlet.ParameterSetName -like 'Attributes*') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('DnsName')) {
                $body['dns'] = @($DnsName | ForEach-Object { @{ name = $_ } })
            }
            if ($PSBoundParameters.ContainsKey('LocalDirectoryService')) {
                $body['local_directory_service'] = @{ name = $LocalDirectoryService }
            }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update server')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'servers' -Body $body -QueryParams $queryParams
        }
    }
}
