#Requires -Version 7.0
<#
.SYNOPSIS
    Builds/updates the REST-API-version <-> Purity//FB-version map from the SSOT
    (Single Source of Truth) API.
.DESCRIPTION
    Each FlashBlade REST API version has a corresponding row in a single "FlashBlade
    Management REST API Reference" table, exposed by a scoped SSOT API proxy in front of
    Fluid Topics (owner: ***REMOVED*** / ***REMOVED***, delta-synced nightly from FT). This
    fetches that table in one call and derives the REST<->Purity//FB pairing, writing
    Data/PfbVersionMap.json so runtime code (Phase 2's capability check) can render
    messages like "requires REST 2.26 / Purity//FB 4.8.1" without a live lookup.

    When no API key is configured (local dev without a key, or CI without the secret
    set), this script does not fail - it reports which versions still need lookup and
    exits, leaving PfbVersionMap.json untouched.
.PARAMETER SsotApiKey
    API key for the SSOT proxy (`x-api-key` header). Defaults to $env:SSOT_API_KEY.
.PARAMETER Versions
    REST versions to look up (e.g. '2.26','2.27'). Defaults to every version discovered
    under tools/specs/ that is not yet present in Data/PfbVersionMap.json.
.PARAMETER OutputPath
    Where to write the map. Defaults to Data/PfbVersionMap.json relative to the repo root.
#>
[CmdletBinding()]
param(
    [string]$SsotApiKey = $env:SSOT_API_KEY,

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

if (-not $SsotApiKey) {
    Write-Warning @"
No SSOT API key configured (`$env:SSOT_API_KEY` / -SsotApiKey not set). This step is
skipped in that case rather than failing - CI will proceed without updating the version
map, and Data/PfbVersionMap.json is left untouched.

Versions still needing a REST<->Purity mapping: $($Versions -join ', ')
"@
    return
}

# --- Fetch + parse the full mapping table in one call ---

$uri = Get-PfbSsotVersionMapUri
Write-Host "Fetching $uri..." -ForegroundColor Cyan

$response = Invoke-WebRequest -Uri $uri -Headers @{ 'x-api-key' = $SsotApiKey } -UseBasicParsing
$parsed = ConvertFrom-PfbSsotVersionMapHtml -Html $response.Content

$updated = $false
foreach ($version in $Versions) {
    if ($parsed.Contains($version)) {
        $existingMap[$version] = $parsed[$version]
        $updated = $true
        Write-Host "  -> REST $version = Purity//FB $($parsed[$version].purity)" -ForegroundColor Green
    }
    else {
        Write-Warning "SSOT table has no row for REST $version."
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
