#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbCmdletParamTools.ps1 — the AST-based cmdlet parameter
    inventory used by tools/Build-PfbFieldCmdletMap.ps1.
.DESCRIPTION
    Runs against a small synthetic Public/-shaped directory under TestDrive, built from
    real patterns observed in this repo's actual cmdlets (New-PfbAlertWatcher's simple
    $body['wire_name'] = $Param assignment, New-PfbNetworkInterface's -Attributes escape
    hatch and its unresolvable $AttachedServers | ForEach-Object {...} pipeline, and
    Get-PfbArrayPerformance's $queryParams assignment) — no dependency on the real Public/
    tree so the test stays stable if cmdlets change.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbCmdletParamTools.ps1')

    $script:fixtureDir = Join-Path $TestDrive 'Public/Fixture'
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureAlertWatcher.ps1') -Value @'
function New-PfbFixtureAlertWatcher {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('info', 'warning', 'critical')]
        [string]$MinimumSeverity,

        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($MinimumSeverity) { $body['minimum_notification_severity'] = $MinimumSeverity }
    }
}
'@

    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureNetworkInterface.ps1') -Value @'
function New-PfbFixtureNetworkInterface {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Individual")]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(ParameterSetName = "Individual")]
        [ValidateSet("data", "egress-only", "management", "replication", "support")]
        [string[]]$Services,

        [Parameter(ParameterSetName = "Individual")]
        [string[]]$AttachedServers,

        [Parameter(Mandatory, ParameterSetName = "Attributes")]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    if ($PSCmdlet.ParameterSetName -eq "Attributes") {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($Services) { $body["services"] = @($Services) }
        if ($AttachedServers) {
            $body["attached_servers"] = @($AttachedServers | ForEach-Object { @{ name = $_ } })
        }
    }
}
'@

    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureArrayPerformance.ps1') -Value @'
function Get-PfbFixtureArrayPerformance {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,

        [Parameter()]
        [string]$Protocol,

        [Parameter()]
        [int64]$Resolution,

        [Parameter()]
        [datetime]$StartTime
    )

    $queryParams = @{}
    if ($Protocol)   { $queryParams["protocol"]   = $Protocol }
    if ($Resolution) { $queryParams["resolution"] = $Resolution }
    # Deliberately NOT a simple "$queryParams[key] = $Param" assignment -- string
    # interpolation is a real pattern this repo does not currently use, but the resolver
    # must not guess through it. No -Attributes escape hatch exists on this cmdlet either,
    # so this must surface as TypedUnresolved, not silently dropped or force-matched.
    if ($StartTime) { $queryParams["start_time"] = "$StartTime" }
}
'@

    $script:inventory = Get-PfbCmdletParameterInventory -PublicDirectory $fixtureDir
}

Describe 'Get-PfbCmdletParameterInventory' {
    It 'always skips the Array parameter' {
        $inventory | Where-Object { $_.Parameter -eq 'Array' } | Should -BeNullOrEmpty
    }

    It 'always skips the Attributes parameter itself' {
        $inventory | Where-Object { $_.Parameter -eq 'Attributes' } | Should -BeNullOrEmpty
    }

    It 'records an existing ValidateSet and marks HasValidateSet true' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureAlertWatcher' -and $_.Parameter -eq 'MinimumSeverity' }
        $rec.HasValidateSet | Should -BeTrue
        $rec.ValidateSetValues | Should -Be @('info', 'warning', 'critical')
    }

    It 'resolves a simple $body[wire_name] = $Param assignment' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureAlertWatcher' -and $_.Parameter -eq 'MinimumSeverity' }
        $rec.WireName | Should -Be 'minimum_notification_severity'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'resolves a simple $queryParams[wire_name] = $Param assignment' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.Parameter -eq 'Protocol' }
        $rec.WireName | Should -Be 'protocol'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'resolves an array parameter wrapped in @(...)' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNetworkInterface' -and $_.Parameter -eq 'Services' }
        $rec.WireName | Should -Be 'services'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'classifies a parameter fed through a pipeline transform as AttributesOnly, not a guessed wire name' {
        # $AttachedServers is assigned via `@($AttachedServers | ForEach-Object { @{ name = $_ } })`
        # -- deliberately NOT matched by the simple-assignment resolver. Since this cmdlet also
        # has an -Attributes escape hatch, it must be classified AttributesOnly, not silently
        # dropped and not force-matched to a wrong wire name.
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNetworkInterface' -and $_.Parameter -eq 'AttachedServers' }
        $rec.WireName | Should -BeNullOrEmpty
        $rec.Surface | Should -Be 'AttributesOnly'
    }

    It 'resolves a parameter with no -Attributes escape hatch via a simple assignment' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.Parameter -eq 'Resolution' }
        $rec.WireName | Should -Be 'resolution'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'classifies a parameter with no -Attributes escape hatch and no resolvable assignment as TypedUnresolved' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.Parameter -eq 'StartTime' }
        $rec.WireName | Should -BeNullOrEmpty
        $rec.Surface | Should -Be 'TypedUnresolved'
    }
}

Describe 'Get-PfbWireNameForParameter' {
    It 'returns $null when the parameter name never appears on the right-hand side of a body/queryParams assignment' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Unused) $body = @{} }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Unused' | Should -BeNullOrEmpty
    }
}
