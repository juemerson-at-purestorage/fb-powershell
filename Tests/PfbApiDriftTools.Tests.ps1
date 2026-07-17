#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbApiDriftTools.ps1 -- category 1 (uncovered endpoints) and
    category 2 (parameter gaps) of the API drift report.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbApiDriftTools.ps1')

    $script:publicFixtureDir = Join-Path $TestDrive 'Public/Fixture'
    $script:privateFixtureDir = Join-Path $TestDrive 'Private'
    New-Item -ItemType Directory -Path $publicFixtureDir -Force | Out-Null
    New-Item -ItemType Directory -Path $privateFixtureDir -Force | Out-Null

    Set-Content -Path (Join-Path $publicFixtureDir 'Get-PfbFixtureWidget.ps1') -Value @'
function Get-PfbFixtureWidget {
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Name)
    $queryParams = @{}
    if ($Name) { $queryParams['name'] = $Name }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'widgets' -QueryParams $queryParams -AutoPaginate
}
'@

    Set-Content -Path (Join-Path $publicFixtureDir 'Get-PfbFixtureDynamic.ps1') -Value @'
function Get-PfbFixtureDynamic {
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Kind)
    $endpoint = "widgets/$Kind"
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint $endpoint -AutoPaginate
}
'@

    # A Private/ helper that also happens to use the standard Invoke-PfbApiRequest
    # convention -- Get-PfbModuleCalledEndpoints must scan Private/ too, not just Public/.
    Set-Content -Path (Join-Path $privateFixtureDir 'Invoke-PfbFixtureInternalHelper.ps1') -Value @'
function Invoke-PfbFixtureInternalHelper {
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'internal-only' -AutoPaginate
}
'@

    $script:calledEndpoints = Get-PfbModuleCalledEndpoints -PublicDirectory $publicFixtureDir -PrivateDirectory $privateFixtureDir

    $script:capabilityMap = [PSCustomObject]@{
        endpoints = [PSCustomObject]@{
            'GET /widgets'        = [PSCustomObject]@{ minVersion = '2.0' }
            'GET /internal-only'  = [PSCustomObject]@{ minVersion = '2.0' }
            'GET /gadgets'        = [PSCustomObject]@{ minVersion = '2.20' }
            'POST /api/login'    = [PSCustomObject]@{ minVersion = '2.26' }
        }
    }
}

Describe 'Get-PfbModuleCalledEndpoints' {
    It 'resolves a literal -Method/-Endpoint pair to the capability-map key format' {
        $rec = $calledEndpoints | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureWidget' }
        $rec.Key | Should -Be 'GET /widgets'
        $rec.Resolved | Should -BeTrue
    }

    It 'scans Private/*.ps1 as well as Public/*.ps1' {
        $rec = $calledEndpoints | Where-Object { $_.Cmdlet -eq 'Invoke-PfbFixtureInternalHelper' }
        $rec.Key | Should -Be 'GET /internal-only'
    }

    It 'marks a dynamically-built -Endpoint as unresolved, never silently dropped or guessed' {
        $rec = $calledEndpoints | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureDynamic' }
        $rec.Resolved | Should -BeFalse
        $rec.Key | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbEndpointCoverageGaps' {
    It 'flags a capability-map endpoint no cmdlet calls at all' {
        $gaps = Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints
        ($gaps | Where-Object { $_.Endpoint -eq 'GET /gadgets' }) | Should -Not -BeNullOrEmpty
    }

    It 'does not flag an endpoint a fixture cmdlet already calls' {
        $gaps = Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints
        ($gaps | Where-Object { $_.Endpoint -eq 'GET /widgets' }) | Should -BeNullOrEmpty
    }

    It 'excludes a bespoke-allowlisted endpoint even though no cmdlet calls it directly' {
        $gaps = Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints -BespokeAllowlist @('POST /api/login')
        ($gaps | Where-Object { $_.Endpoint -eq 'POST /api/login' }) | Should -BeNullOrEmpty
    }
}

Describe 'Bespoke auth-endpoint allowlist (real, confirmed by reading Private/ + Connect-PfbArray.ps1)' {
    It 'contains exactly the four confirmed bespoke endpoints, no more, no fewer' {
        $script:PfbBespokeAuthEndpoints | Sort-Object | Should -Be @(
            'GET /api/api_version',
            'POST /api/login',
            'POST /api/logout',
            'POST /oauth2/1.0/token'
        ) | Sort-Object
    }
}
