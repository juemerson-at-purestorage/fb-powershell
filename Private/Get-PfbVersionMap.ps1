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

    $json = Get-Content -Path $path -Raw
    # ConvertFrom-Json has no -Depth parameter on Windows PowerShell 5.1 (added in PS6) --
    # 5.1's own recursion limit (100) is already far deeper than this manifest's shape.
    $script:PfbVersionMap = if ($PSVersionTable.PSVersion.Major -ge 6) {
        $json | ConvertFrom-Json -Depth 5
    }
    else {
        $json | ConvertFrom-Json
    }
    return $script:PfbVersionMap
}
