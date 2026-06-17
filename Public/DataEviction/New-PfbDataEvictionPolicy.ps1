function New-PfbDataEvictionPolicy {
    <#
    .SYNOPSIS
        Creates a new data eviction policy on the FlashBlade.
    .DESCRIPTION
        A data eviction policy defines a `keep_size` threshold (in bytes) above which the
        FB evicts data to tiered storage. The policy is created in disabled-on-attach
        mode by default; pass -Disabled to create it disabled.
    .PARAMETER Name
        Policy name to create.
    .PARAMETER KeepSize
        Maximum physical data space (in bytes) before eviction triggers. Required.
        Use the standard PowerShell size suffixes: `100GB`, `1TB`, etc.
    .PARAMETER Disabled
        Create the policy disabled. Default is enabled.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        New-PfbDataEvictionPolicy -Name 'tier-out-100tb' -KeepSize 100TB
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(Mandatory)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$KeepSize,

        [Parameter()] [switch]$Disabled,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{ 'names' = $Name -join ',' }
    $body = @{
        keep_size = $KeepSize
        enabled   = -not $Disabled.IsPresent
    }

    if ($PSCmdlet.ShouldProcess(($Name -join ', '), "Create data eviction policy (keep_size=$KeepSize)")) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'data-eviction-policies' -QueryParams $queryParams -Body $body
    }
}
