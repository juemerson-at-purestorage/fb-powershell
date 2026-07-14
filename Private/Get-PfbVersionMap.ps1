function Get-PfbVersionMap {
    <#
    .SYNOPSIS
        Loads and caches Data/PfbVersionMap.json, the REST-version to Purity//FB-version
        pairing.
    .DESCRIPTION
        Returns $null if the file is missing. This map is purely cosmetic -- it only
        enriches capability-check error messages with a Purity//FB version alongside the
        REST version; a missing map never blocks a call.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $script:PfbVersionMap) {
        return $script:PfbVersionMap
    }

    $path = Join-Path $script:PfbModuleRoot 'Data/PfbVersionMap.json'
    if (-not (Test-Path $path)) {
        return $null
    }

    $script:PfbVersionMap = Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 5
    return $script:PfbVersionMap
}
