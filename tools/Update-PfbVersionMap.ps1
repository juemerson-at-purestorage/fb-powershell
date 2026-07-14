#Requires -Version 7.0
<#
.SYNOPSIS
    Builds/updates the REST-API-version <-> Purity//FB-version map from per-version
    release notes.
.DESCRIPTION
    Each FlashBlade REST API version has a corresponding "Purity//FB Management REST API
    X.Y Release Notes" page. This script derives that pairing (plus, best-effort, a short
    human-readable summary of changes) and writes Data/PfbVersionMap.json, so runtime code
    (Phase 2's capability check) can render messages like "requires REST 2.26 / Purity//FB
    4.8.1" without a live lookup.

    STATUS: skeleton pending a working credential. The release-notes pages live behind
    auth at https://support.everpuredata.com/r/flashblade-release/... — confirmed
    returning HTTP 401 without a service-key token. The URL-derivation logic below (dot
    stripped, e.g. "2.27" -> ".../purityfb-management-rest-api-227-release-notes") and the
    token-gated fetch plumbing are implemented and tested; the actual page-content parsing
    is NOT yet implemented because no authenticated sample page has been seen. Once a
    service-key secret is available, fetch one real page and replace the TODO in
    Get-PfbVersionMapEntryFromHtml below with real selectors.

    When no token is configured (local dev without a key, or CI without the secret set),
    this script does not fail — it reports which versions still need lookup and exits,
    leaving PfbVersionMap.json untouched. In that case, populate entries via the
    Glean-assisted flow instead (ask an agent with Glean access to look up "Purity//FB
    Management REST API 2.N Release Notes" and merge results manually) - this path is
    interactive/local-only and cannot run in headless CI.
.PARAMETER SupportToken
    Bearer token for the Everpure support site. Defaults to $env:EVERPURE_SUPPORT_TOKEN.
.PARAMETER Versions
    REST versions to look up (e.g. '2.26','2.27'). Defaults to every version discovered
    under tools/specs/ that is not yet present in Data/PfbVersionMap.json.
.PARAMETER OutputPath
    Where to write the map. Defaults to Data/PfbVersionMap.json relative to the repo root.
#>
[CmdletBinding()]
param(
    [string]$SupportToken = $env:EVERPURE_SUPPORT_TOKEN,

    [string[]]$Versions,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir 'lib/PfbVersionMapTools.ps1')

if (-not $OutputPath) {
    $OutputPath = Join-Path (Join-Path $repoRoot 'Data') 'PfbVersionMap.json'
}

# --- Determine which versions need looking up ---

$existingMap = [ordered]@{}
if (Test-Path $OutputPath) {
    (Get-Content -Path $OutputPath -Raw | ConvertFrom-Json -Depth 5).PSObject.Properties |
        ForEach-Object { $existingMap[$_.Name] = $_.Value }
}

if (-not $Versions) {
    $specsDir = Join-Path $scriptDir 'specs'
    if (Test-Path $specsDir) {
        $Versions = Get-ChildItem -Path $specsDir -Filter 'fb*.json' |
            Where-Object { $_.BaseName -match '^fb(\d+\.\d+)$' } |
            ForEach-Object { $Matches[1] } |
            Where-Object { -not $existingMap.Contains($_) }
    }
}

if (-not $Versions) {
    Write-Host 'No versions need looking up (nothing new since the last run).' -ForegroundColor Green
    return
}

if (-not $SupportToken) {
    Write-Warning @"
No support-site token configured (`$env:EVERPURE_SUPPORT_TOKEN` / -SupportToken not set).
This step is skipped in that case rather than failing — CI will proceed without updating
the version map, and Data/PfbVersionMap.json is left untouched.

Versions still needing a REST<->Purity mapping: $($Versions -join ', ')

To fill these in without a service key, ask an agent with Glean access to look up
"Purity//FB Management REST API <version> Release Notes" for each and merge the results
into $OutputPath by hand.
"@
    return
}

# --- Fetch + parse (best-effort; see STATUS note above) ---

$updated = $false
foreach ($version in $Versions) {
    $url = ConvertTo-PfbSupportNotesUrl -RestVersion $version
    Write-Host "Fetching $url..." -ForegroundColor Cyan

    try {
        $response = Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Bearer $SupportToken" } -UseBasicParsing
    }
    catch {
        Write-Warning "Failed to fetch release notes for REST $version : $($_.Exception.Message)"
        continue
    }

    $entry = Get-PfbVersionMapEntryFromHtml -Html $response.Content -RestVersion $version
    if ($entry) {
        $existingMap[$version] = $entry
        $updated = $true
        Write-Host "  -> REST $version = Purity//FB $($entry.purity)" -ForegroundColor Green
    }
}

if ($updated) {
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $existingMap | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Wrote $OutputPath" -ForegroundColor Green
}
else {
    Write-Host 'No entries were successfully parsed; output left unchanged.' -ForegroundColor Yellow
}
