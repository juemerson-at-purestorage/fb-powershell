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

    $json = Get-Content -Path $path -Raw
    # ConvertFrom-Json has no -Depth parameter on Windows PowerShell 5.1 (added in PS6) --
    # 5.1's own recursion limit (100) is already far deeper than this manifest's shape.
    $script:PfbCapabilityMap = if ($PSVersionTable.PSVersion.Major -ge 6) {
        $json | ConvertFrom-Json -Depth 20
    }
    else {
        $json | ConvertFrom-Json
    }
    return $script:PfbCapabilityMap
}
