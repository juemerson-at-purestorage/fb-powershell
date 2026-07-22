function Test-PfbVersionAtLeast {
    <#
    .SYNOPSIS
        Tests whether one REST API version string is numerically >= another.
    .DESCRIPTION
        Naive string comparison ranks '2.9' above '2.26'. Parses each into numeric
        Major/Minor components (same idiom as ConvertTo-PfbVersionObject) and compares
        those instead.
    .PARAMETER Have
        The version to test, e.g. the connected array's negotiated REST version.
    .PARAMETER Need
        The minimum version required.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Have,

        [Parameter(Mandatory)]
        [string]$Need
    )

    $haveParts = $Have -split '\.'
    $needParts = $Need -split '\.'
    $haveMajor = [int]$haveParts[0]
    $haveMinor = [int]$haveParts[1]
    $needMajor = [int]$needParts[0]
    $needMinor = [int]$needParts[1]

    if ($haveMajor -ne $needMajor) {
        return $haveMajor -gt $needMajor
    }
    return $haveMinor -ge $needMinor
}
