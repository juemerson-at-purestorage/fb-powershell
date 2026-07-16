#Requires -Version 7.0
<#
.SYNOPSIS
    Joins the cmdlet parameter inventory (tools/lib/PfbCmdletParamTools.ps1) against the
    prose value-enum data (tools/lib/PfbValueEnumTools.ps1) to recommend, per typed
    Public/ parameter that lacks a ValidateSet today, whether it should become a
    ValidateSet or an ArgumentCompleter.
.DESCRIPTION
    Data-extraction and reporting only -- does NOT add a ValidateSet or ArgumentCompleter
    to any Public/ cmdlet. See docs/superpowers/plans/2026-07-16-field-cmdlet-mapping.md
    for the full design rationale and the exact ValidateSet-recommendation rule.
.PARAMETER SpecsDirectory
    Where cached spec JSON files live. Defaults to tools/specs relative to this script.
.PARAMETER PublicDirectory
    Where Public/ cmdlet files live. Defaults to Public/ relative to the repo root.
.PARAMETER OutputPath
    Where to write Data/PfbFieldCmdletMap.json. Defaults there.
.PARAMETER ReportPath
    Where to write tools/PfbFieldCmdletMapping.md. Defaults there.
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,
    [string]$PublicDirectory,
    [string]$OutputPath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')
. (Join-Path $scriptDir 'lib/PfbValueEnumTools.ps1')
. (Join-Path $scriptDir 'lib/PfbCmdletParamTools.ps1')

$repoRoot = Split-Path -Parent $scriptDir
if (-not $SpecsDirectory)  { $SpecsDirectory = Join-Path $scriptDir 'specs' }
if (-not $PublicDirectory) { $PublicDirectory = Join-Path $repoRoot 'Public' }
if (-not $OutputPath)      { $OutputPath = Join-Path (Join-Path $repoRoot 'Data') 'PfbFieldCmdletMap.json' }
if (-not $ReportPath)      { $ReportPath = Join-Path $scriptDir 'PfbFieldCmdletMapping.md' }

$specFiles = Get-ChildItem -Path $SpecsDirectory -Filter 'fb*.json' -ErrorAction SilentlyContinue
if (-not $specFiles) {
    throw "No cached specs found in '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first."
}

