#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/Build-PfbFieldCmdletMap.ps1's classification logic, against
    small synthetic inventory + spec fixtures. Also includes one real-artifact check that
    skips gracefully if tools/specs/ or Data/PfbValueEnumMap.json aren't present, matching
    Tests/Build-PfbValueEnumMap.Tests.ps1's convention.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbValueEnumTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbCmdletParamTools.ps1')
    $script:buildScript = Join-Path $repoRoot 'tools/Build-PfbFieldCmdletMap.ps1'

    $script:specsDir = Join-Path $TestDrive 'specs'
    New-Item -ItemType Directory -Path $specsDir -Force | Out-Null

    # Two versions: v1 introduces both a stable field (present unchanged in both versions)
    # and a field whose value set changes between versions (must NOT be recommended
    # ValidateSet even though it has full history). v-only-in-2 exists only in the newer
    # version (short history) and must also fall back to ArgumentCompleter.
    $specV1 = @{
        components = @{
            schemas = @{
                Widget = @{
                    properties = @{
                        stable_field    = @{ description = 'Valid values are `a`, `b`.' }
                        changing_field  = @{ description = 'Valid values are `x`, `y`.' }
                        collision_field = @{ description = 'Valid values are `m`, `n`.' }
                    }
                }
                WidgetSpecial = @{
                    properties = @{
                        # Same wire name as Widget.collision_field, different value set,
                        # and "WidgetSpecial" still prefix-matches the "Widget" resource
                        # hint -- must produce 'collision', not a guessed pick.
                        collision_field = @{ description = 'Valid values are `m`, `o`.' }
                    }
                }
                OtherThing = @{
                    properties = @{
                        # Real field, but under a schema the "Widget" hint never matches --
                        # must produce 'not-found-in-resource', not a false match.
                        elsewhere_field = @{ description = 'Valid values are `q`, `r`.' }
                    }
                }
            }
            # Reproduces the real Get-PfbArraySpace -Type bug pattern: Kind='parameter'
            # records are keyed by an OpenAPI components.parameters dictionary name with
            # NO relationship to the owning resource/cmdlet, so the resource-hint filter
            # (built for schema keys) can never match them. Two distinct
            # components.parameters definitions can share the same wire "name" -- if
            # they disagree on value set, the field is genuinely ambiguous (collision);
            # if they agree, it's safe to resolve regardless of which definition this
            # cmdlet's endpoint actually references (matched).
            parameters = @{
                ParamKindAmbiguousA  = @{ name = 'param_kind_ambiguous';  description = 'Valid values are `t1`, `t2`.' }
                ParamKindAmbiguousB  = @{ name = 'param_kind_ambiguous';  description = 'Valid values are `t1`, `t3`.' }
                ParamKindConsistentA = @{ name = 'param_kind_consistent'; description = 'Valid values are `k1`, `k2`.' }
                ParamKindConsistentB = @{ name = 'param_kind_consistent'; description = 'Valid values are `k1`, `k2`.' }
            }
        }
    }
    $specV2 = @{
        components = @{
            schemas = @{
                Widget = @{
                    properties = @{
                        stable_field    = @{ description = 'Valid values are `a`, `b`.' }
                        changing_field  = @{ description = 'Valid values are `x`, `y`, `z`.' }
                        new_in_v2       = @{ description = 'Valid values are `p`, `q`.' }
                        collision_field = @{ description = 'Valid values are `m`, `n`.' }
                    }
                }
                WidgetSpecial = @{
                    properties = @{
                        collision_field = @{ description = 'Valid values are `m`, `o`.' }
                    }
                }
                OtherThing = @{
                    properties = @{
                        elsewhere_field = @{ description = 'Valid values are `q`, `r`.' }
                    }
                }
            }
            parameters = @{
                ParamKindAmbiguousA  = @{ name = 'param_kind_ambiguous';  description = 'Valid values are `t1`, `t2`.' }
                ParamKindAmbiguousB  = @{ name = 'param_kind_ambiguous';  description = 'Valid values are `t1`, `t3`.' }
                ParamKindConsistentA = @{ name = 'param_kind_consistent'; description = 'Valid values are `k1`, `k2`.' }
                ParamKindConsistentB = @{ name = 'param_kind_consistent'; description = 'Valid values are `k1`, `k2`.' }
            }
        }
    }
    $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $specsDir 'fb1.0.json')
    $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $specsDir 'fb1.1.json')

    $script:publicDir = Join-Path $TestDrive 'Public'
    New-Item -ItemType Directory -Path $publicDir -Force | Out-Null
    # Cmdlet is named "New-PfbWidget" (not "New-PfbFixtureWidget") deliberately: the
    # resource-hint resolver strips the "New-Pfb" verb prefix to get "Widget", which must
    # prefix-match the fixture spec's "Widget.stable_field" etc. schema keys below.
    Set-Content -Path (Join-Path $publicDir 'New-PfbWidget.ps1') -Value @'
