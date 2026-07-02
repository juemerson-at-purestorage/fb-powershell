function ConvertTo-PfbVersionObject {
    <#
    .SYNOPSIS
        Parses raw FlashBlade REST API version strings into sortable objects.
    .DESCRIPTION
        Converts strings like '2.9' or '2.26' into PSCustomObjects with numeric
        Major/Minor properties, so version comparisons and sorts are numerically
        correct. A naive string comparison would incorrectly rank '2.9' above '2.26'.
    .PARAMETER Versions
        An array of raw version strings (e.g. '1.8', '2.9', '2.26').
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Versions
    )

    $Versions | ForEach-Object {
        $parts = $_ -split '\.'
        [PSCustomObject]@{
            Version = $_
            Major   = [int]$parts[0]
            Minor   = [int]$parts[1]
        }
    } | Sort-Object Major, Minor -Descending
}
