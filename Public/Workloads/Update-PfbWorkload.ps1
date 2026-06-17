function Update-PfbWorkload {
    <#
    .SYNOPSIS
        Modifies a workload on the FlashBlade.
    .DESCRIPTION
        PATCHes a workload. Supports rename and soft-destroy / recovery via the -Destroyed
        switch. Pass -Destroyed to mark a workload as pending eradication; pass
        -Destroyed:$false to recover one within the eradication window.
    .PARAMETER Name
        Workload name to update.
    .PARAMETER Id
        Workload ID to update.
    .PARAMETER NewName
        Rename the workload.
    .PARAMETER Destroyed
        Set the workload's destroyed state. $true marks for eradication, $false recovers a
        destroyed workload within the eradication window.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Update-PfbWorkload -Name wl1 -NewName wl1-renamed
    .EXAMPLE
        Update-PfbWorkload -Name wl1 -Destroyed
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()] [string]$NewName,
        [Parameter()] [nullable[bool]]$Destroyed,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id)   { $queryParams['ids']   = $Id }

    $body = @{}
    if ($PSBoundParameters.ContainsKey('NewName'))   { $body['name']      = $NewName }
    if ($PSBoundParameters.ContainsKey('Destroyed')) { $body['destroyed'] = [bool]$Destroyed }

    if ($body.Count -eq 0) {
        throw 'Update-PfbWorkload requires at least one of: -NewName, -Destroyed.'
    }

    $target = if ($Name) { $Name } else { $Id }
    if ($PSCmdlet.ShouldProcess($target, 'Update workload')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'workloads' -QueryParams $queryParams -Body $body
    }
}