$specFiles = $specFiles | ForEach-Object {
    if ($_.BaseName -match '^fb(\d+)\.(\d+)$') {
        [PSCustomObject]@{ File = $_; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
    }
} | Where-Object { $_ } | Sort-Object Major, Minor

# Re-derive, per (schema/param) Key, the full per-version value-set history -- NOT just
# the "latest wins" summary Data/PfbValueEnumMap.json stores -- so stability (did the
# value set ever change since first seen?) can be computed. Deliberately a separate,
# self-contained re-scan rather than modifying the prior phase's already-shipped output
# shape, keeping this task's diff additive-only.
$history = [ordered]@{}
$processedVersions = [System.Collections.Generic.List[string]]::new()
$oldestVersion = "$($specFiles[0].Major).$($specFiles[0].Minor)"

foreach ($entry in $specFiles) {
    $version = "$($entry.Major).$($entry.Minor)"
    $spec = Get-Content -Path $entry.File.FullName -Raw | ConvertFrom-Json -Depth 64
    $valueEnums = Get-PfbSpecValueEnums -Spec $spec

    foreach ($rec in $valueEnums) {
        if (-not $rec.Parsed) { continue }
        $sortedValues = ($rec.Values | Sort-Object) -join ','

        if (-not $history.Contains($rec.Key)) {
            $history[$rec.Key] = [ordered]@{
                Name           = $rec.Name
                MinVersion     = $version
                CurrentValues  = $rec.Values
                DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new()
            }
        }
        $history[$rec.Key].CurrentValues = $rec.Values
        [void]$history[$rec.Key].DistinctValueSets.Add($sortedValues)
    }

    $processedVersions.Add($version)
}

# --- Cmdlet parameter inventory, filtered to fields with no existing ValidateSet ---
$inventory = Get-PfbCmdletParameterInventory -PublicDirectory $PublicDirectory
$candidates = @($inventory | Where-Object { $_.Surface -eq 'Typed' -and -not $_.HasValidateSet })
$attributesOnly = @($inventory | Where-Object { $_.Surface -eq 'AttributesOnly' } | ForEach-Object { [ordered]@{ cmdlet = $_.Cmdlet; parameter = $_.Parameter } })
$typedUnresolved = @($inventory | Where-Object { $_.Surface -eq 'TypedUnresolved' } | ForEach-Object { [ordered]@{ cmdlet = $_.Cmdlet; parameter = $_.Parameter } })

function Get-PfbResourceHint {
    param([string]$CmdletName)
    # Strip the leading "<Verb>-Pfb" prefix to derive a resource-name hint, e.g.
    # "New-PfbNetworkInterface" -> "NetworkInterface". Matches any verb generically --
    # the "-Pfb" module prefix is the reliable marker, not the specific verb, and this
    # repo uses far more verbs (Add/Export/Invoke/Grant/...) than are worth enumerating.
    if ($CmdletName -match '^[A-Za-z]+-Pfb(.+)$') {
        return $Matches[1]
    }
    return $CmdletName
}

$entries = foreach ($cand in $candidates) {
    $hint = Get-PfbResourceHint -CmdletName $cand.Cmdlet
    $allMatches = @($history.Keys | Where-Object { $history[$_].Name -eq $cand.WireName })
    $hinted = @($allMatches | Where-Object { $_ -like "$hint*" })

    $status = $null
    $matchedKey = $null
    $specValues = $null
    $stable = $null
    $recommendation = $null

    if ($allMatches.Count -eq 0) {
        $status = 'no-spec-enum-found'
    }
    elseif ($hinted.Count -eq 0) {
        $status = 'not-found-in-resource'
    }
    else {
        $distinctCurrentSets = $hinted | ForEach-Object { ($history[$_].CurrentValues | Sort-Object) -join ',' } | Select-Object -Unique
        if (@($distinctCurrentSets).Count -gt 1) {
            $status = 'collision'
        }
        else {
            $matchedKey = $hinted[0]
            $h = $history[$matchedKey]
            $specValues = $h.CurrentValues
            $stable = ($h.MinVersion -eq $oldestVersion) -and ($h.DistinctValueSets.Count -eq 1)
            $status = 'matched'
            $recommendation = if ($stable) { 'ValidateSet' } else { 'ArgumentCompleter' }
        }
    }

    [ordered]@{
        cmdlet                   = $cand.Cmdlet
        parameter                = $cand.Parameter
        wireName                 = $cand.WireName
        status                   = $status
        matchedKey               = $matchedKey
        specValues                = $specValues
        stableSinceOldestVersion = $stable
        recommendation           = $recommendation
    }
}

$manifest = [ordered]@{
    schemaVersion  = 1
    generatedFrom  = $processedVersions
    entries        = $entries
    attributesOnly = $attributesOnly
    typedUnresolved = $typedUnresolved
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

$mdLines = [System.Collections.Generic.List[string]]::new()
$mdLines.Add('# Field-to-Cmdlet Mapping Report')
$mdLines.Add('')
$mdLines.Add("Generated by ``tools/Build-PfbFieldCmdletMap.ps1`` ($($processedVersions.Count) REST versions).")
$mdLines.Add('')
$mdLines.Add('Reporting only -- no `Public/` cmdlet is edited by this script. Every `matched` row below is a candidate for a follow-up decision, not an action already taken.')
$mdLines.Add('')
$mdLines.Add('| Cmdlet | Parameter | Wire name | Status | Spec values | Recommendation |')
$mdLines.Add('|---|---|---|---|---|---|')
foreach ($e in $entries) {
    $mdLines.Add("| ``$($e.cmdlet)`` | ``-$($e.parameter)`` | $($e.wireName) | $($e.status) | $($e.specValues -join ', ') | $($e.recommendation) |")
}
$mdLines.Add('')
$mdLines.Add("## Attributes-only parameters (no typed field to attach either mechanism to): $($attributesOnly.Count)")
$mdLines.Add('')
foreach ($a in $attributesOnly) { $mdLines.Add("- ``$($a.cmdlet) -$($a.parameter)``") }
$mdLines.Add('')
$mdLines.Add("## Typed but unresolved wire name (needs manual inspection): $($typedUnresolved.Count)")
$mdLines.Add('')
foreach ($u in $typedUnresolved) { $mdLines.Add("- ``$($u.cmdlet) -$($u.parameter)``") }
$mdLines.Add('')

Set-Content -Path $ReportPath -Value ($mdLines -join "`n") -Encoding UTF8
Write-Host "Wrote $($entries.Count) entries to $OutputPath and $ReportPath" -ForegroundColor Green
