function New-PfbWorkload {
    <#
    .SYNOPSIS
        Creates a new workload on the FlashBlade from a workload preset.
    .DESCRIPTION
        A workload is instantiated from a workload preset. Supply one or more new workload
        names and either -PresetName or -PresetId to identify the preset that defines the
        shape of the storage resources to create. -Parameters supplies values for any preset
        parameters that don't have defaults.
    .PARAMETER Name
        Name(s) for the new workload(s). One workload is created per name.
    .PARAMETER PresetName
        Name of the workload preset to instantiate from. Mutually exclusive with -PresetId.
    .PARAMETER PresetId
        ID of the workload preset to instantiate from. Mutually exclusive with -PresetName.
    .PARAMETER Parameters
        Optional array of parameter hashtables to satisfy the preset's parameter list:
        @( @{ name = 'size_gb'; value = '500' }, @{ name = 'env'; value = 'prod' } )
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        New-PfbWorkload -Name 'analytics-prod' -PresetName 'analytics-template'
    .EXAMPLE
        New-PfbWorkload -Name 'wl1' -PresetName 'preset1' -Parameters @(@{ name='size_gb'; value='1000' })
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByPresetName')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByPresetName')]
        [ValidateNotNullOrEmpty()]
        [string]$PresetName,

        [Parameter(Mandatory, ParameterSetName = 'ByPresetId')]
        [ValidateNotNullOrEmpty()]
        [string]$PresetId,

        [Parameter()]
        [hashtable[]]$Parameters,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{ 'names' = $Name -join ',' }
    if ($PresetName) { $queryParams['preset_names'] = $PresetName }
    if ($PresetId)   { $queryParams['preset_ids']   = $PresetId }

    $body = @{}
    if ($Parameters) { $body['parameters'] = @($Parameters) }

    if ($PSCmdlet.ShouldProcess(($Name -join ', '), 'Create workload')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'workloads' -QueryParams $queryParams -Body $body
    }
}
