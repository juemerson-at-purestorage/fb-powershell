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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/performance' -QueryParams $queryParams -AutoPaginate
}
'@

    # Real Get-PfbArraySpace shape: exactly one Invoke-PfbApiRequest call, so -Type's
    # $queryParams assignment resolves to exactly one (Method, Endpoint) pair.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureArraySpace.ps1') -Value @'
function Get-PfbFixtureArraySpace {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Type
    )
    $queryParams = @{}
    if ($Type) { $queryParams['type'] = $Type }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/space' -QueryParams $queryParams -AutoPaginate
}
'@

    # Real Get-PfbNode shape: the SAME $queryParams variable is reused across two calls
    # against two genuinely different endpoints (a try/catch model-support fallback) --
    # must resolve to $null, not a guessed pick of either endpoint.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureNode.ps1') -Value @'
function Get-PfbFixtureNode {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Filter
    )
    $queryParams = @{}
    if ($Filter) { $queryParams['filter'] = $Filter }
    try {
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'nodes' -QueryParams $queryParams -AutoPaginate
    } catch {
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'blades' -QueryParams $queryParams -AutoPaginate
    }
}
'@

    # Real Get-PfbPolicyAllMember shape: a plural wire name built by joining a string-array
    # parameter, not assigning it directly or wrapping it in @(...).
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixturePolicyAllMember.ps1') -Value @'
function Get-PfbFixturePolicyAllMember {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string[]]$MemberName
    )
    $queryParams = @{}
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'policies/members' -QueryParams $queryParams -AutoPaginate
}
'@

    # Real Get-PfbFileSystemSession shape: a switch's mere presence is keyed to a
    # hardcoded string literal, not derived from the switch's own value at all.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureFileSystemSession.ps1') -Value @'
function Get-PfbFixtureFileSystemSession {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [switch]$TotalOnly
    )
    $queryParams = @{}
    if ($TotalOnly) { $queryParams['total_only'] = 'true' }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-sessions' -QueryParams $queryParams -AutoPaginate
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

    It 'resolves a parameter joined into a plural wire name via -join' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixturePolicyAllMember' -and $_.Parameter -eq 'MemberName' }
        $rec.WireName | Should -Be 'member_names'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'resolves a [switch] parameter keyed to a hardcoded literal, guarded by if ($Param)' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureFileSystemSession' -and $_.Parameter -eq 'TotalOnly' }
        $rec.WireName | Should -Be 'total_only'
        $rec.Surface | Should -Be 'Typed'
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

Describe 'Get-PfbWireNameForParameter: switch-to-literal pattern' {
    It 'does NOT treat an unguarded literal assignment as switch-derived (false-positive guard)' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([switch]$Foo) $body = @{}; $body["bar"] = "literal" }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Foo' -IsSwitchParameter | Should -BeNullOrEmpty
    }

    It 'does NOT apply the switch-literal match when -IsSwitchParameter is not passed' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([switch]$Foo) if ($Foo) { $body["bar"] = "literal" } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Foo' | Should -BeNullOrEmpty
    }
}

Describe 'Endpoint/Method resolution (Get-PfbEndpointForVariable, via the inventory)' {
    It 'resolves Endpoint/Method for a parameter whose variable feeds exactly one Invoke-PfbApiRequest call' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArraySpace' -and $_.Parameter -eq 'Type' }
        $rec.Endpoint | Should -Be 'arrays/space'
        $rec.Method | Should -Be 'GET'
    }

    It 'leaves Endpoint/Method $null when the same variable feeds two calls with different endpoints (ambiguous, never guessed)' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureNode' -and $_.Parameter -eq 'Filter' }
        $rec.Endpoint | Should -BeNullOrEmpty
        $rec.Method | Should -BeNullOrEmpty
    }

    It 'leaves Endpoint/Method $null when there is no resolvable wire-name assignment at all' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.Parameter -eq 'StartTime' }
        $rec.Endpoint | Should -BeNullOrEmpty
        $rec.Method | Should -BeNullOrEmpty
    }

    It 'directly returns $null from Get-PfbEndpointForVariable for a variable with zero matching Invoke-PfbApiRequest calls' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Unused) $queryParams = @{} }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbEndpointForVariable -FunctionAst $funcAst -TargetVariable 'queryParams' | Should -BeNullOrEmpty
    }
}
