#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests for tools/Build-PfbValueEnumMap.ps1 against small synthetic spec
    fixtures (no dependency on the real cached specs in tools/specs/), plus a shape/
    regression check of the real committed manifest when present.
.DESCRIPTION
    Every invocation below passes explicit -OutputPath AND -ReconciliationPath under
    TestDrive: — never let the script fall back to its real-repo defaults, or running
    these tests would overwrite Data/PfbValueEnumMap.json and
    tools/PfbValueEnumReconciliation.md as a side effect.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:builderScript = Join-Path $repoRoot 'tools/Build-PfbValueEnumMap.ps1'
}

Describe 'Build-PfbValueEnumMap: introduced-in diffing and value tracking' {
    BeforeAll {
        New-Item -ItemType Directory -Path 'TestDrive:\specs' -Force | Out-Null

        # v9.0: Widget.color has a two-value enum; a squash-mode-style pair of schemas
        # (WidgetA/WidgetB) share a property name with different value lists.
        $specV1 = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '9.0' }
            paths      = [ordered]@{}
            components = [ordered]@{
                schemas    = [ordered]@{
                    Widget  = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            color = @{ type = 'string'; description = 'The widget color. Valid values are `red`, `blue`.' }
                        }
                    }
                    WidgetA = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            mode = @{ type = 'string'; description = 'Valid values are `on`, `off`.' }
                        }
                    }
                    WidgetB = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            mode = @{ type = 'string'; description = 'Valid values are `enabled`, `disabled`.' }
                        }
                    }
                }
                parameters = [ordered]@{}
            }
        }

        # v9.1: Widget.color gains a third value (green); a brand-new Gadget.kind enum
        # appears; a numeric-range description that matches the trigger phrase but is
        # not a real enum is introduced (must land in "unparsed", not silently dropped).
        $specV2 = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '9.1' }
            paths      = [ordered]@{}
            components = [ordered]@{
                schemas    = [ordered]@{
                    Widget  = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            color = @{ type = 'string'; description = 'The widget color. Valid values are `red`, `blue`, and `green`.' }
                        }
                    }
                    WidgetA = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            mode = @{ type = 'string'; description = 'Valid values are `on`, `off`.' }
                        }
                    }
                    WidgetB = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            mode = @{ type = 'string'; description = 'Valid values are `enabled`, `disabled`.' }
                        }
                    }
                    Gadget  = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            kind    = @{ type = 'string'; description = 'Valid values are `small`, `large`.' }
                            timeout = @{ type = 'integer'; description = "Valid values are`nin the range of 1000 and 60000." }
                        }
                    }
                }
                parameters = [ordered]@{}
            }
        }

        $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\specs\fb9.0.json'
        $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\specs\fb9.1.json'

        & $builderScript -SpecsDirectory 'TestDrive:\specs' -OutputPath 'TestDrive:\output\map.json' -ReconciliationPath 'TestDrive:\output\reconciliation.md'
        $script:manifest = Get-Content -Path 'TestDrive:\output\map.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'records generatedFrom in ascending version order' {
        $manifest.generatedFrom | Should -Be @('9.0', '9.1')
    }

    It 'attributes an entry present since the earliest version to that version, but reports the newest values' {
        $manifest.entries.'Widget.color'.minVersion | Should -Be '9.0'
        $manifest.entries.'Widget.color'.values | Should -Be @('red', 'blue', 'green')
    }

    It 'attributes a brand-new entry to the version it first appears in' {
        $manifest.entries.'Gadget.kind'.minVersion | Should -Be '9.1'
        $manifest.entries.'Gadget.kind'.values | Should -Be @('small', 'large')
    }

    It 'never collapses two schemas sharing a property name into one entry (squash-mode gotcha)' {
        $manifest.entries.'WidgetA.mode'.values | Should -Be @('on', 'off')
        $manifest.entries.'WidgetB.mode'.values | Should -Be @('enabled', 'disabled')
    }

    It 'tracks a trigger-matching but non-enumerable description as unparsed rather than dropping it' {
        $manifest.unparsedCount | Should -BeGreaterThan 0
        $unparsedKeys = $manifest.unparsed | ForEach-Object { $_.key }
        $unparsedKeys | Should -Contain 'Gadget.timeout'
    }

    It 'reports entryCount matching the actual number of entries' {
        $manifest.entryCount | Should -Be $manifest.entries.PSObject.Properties.Name.Count
    }

    It 'reports unparsedCount matching the actual number of unparsed records' {
        $manifest.unparsedCount | Should -Be @($manifest.unparsed).Count
    }
}

