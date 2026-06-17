function New-PfbWorkloadPlacementRecommendation {
    <#
    .SYNOPSIS
        Computes workload placement recommendations from inputs.
    .DESCRIPTION
        POSTs a placement-recommendation request. Given target placement names and one or
        more workload presets, the FlashBlade computes a ranked recommendation of where the
        workloads should be placed. Pass -Inputs as the optional request body for additional
        constraints.
    .PARAMETER PlacementName
        One or more target placement names to consider.
    .PARAMETER PresetName
        Workload preset name(s) the recommendation should be computed against.
    .PARAMETER PresetId
        Workload preset ID(s).
    .PARAMETER Inputs
        Optional hashtable matching the WorkloadPlacementRecommendation schema for
        additional constraints (e.g. capacity, performance hints).
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        New-PfbWorkloadPlacementRecommendation -PresetName 'analytics-template' -PlacementName 'cluster-east'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter()] [string[]]$PlacementName,
        [Parameter()] [string[]]$PresetName,
        [Parameter()] [string[]]$PresetId,
        [Parameter()] [hashtable]$Inputs,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PlacementName) { $queryParams['placement_names'] = $PlacementName -join ',' }
    if ($PresetName)    { $queryParams['preset_names']    = $PresetName -join ',' }
    if ($PresetId)      { $queryParams['preset_ids']      = $PresetId -join ',' }

    $body = if ($Inputs) { $Inputs } else { @{} }

    if ($PSCmdlet.ShouldProcess('placement-recommendations', 'Compute workload placement recommendation')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'workloads/placement-recommendations' -QueryParams $queryParams -Body $body
    }
}
