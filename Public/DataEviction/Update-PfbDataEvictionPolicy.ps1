function Update-PfbDataEvictionPolicy {
    <#
    .SYNOPSIS
        Modifies a data eviction policy on the FlashBlade.
    .DESCRIPTION
        Updates `keep_size`, `enabled`, or the policy name. At least one of these must be
        specified.
    .PARAMETER Name
        Current policy name.
    .PARAMETER Id
        Current policy ID.
    .PARAMETER NewName
        Rename the policy.
    .PARAMETER KeepSize
        New `keep_size` value in bytes.
    .PARAMETER Enabled
        Enable or disable the policy. Pass $true / $false; omit to leave unchanged.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Update-PfbDataEvictionPolicy -Name 'tier-out-100tb' -KeepSize 200TB
    .EXAMPLE
        Update-PfbDataEvictionPolicy -Name 'tier-out-100tb' -Enabled $false
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
        [Parameter()] [ValidateRange(1, [long]::MaxValue)] [long]$KeepSize,
        [Parameter()] [nullable[bool]]$Enabled,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id)   { $queryParams['ids']   = $Id }

    $body = @{}
    if ($PSBoundParameters.ContainsKey('NewName'))  { $body['name']      = $NewName }
    if ($PSBoundParameters.ContainsKey('KeepSize')) { $body['keep_size'] = $KeepSize }
    if ($PSBoundParameters.ContainsKey('Enabled'))  { $body['enabled']   = [bool]$Enabled }

    if ($body.Count -eq 0) {
        throw 'Update-PfbDataEvictionPolicy requires at least one of: -NewName, -KeepSize, -Enabled.'
    }

    $target = if ($Name) { $Name } else { $Id }
    if ($PSCmdlet.ShouldProcess($target, 'Update data eviction policy')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'data-eviction-policies' -QueryParams $queryParams -Body $body
    }
}
