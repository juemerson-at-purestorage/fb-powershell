<#
.SYNOPSIS
    Shared helpers for tools/Update-PfbVersionMap.ps1. Split out from that script so the
    pure, fully-specified pieces (URI construction, HTML table parsing) are unit-testable
    independent of the network-dependent orchestration.
#>

function Get-PfbSsotVersionMapUri {
    <#
    .SYNOPSIS
        Builds the SSOT (Single Source of Truth) API URI for the FlashBlade REST API
        version <-> Purity//FB mapping topic.
    .DESCRIPTION
        The SSOT API is a scoped proxy in front of Fluid Topics (owner: ***REMOVED*** /
        ***REMOVED***), delta-synced nightly. This one endpoint returns the full REST-version-
        to-Purity//FB mapping table as HTML in a single call - no per-version fetches
        needed. Auth is an `x-api-key` header (see tools/Update-PfbVersionMap.ps1), not a
        bearer token.
    .EXAMPLE
        Get-PfbSsotVersionMapUri
    #>
    [CmdletBinding()]
    param(
        [string]$BaseUri = 'https://***REMOVED***',
        [string]$TopicId = '***REMOVED***'
    )

    return "$BaseUri/v1/topics/$TopicId/content"
}

function ConvertFrom-PfbSsotVersionMapHtml {
    <#
    .SYNOPSIS
        Parses the SSOT version-mapping topic's HTML into a REST-version -> { purity }
        map covering every row in the table.
    .DESCRIPTION
        The table has (at least) four columns: REST API Version | HTML | Introduced in
        Purity//FB | Ships with Purity//FB. This uses the "Introduced in" column, matching
        the existing hand-maintained Data/PfbVersionMap.json convention. Rows that don't
        have a "REST API X.Y" first cell (e.g. the header row) or that have fewer than 4
        cells are skipped rather than erroring, since the table also carries the legacy
        REST 1.x line, which this module doesn't track.

        Parsed with regex rather than a DOM parser so this runs identically on Windows and
        the ubuntu-latest CI runner (no HTMLFile COM object, which is Windows-only).
    .OUTPUTS
        [ordered] hashtable keyed by bare REST version (e.g. '2.27') -> @{ purity = '4.8.3' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Html
    )

    $map = [ordered]@{}

    $rowMatches = [regex]::Matches($Html, '<tr[^>]*>(.*?)</tr>', 'Singleline, IgnoreCase')
    foreach ($rowMatch in $rowMatches) {
        $cellMatches = [regex]::Matches($rowMatch.Groups[1].Value, '<t[dh][^>]*>(.*?)</t[dh]>', 'Singleline, IgnoreCase')
        if ($cellMatches.Count -lt 4) {
            continue
        }

        $cells = $cellMatches | ForEach-Object {
            $text = [regex]::Replace($_.Groups[1].Value, '<[^>]+>', '')
            $text = [System.Net.WebUtility]::HtmlDecode($text)
            $text.Trim()
        }

        $versionMatch = [regex]::Match($cells[0], 'REST API (\d+\.\d+)')
        if (-not $versionMatch.Success) {
            continue
        }

        $map[$versionMatch.Groups[1].Value] = [PSCustomObject]@{
            purity = $cells[2]
        }
    }

    return $map
}
