function Remove-PfbWorkload {
    <#
    .SYNOPSIS
        Eradicates a (previously destroyed) workload on the FlashBlade.
    .DESCRIPTION
        Permanently deletes a workload. To soft-destroy a workload first, use
        Update-PfbWorkload -Destroyed. This cmdlet then permanently eradicates it.
    .PARAMETER Name
        Workload name to eradicate.
    .PARAMETER Id
        Workload ID to eradicate.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Remove-PfbWorkload -Name wl1
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()] [PSCustomObject]$Array
    )

    begin { Assert-PfbConnection -Array ([ref]$Array) }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Eradicate workload')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'workloads' -QueryParams $queryParams
        }
    }
}
