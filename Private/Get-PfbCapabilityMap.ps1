function Get-PfbCapabilityMap {
    <#
    .SYNOPSIS
        Loads and caches Data/PfbCapabilityMap.json, the generated manifest mapping each
        FlashBlade REST endpoint (and its parameters/request-body fields) to the REST
        version it was introduced in.
    .DESCRIPTION
        Returns $null if the manifest file is missing rather than throwing -- callers
        (Assert-PfbApiCapability) treat a missing/unloadable map as "nothing to check
        against" rather than a hard failure.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $script:PfbCapabilityMap) {
        return $script:PfbCapabilityMap
    }

    $path = Join-Path $script:PfbModuleRoot 'Data/PfbCapabilityMap.json'
    if (-not (Test-Path $path)) {
        return $null
    }

    $script:PfbCapabilityMap = Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 20
    return $script:PfbCapabilityMap
}
