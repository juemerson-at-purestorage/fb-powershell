function Assert-PfbApiCapability {
    <#
    .SYNOPSIS
        Throws before an API call is sent if the connected array's REST version does not
        support the requested endpoint, query parameter, or request-body field.
    .DESCRIPTION
        Looks up Data/PfbCapabilityMap.json (built by tools/Build-PfbCapabilityMap.ps1) for
        the "$Method $Endpoint" being called. If the map is unavailable, or the endpoint is
        not present in it, this is a deliberate no-op: the map may be stale, or the endpoint
        may take path parameters not captured by the map's flat key format. A capability
        check must never be the reason a call that would otherwise succeed gets blocked.
    .PARAMETER ApiVersion
        Overrides the version to check against instead of $Array.ApiVersion (mirrors
        Invoke-PfbApiRequest's -ApiVersionOverride).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Array,

        [Parameter(Mandatory)]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [hashtable]$Body,

        [Parameter()]
        [hashtable]$QueryParams,

        [Parameter()]
        [string]$ApiVersion
    )

    $map = Get-PfbCapabilityMap
    if (-not $map) { return }

    $normalizedEndpoint = '/' + $Endpoint.TrimStart('/')
    $key = "$Method $normalizedEndpoint"
    $entry = $map.endpoints.$key
    if (-not $entry) { return }

    $effectiveVersion = if ($ApiVersion) { $ApiVersion } else { $Array.ApiVersion }
    if (-not $effectiveVersion) { return }

    $versionMap = Get-PfbVersionMap

    function Format-PfbVersionDescription {
        param([string]$RestVersion)
        $purity = $versionMap.$RestVersion.purity
        if ($purity) { return "REST $RestVersion (Purity//FB $purity)" }
        return "REST $RestVersion"
    }

    $violations = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-PfbVersionAtLeast -Have $effectiveVersion -Need $entry.minVersion)) {
        $violations.Add("$key requires $(Format-PfbVersionDescription $entry.minVersion)")
    }

    if ($QueryParams) {
        foreach ($paramName in $QueryParams.Keys) {
            $value = $QueryParams[$paramName]
            if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrEmpty($value))) { continue }

            $introducedIn = $entry.parameters.$paramName
            if ($introducedIn -and -not (Test-PfbVersionAtLeast -Have $effectiveVersion -Need $introducedIn)) {
                $violations.Add("parameter '$paramName' on $key requires $(Format-PfbVersionDescription $introducedIn)")
            }
        }
    }

    if ($Body) {
        foreach ($propName in $Body.Keys) {
            $introducedIn = $entry.bodyProperties.$propName
            if ($introducedIn -and -not (Test-PfbVersionAtLeast -Have $effectiveVersion -Need $introducedIn)) {
                $violations.Add("request-body field '$propName' on $key requires $(Format-PfbVersionDescription $introducedIn)")
            }
        }
    }

    if ($violations.Count -eq 0) { return }

    $haveDescription = Format-PfbVersionDescription $effectiveVersion
    throw "$($violations -join '; '), but the connected array is running $haveDescription. Upgrade the array or omit the unsupported option(s)."
}
