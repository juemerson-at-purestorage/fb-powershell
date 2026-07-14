<#
.SYNOPSIS
    Shared helpers for tools/Update-PfbVersionMap.ps1. Split out from that script so the
    pure, fully-specified pieces (URL derivation) are unit-testable independent of the
    network-dependent orchestration and the not-yet-implemented page parsing.
#>

function ConvertTo-PfbSupportNotesUrl {
    <#
    .SYNOPSIS
        Derives the Everpure support-site URL for a REST version's release notes.
    .DESCRIPTION
        Pattern confirmed by the user against a real page for 2.27:
        https://support.everpuredata.com/r/flashblade-release/purityfb-management-rest-api-227-release-notes
        The dot in the REST version is stripped (2.27 -> 227). The page itself is
        confirmed to require authentication (401 without a token as of 2026-07-08).
    .EXAMPLE
        ConvertTo-PfbSupportNotesUrl -RestVersion '2.27'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+$')]
        [string]$RestVersion
    )

    $compact = $RestVersion -replace '\.', ''
    return "https://support.everpuredata.com/r/flashblade-release/purityfb-management-rest-api-$compact-release-notes"
}

function Get-PfbVersionMapEntryFromHtml {
    <#
    .SYNOPSIS
        Parses a fetched release-notes page into a { purity } entry.
    .DESCRIPTION
        TODO(unblocked-by-service-key): this parsing logic is UNVERIFIED against a real
        page. As of 2026-07-08 the release-notes page 401s without a service-key token,
        so no authenticated sample has been seen. This is a best-effort placeholder that
        scans the page text for a "Purity//FB X.Y.Z" pattern; replace with real selectors
        (or a structured content API, if the support platform has one) once a service key
        is available and a real page can be fetched.
    .OUTPUTS
        [PSCustomObject]@{ purity = '4.8.1' }, or $null if no pattern was found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Html,

        [Parameter(Mandatory)]
        [string]$RestVersion
    )

    $textMatch = [regex]::Match($Html, 'Purity\s*//\s*FB\s+(\d+\.\d+\.\d+)')
    if (-not $textMatch.Success) {
        Write-Warning "Could not find a 'Purity//FB X.Y.Z' pattern on the release-notes page for REST $RestVersion. Page format is unconfirmed - see the TODO in this function."
        return $null
    }

    return [PSCustomObject]@{
        purity = $textMatch.Groups[1].Value
    }
}
