function Remove-PfbWorkloadTag {
    <#
    .SYNOPSIS
        Removes tags from FlashBlade workloads.
    .DESCRIPTION
        Deletes specific tag keys from one or more workloads, optionally scoped to a
        namespace.
    .PARAMETER ResourceName
        Workload name(s) to remove tags from.
    .PARAMETER ResourceId
        Workload ID(s) to remove tags from.
    .PARAMETER Key
        Tag key(s) to remove.
    .PARAMETER Namespace
        Tag namespace(s) the keys live in.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Remove-PfbWorkloadTag -ResourceName wl1 -Key 'team','env'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$ResourceName,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$ResourceId,

        [Parameter(Mandatory)]
        [string[]]$Key,

        [Parameter()] [string[]]$Namespace,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{ 'keys' = $Key -join ',' }
    if ($ResourceName) { $queryParams['resource_names'] = $ResourceName -join ',' }
    if ($ResourceId)   { $queryParams['resource_ids']   = $ResourceId -join ',' }
    if ($Namespace)    { $queryParams['namespaces']     = $Namespace -join ',' }

    $target = if ($ResourceName) { $ResourceName -join ', ' } elseif ($ResourceId) { $ResourceId -join ', ' } else { '(all workloads)' }
    if ($PSCmdlet.ShouldProcess($target, "Remove tag(s) $($Key -join ', ')")) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'workloads/tags' -QueryParams $queryParams
    }
}
