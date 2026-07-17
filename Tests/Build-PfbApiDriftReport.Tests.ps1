#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests for tools/Build-PfbApiDriftReport.ps1 against small synthetic
    fixtures (capability map, field-cmdlet map, Public/Private trees, spec files) -- no
    dependency on the real cached specs in tools/specs/, plus one real-artifact check.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:builderScript = Join-Path $repoRoot 'tools/Build-PfbApiDriftReport.ps1'

    $script:fixtureRoot = Join-Path $TestDrive 'fixture'
    $publicDir = Join-Path $fixtureRoot 'Public/Fixture'
    $privateDir = Join-Path $fixtureRoot 'Private'
    $specsDir = Join-Path $fixtureRoot 'specs'
    New-Item -ItemType Directory -Path $publicDir, $privateDir, $specsDir -Force | Out-Null

    Set-Content -Path (Join-Path $publicDir 'Get-PfbFixtureArrayPerformance.ps1') -Value @'
function Get-PfbFixtureArrayPerformance {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()]
        [ValidateSet('nfs', 'smb', 'http', 's3')]
        [string]$Protocol
    )
    $queryParams = @{}
    if ($Protocol) { $queryParams['protocol'] = $Protocol }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/performance' -QueryParams $queryParams -AutoPaginate
}
'@

    # v1: Protocol has 4 values, matching the fixture cmdlet's ValidateSet exactly.
    $specV1 = [ordered]@{
        openapi = '3.0.1'; info = @{ version = '9.0' }
        paths = [ordered]@{
            '/arrays/performance' = [ordered]@{
                get = [ordered]@{
                    parameters = @(
                        [ordered]@{ name = 'protocol'; 'in' = 'query'; schema = [ordered]@{ type = 'string' }; description = 'Valid values are `nfs`, `smb`, `http`, and `s3`.' }
                    )
                }
            }
        }
        components = [ordered]@{ schemas = [ordered]@{} }
    }
    # v2: spec adds 'all' -- the real Get-PfbArrayPerformance -Protocol bug shape.
    $specV2 = [ordered]@{
        openapi = '3.0.1'; info = @{ version = '9.1' }
        paths = [ordered]@{
            '/arrays/performance' = [ordered]@{
                get = [ordered]@{
                    parameters = @(
                        [ordered]@{ name = 'protocol'; 'in' = 'query'; schema = [ordered]@{ type = 'string' }; description = 'Valid values are `all`, `nfs`, `smb`, `http`, and `s3`.' }
                    )
                }
            }
            '/gadgets' = [ordered]@{ get = [ordered]@{ parameters = @() } }
        }
        components = [ordered]@{ schemas = [ordered]@{} }
    }
    $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $specsDir 'fb9.0.json')
    $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $specsDir 'fb9.1.json')

    $script:capabilityMapPath = Join-Path $fixtureRoot 'PfbCapabilityMap.json'
    [ordered]@{
        schemaVersion = 1
        generatedFrom = @('9.0', '9.1')
        endpoints     = [ordered]@{
            'GET /arrays/performance' = [ordered]@{ minVersion = '9.0'; parameters = [ordered]@{ protocol = '9.0' }; bodyProperties = [ordered]@{} }
            'GET /gadgets'            = [ordered]@{ minVersion = '9.1'; parameters = [ordered]@{}; bodyProperties = [ordered]@{} }
        }
    } | ConvertTo-Json -Depth 20 | Set-Content -Path $capabilityMapPath

    $script:fieldCmdletMapPath = Join-Path $fixtureRoot 'PfbFieldCmdletMap.json'
    [ordered]@{
        schemaVersion   = 1
        generatedFrom   = @('9.0', '9.1')
        entries         = @(
            [ordered]@{ cmdlet = 'New-PfbFixtureWidget'; parameter = 'Color'; wireName = 'color'; status = 'matched'; matchedKey = 'Widget.color'; specValues = @('red', 'blue'); stableSinceOldestVersion = $true; recommendation = 'ValidateSet' }
        )
        attributesOnly  = @()
        typedUnresolved = @()
    } | ConvertTo-Json -Depth 20 | Set-Content -Path $fieldCmdletMapPath

    $script:outputPath = Join-Path $TestDrive 'output/PfbApiDriftReport.json'
    $script:reportPath = Join-Path $TestDrive 'output/PfbApiDriftReport.md'

    & $builderScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -PrivateDirectory $privateDir `
        -CapabilityMapPath $capabilityMapPath -FieldCmdletMapPath $fieldCmdletMapPath `
        -OutputPath $outputPath -ReportPath $reportPath

    $script:manifest = Get-Content -Path $outputPath -Raw | ConvertFrom-Json -Depth 20
}

Describe 'Build-PfbApiDriftReport' {
    It 'category 1: flags GET /gadgets as an uncovered endpoint' {
        ($manifest.uncoveredEndpoints | Where-Object { $_.endpoint -eq 'GET /gadgets' }) | Should -Not -BeNullOrEmpty
    }

    It 'category 3: flags the Protocol ValidateSet missing the spec''s newly-added "all" value' {
        $rec = $manifest.validateSetDrift | Where-Object { $_.cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.parameter -eq 'Protocol' }
        $rec.missingValues | Should -Contain 'all'
    }

    It 'category 4: passes Build-PfbFieldCmdletMap.ps1''s matched entries through unchanged' {
        $rec = $manifest.newValidateSetCandidates | Where-Object { $_.cmdlet -eq 'New-PfbFixtureWidget' }
        $rec.parameter | Should -Be 'Color'
    }

    It 'writes both a JSON manifest and a Markdown report' {
        Test-Path $outputPath | Should -BeTrue
        Test-Path $reportPath | Should -BeTrue
    }

    It 'the JSON manifest contains no non-deterministic content (no timestamp fields)' {
        $manifest.PSObject.Properties.Name | Should -Not -Contain 'generatedAt'
        $manifest.PSObject.Properties.Name | Should -Not -Contain 'timestamp'
    }
}

Describe 'Build-PfbApiDriftReport (real generated artifacts, skips gracefully if absent)' {
    It 'produces a manifest against the real Public/Private tree and Reports/ + Data/ inputs' {
        $realCapabilityMapPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
        $realFieldCmdletMapPath = Join-Path $repoRoot 'Reports/PfbFieldCmdletMap.json'
        $realSpecsDir = Join-Path $repoRoot 'tools/specs'
        if (-not (Test-Path $realCapabilityMapPath) -or -not (Test-Path $realFieldCmdletMapPath) -or
            -not (Test-Path $realSpecsDir) -or -not (Get-ChildItem $realSpecsDir -Filter 'fb*.json' -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json, Reports/PfbFieldCmdletMap.json, or tools/specs/ not present locally'
            return
        }

        $realOutput = Join-Path $TestDrive 'realOutput/report.json'
        $realReport = Join-Path $TestDrive 'realOutput/report.md'
        & $builderScript -SpecsDirectory $realSpecsDir -PublicDirectory (Join-Path $repoRoot 'Public') -PrivateDirectory (Join-Path $repoRoot 'Private') `
            -CapabilityMapPath $realCapabilityMapPath -FieldCmdletMapPath $realFieldCmdletMapPath `
            -OutputPath $realOutput -ReportPath $realReport
        Test-Path $realOutput | Should -BeTrue
    }
}