Describe 'Build-PfbValueEnumMap: manifest shape' {
    BeforeAll {
        New-Item -ItemType Directory -Path 'TestDrive:\shapeSpecs' -Force | Out-Null
        $spec = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '9.0' }
            paths      = [ordered]@{}
            components = [ordered]@{
                schemas    = [ordered]@{
                    Widget = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            color = @{ type = 'string'; description = 'Valid values are `red`, `blue`.' }
                        }
                    }
                }
                parameters = [ordered]@{}
            }
        }
        $spec | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\shapeSpecs\fb9.0.json'

        & $builderScript -SpecsDirectory 'TestDrive:\shapeSpecs' -OutputPath 'TestDrive:\shapeOutput\map.json' -ReconciliationPath 'TestDrive:\shapeOutput\reconciliation.md'
        $script:shapeManifest = Get-Content -Path 'TestDrive:\shapeOutput\map.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'has the required top-level keys' {
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'schemaVersion'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'generatedFrom'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'entryCount'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'unparsedCount'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'entries'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'unparsed'
    }

    It 'writes a reconciliation report file' {
        Test-Path 'TestDrive:\shapeOutput\reconciliation.md' | Should -BeTrue
        (Get-Content 'TestDrive:\shapeOutput\reconciliation.md' -Raw) | Should -Match 'Value-Enum Reconciliation Report'
    }

    It 'throws a clear error when no cached specs are present' {
        New-Item -ItemType Directory -Path 'TestDrive:\emptySpecs' -Force | Out-Null
        { & $builderScript -SpecsDirectory 'TestDrive:\emptySpecs' -OutputPath 'TestDrive:\emptyOutput\map.json' -ReconciliationPath 'TestDrive:\emptyOutput\reconciliation.md' } |
            Should -Throw '*No cached specs found*'
    }
}

Describe 'Real committed value-enum map (skips gracefully if not yet generated)' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $script:realManifestPath = Join-Path $repoRoot 'Data/PfbValueEnumMap.json'
        $script:realSpecsDir = Join-Path $repoRoot 'tools/specs'
    }

    It 'Bucket.versioning regression: extracts exactly [none, enabled, suspended] with no per-value version claim' {
        if (-not (Test-Path $realManifestPath)) {
            Set-ItResult -Skipped -Because 'Data/PfbValueEnumMap.json not present (run Build-PfbValueEnumMap.ps1 first)'
            return
        }

        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $manifest.entries.'Bucket.versioning' | Should -Not -BeNullOrEmpty
        $manifest.entries.'Bucket.versioning'.values | Should -Be @('none', 'enabled', 'suspended')
    }

    It 'never collapses NfsExportPolicyRuleBase.access and the presets-only variant into one entry (squash-mode gotcha)' {
        if (-not (Test-Path $realManifestPath)) {
            Set-ItResult -Skipped -Because 'Data/PfbValueEnumMap.json not present (run Build-PfbValueEnumMap.ps1 first)'
            return
        }

        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $base = $manifest.entries.'NfsExportPolicyRuleBase.access'
        $preset = $manifest.entries.'_presetWorkloadExportConfigurationNfsRule.access'

        $base | Should -Not -BeNullOrEmpty
        $preset | Should -Not -BeNullOrEmpty
        $base.values | Should -Contain 'no-squash'
        $preset.values | Should -Contain 'no-root-squash'
        ($base.values -join ',') | Should -Not -Be ($preset.values -join ',')
    }

    It 'meets the acceptance-criteria entry-count floor and reports unparsedCount as a first-class field' {
        if (-not (Test-Path $realManifestPath)) {
            Set-ItResult -Skipped -Because 'Data/PfbValueEnumMap.json not present (run Build-PfbValueEnumMap.ps1 first)'
            return
        }

        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $manifest.entryCount | Should -BeGreaterOrEqual 100
        $manifest.PSObject.Properties.Name | Should -Contain 'unparsedCount'
        @($manifest.unparsed).Count | Should -Be $manifest.unparsedCount
    }

    It 'every (schema, property) value-enum extractable from the newest cached spec is represented in the manifest' {
        if (-not (Test-Path $realManifestPath) -or -not (Test-Path $realSpecsDir)) {
            Set-ItResult -Skipped -Because 'Data/PfbValueEnumMap.json or tools/specs/ not present (run Update-PfbApiSpecs.ps1 and Build-PfbValueEnumMap.ps1 first)'
            return
        }

        . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
        . (Join-Path $repoRoot 'tools/lib/PfbValueEnumTools.ps1')

        $specFiles = Get-ChildItem -Path $realSpecsDir -Filter 'fb*.json' | Where-Object { $_.BaseName -match '^fb(\d+)\.(\d+)$' }
        if (-not $specFiles) {
            Set-ItResult -Skipped -Because 'No cached spec files found under tools/specs/'
            return
        }
        $newest = $specFiles | ForEach-Object {
            $null = $_.BaseName -match '^fb(\d+)\.(\d+)$'
            [PSCustomObject]@{ File = $_; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
        } | Sort-Object Major, Minor | Select-Object -Last 1

        $spec = Get-Content -Path $newest.File.FullName -Raw | ConvertFrom-Json -Depth 64
        $valueEnums = Get-PfbSpecValueEnums -Spec $spec
        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $entryKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]$manifest.entries.PSObject.Properties.Name)
        $unparsedKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]($manifest.unparsed | ForEach-Object { $_.key }))

        $missing = $valueEnums | ForEach-Object { $_.Key } | Where-Object { -not $entryKeys.Contains($_) -and -not $unparsedKeys.Contains($_) }

        $missing | Should -BeNullOrEmpty -Because "these value enums exist in the newest spec but are represented in neither entries nor unparsed: $($missing -join ', ')"
    }
}
