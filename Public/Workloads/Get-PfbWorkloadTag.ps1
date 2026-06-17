function Get-PfbWorkloadTag {
    <#
    .SYNOPSIS
        Retrieves tags applied to FlashBlade workloads.
    .DESCRIPTION
        Lists tags for one or more workloads, optionally filtered by namespace.
    .PARAMETER ResourceName
        Workload name(s) to fetch tags for.
    .PARAMETER ResourceId
        Workload ID(s) to fetch tags for.
    .PARAMETER Namespace
        Tag namespace(s) to filter by.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Get-PfbWorkloadTag -ResourceName wl1
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$ResourceName,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$ResourceId,

        [Parameter()] [string[]]$Namespace,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($ResourceName) { $queryParams['resource_names'] = $ResourceName -join ',' }
    if ($ResourceId)   { $queryParams['resource_ids']   = $ResourceId -join ',' }
    if ($Namespace)    { $queryParams['namespaces']     = $Namespace -join ',' }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'workloads/tags' -QueryParams $queryParams
}
