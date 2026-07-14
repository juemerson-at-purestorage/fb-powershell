#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the FlashBlade API capability manifest from cached OpenAPI specs.
.DESCRIPTION
    Loads every cached tools/specs/fb<version>.json in ascending version order and
    records, for each (HTTP method, normalized path), the earliest version it appears
    in — and likewise for each parameter name and request-body top-level property name
    on that endpoint. This is the data Phase 2's per-cmdlet capability check and Phase
    3's version-aware ArgumentCompleters will consume.

    Deliberately NOT included: per-enum-value "introduced in version X" tracking. The
    FlashBlade OpenAPI spec has no structural JSON Schema `enum` anywhere (verified
    against fb2.10 and fb2.27) — allowed values are documented only in free-text
    `description` prose, which is not reliably machine-diffable. See
    tools/lib/PfbSpecTools.ps1 for the full finding.

    Also NOT included (deferred, see plan): endpoint/field deprecation or removal
    tracking, and hardware-model (//S vs //E) capability — that is a separate axis from
    REST version and is handled in a later phase from a different data source.
.PARAMETER SpecsDirectory
    Where cached spec JSON files live. Defaults to tools/specs relative to this script.
.PARAMETER OutputPath
    Where to write the manifest. Defaults to Data/PfbCapabilityMap.json relative to the
    repo root (one level up from tools/).
.EXAMPLE
    ./tools/Build-PfbCapabilityMap.ps1
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')

if (-not $SpecsDirectory) {
    $SpecsDirectory = Join-Path $scriptDir 'specs'
}
if (-not $OutputPath) {
    $repoRoot = Split-Path -Parent $scriptDir
    $OutputPath = Join-Path (Join-Path $repoRoot 'Data') 'PfbCapabilityMap.json'
}

$specFiles = Get-ChildItem -Path $SpecsDirectory -Filter 'fb*.json' -ErrorAction SilentlyContinue
if (-not $specFiles) {
    throw "No cached specs found in '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first."
}

# Sort by numeric version, not filename string (fb2.9 must sort before fb2.10).
$specFiles = $specFiles | ForEach-Object {
    if ($_.BaseName -match '^fb(\d+)\.(\d+)$') {
        [PSCustomObject]@{
            File  = $_
            Major = [int]$Matches[1]
            Minor = [int]$Matches[2]
        }
    }
    else {
        Write-Warning "Skipping unrecognized spec filename: $($_.Name)"
        $null
    }
} | Where-Object { $_ } | Sort-Object Major, Minor

$endpoints = [ordered]@{}
$processedVersions = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $specFiles) {
    $version = "$($entry.Major).$($entry.Minor)"
    Write-Host "Processing $version ($($entry.File.Name))..." -ForegroundColor Cyan

    $spec = Get-Content -Path $entry.File.FullName -Raw | ConvertFrom-Json -Depth 64
    $capabilities = Get-PfbSpecCapabilities -Spec $spec

    foreach ($cap in $capabilities) {
        $epKey = "$($cap.Method) $($cap.Path)"

        if (-not $endpoints.Contains($epKey)) {
            $endpoints[$epKey] = [ordered]@{
                minVersion     = $version
                parameters     = [ordered]@{}
                bodyProperties = [ordered]@{}
            }
        }
        $entryRecord = $endpoints[$epKey]

        foreach ($paramName in $cap.Parameters) {
            if (-not $entryRecord.parameters.Contains($paramName)) {
                $entryRecord.parameters[$paramName] = $version
            }
        }
        foreach ($propName in $cap.BodyProperties) {
            if (-not $entryRecord.bodyProperties.Contains($propName)) {
                $entryRecord.bodyProperties[$propName] = $version
            }
        }
    }

    $processedVersions.Add($version)
}

$manifest = [ordered]@{
    schemaVersion  = 1
    generatedFrom  = $processedVersions
    endpointCount  = $endpoints.Count
    endpoints      = $endpoints
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host ''
Write-Host "Wrote $($endpoints.Count) endpoints from $($processedVersions.Count) versions to $OutputPath" -ForegroundColor Green