function New-PfbWidget {
    param(
        [Parameter()] [string]$StableField,
        [Parameter()] [string]$ChangingField,
        [Parameter()] [string]$NewInV2,
        [Parameter()] [string]$CollisionField,
        [Parameter()] [string]$ElsewhereField,
        [Parameter()] [string]$NoSpecField,
        [Parameter()] [string]$ParamKindField,
        [Parameter()] [string]$ParamKindConsistentField,
        [Parameter()] [PSCustomObject]$Array
    )
    $body = @{}
    if ($StableField)     { $body["stable_field"]     = $StableField }
    if ($ChangingField)   { $body["changing_field"]   = $ChangingField }
    if ($NewInV2)          { $body["new_in_v2"]        = $NewInV2 }
    if ($CollisionField)  { $body["collision_field"]  = $CollisionField }
    if ($ElsewhereField)  { $body["elsewhere_field"]  = $ElsewhereField }
    if ($NoSpecField)      { $body["totally_unknown_field"] = $NoSpecField }
    if ($ParamKindField)   { $body["param_kind_ambiguous"] = $ParamKindField }
    if ($ParamKindConsistentField) { $body["param_kind_consistent"] = $ParamKindConsistentField }
}
'@

    $script:outputDir = Join-Path $TestDrive 'output'
    $script:manifestPath = Join-Path $outputDir 'map.json'
    $script:reportPath = Join-Path $outputDir 'report.md'

    & $buildScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -OutputPath $manifestPath -ReportPath $reportPath
    $script:manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json -Depth 20
}

Describe 'Build-PfbFieldCmdletMap' {
    It 'recommends ValidateSet only for a field with full version history and no value-set changes' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'StableField' }
        $rec.status | Should -Be 'matched'
        $rec.stableSinceOldestVersion | Should -BeTrue
        $rec.recommendation | Should -Be 'ValidateSet'
    }

    It 'recommends ArgumentCompleter for a field with full history but a value-set change' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ChangingField' }
        $rec.status | Should -Be 'matched'
        $rec.stableSinceOldestVersion | Should -BeFalse
        $rec.recommendation | Should -Be 'ArgumentCompleter'
    }

    It 'recommends ArgumentCompleter for a field introduced only in the newest version' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'NewInV2' }
        $rec.status | Should -Be 'matched'
        $rec.stableSinceOldestVersion | Should -BeFalse
        $rec.recommendation | Should -Be 'ArgumentCompleter'
    }

    It 'writes the reconciliation-style Markdown report' {
        Test-Path $reportPath | Should -BeTrue
        (Get-Content $reportPath -Raw) | Should -Match 'ValidateSet'
    }

    It 'classifies a wire name matching multiple hinted schemas with different value sets as collision, not a guess' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'CollisionField' }
        $rec.status | Should -Be 'collision'
        $rec.recommendation | Should -BeNullOrEmpty
        $rec.matchedKey | Should -BeNullOrEmpty
    }

    It 'classifies a wire name found only under an unrelated schema as not-found-in-resource, not a false match' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ElsewhereField' }
        $rec.status | Should -Be 'not-found-in-resource'
        $rec.recommendation | Should -BeNullOrEmpty
    }

    It 'classifies a wire name absent from the spec entirely as no-spec-enum-found' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'NoSpecField' }
        $rec.status | Should -Be 'no-spec-enum-found'
        $rec.recommendation | Should -BeNullOrEmpty
    }

    It 'classifies a parameter-kind wire name with disagreeing value sets across components.parameters definitions as collision, not not-found-in-resource' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ParamKindField' }
        $rec.status | Should -Be 'collision'
        $rec.recommendation | Should -BeNullOrEmpty
        $rec.matchedKey | Should -BeNullOrEmpty
    }

    It 'resolves a parameter-kind wire name to matched when every components.parameters definition sharing it agrees on the same value set' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ParamKindConsistentField' }
        $rec.status | Should -Be 'matched'
        $rec.specValues | Should -Be @('k1', 'k2')
    }
}

Describe 'Build-PfbFieldCmdletMap (real generated artifacts, skips gracefully if absent)' {
    It 'produces a manifest against the real Public/ tree and tools/specs/ cache' {
        $realSpecsDir = Join-Path $repoRoot 'tools/specs'
        $realPublicDir = Join-Path $repoRoot 'Public'
        if (-not (Test-Path $realSpecsDir) -or -not (Get-ChildItem $realSpecsDir -Filter 'fb*.json' -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'tools/specs/ not present locally (gitignored, run Update-PfbApiSpecs.ps1 first)'
            return
        }

        $realOutput = Join-Path $TestDrive 'realOutput/map.json'
        $realReport = Join-Path $TestDrive 'realOutput/report.md'
        & $buildScript -SpecsDirectory $realSpecsDir -PublicDirectory $realPublicDir -OutputPath $realOutput -ReportPath $realReport
        Test-Path $realOutput | Should -BeTrue
    }
}
