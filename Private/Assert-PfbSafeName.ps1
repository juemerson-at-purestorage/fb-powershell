function Assert-PfbSafeName {
    <#
    .SYNOPSIS
        Reject names that look like wildcards or empty strings, to prevent accidental
        bulk delete via -Name '*'.
    .DESCRIPTION
        Used as a [ValidateScript({Assert-PfbSafeName $_})] on -Name parameters of
        destructive cmdlets (Remove-Pfb*, Eradicate). The FlashBlade API does not
        interpret '*' as a wildcard on names=, but defending against the typo
        is cheap and prevents user error from compounding into a real outage
        if the API behavior ever changes.
    #>
    param([Parameter(Mandatory)] [object]$Value)

    foreach ($v in @($Value)) {
        if ([string]::IsNullOrWhiteSpace($v))           { throw "Name cannot be empty or whitespace." }
        if ($v -eq '*' -or $v -eq '%')                  { throw "Name '$v' looks like a wildcard. Pass an explicit name or list of names." }
        if ($v -match '[\*\?]')                         { throw "Name '$v' contains wildcard characters (* or ?). Pass explicit names." }
    }
    return $true
}
