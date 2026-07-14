#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for the Private Assert-PfbApiCapability capability-check gate.
.DESCRIPTION
    Injects a small synthetic capability/version map into module state rather than relying
    on the real committed Data/PfbCapabilityMap.json, so these tests are independent of
    what the real map currently contains.
#>

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:originalModuleRoot = InModuleScope PureStorageFlashBladePowerShell { $script:PfbModuleRoot }

    function New-TestArray {
        param([string]$ApiVersion)
        [PSCustomObject]@{ ApiVersion = $ApiVersion }
    }
}

Describe 'Assert-PfbApiCapability' {
    BeforeEach {
        InModuleScope PureStorageFlashBladePowerShell {
            $script:PfbCapabilityMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'GET /widgets'  = [PSCustomObject]@{
                        minVersion     = '9.0'
                        parameters     = [PSCustomObject]@{ sort = '9.1' }
                        bodyProperties = [PSCustomObject]@{}
                    }
                    'POST /widgets' = [PSCustomObject]@{
                        minVersion     = '9.1'
                        parameters     = [PSCustomObject]@{}
                        bodyProperties = [PSCustomObject]@{ name = '9.0'; color = '9.2' }
                    }
                }
            }
            $script:PfbVersionMap = [PSCustomObject]@{
                '9.0' = [PSCustomObject]@{ purity = '5.0.0' }
                '9.1' = [PSCustomObject]@{ purity = '5.1.0' }
            }
        }
    }

    AfterEach {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = $script:originalModuleRoot } {
            $script:PfbCapabilityMap = $null
            $script:PfbVersionMap = $null
            $script:PfbModuleRoot = $root
        }
    }

    It 'does not throw when the endpoint and its query parameter are both supported by the connected version' {
        $array = New-TestArray -ApiVersion '9.1'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            { Assert-PfbApiCapability -Array $array -Method GET -Endpoint 'widgets' -QueryParams @{ sort = 'name' } } |
                Should -Not -Throw
        }
    }

    It 'throws when the endpoint itself requires a newer version than the connected array' {
        $array = New-TestArray -ApiVersion '9.0'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            { Assert-PfbApiCapability -Array $array -Method POST -Endpoint 'widgets' } |
                Should -Throw -ExpectedMessage '*POST /widgets requires REST 9.1*'
        }
    }

    It 'throws naming the specific query parameter that requires a newer version' {
        $array = New-TestArray -ApiVersion '9.0'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            { Assert-PfbApiCapability -Array $array -Method GET -Endpoint 'widgets' -QueryParams @{ sort = 'newest' } } |
                Should -Throw -ExpectedMessage "*parameter 'sort'*requires REST 9.1*"
        }
    }

    It 'ignores a query parameter whose value is null or empty (never sent, so never a violation)' {
        $array = New-TestArray -ApiVersion '9.0'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            { Assert-PfbApiCapability -Array $array -Method GET -Endpoint 'widgets' -QueryParams @{ sort = '' } } |
                Should -Not -Throw
        }
    }

    It 'throws naming the specific request-body field that requires a newer version' {
        $array = New-TestArray -ApiVersion '9.1'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            { Assert-PfbApiCapability -Array $array -Method POST -Endpoint 'widgets' -Body @{ name = 'x'; color = 'red' } } |
                Should -Throw -ExpectedMessage "*request-body field 'color'*requires REST 9.2*"
        }
    }

    It 'does not throw for an endpoint absent from the capability map (safety valve for stale/uncovered maps)' {
        $array = New-TestArray -ApiVersion '1.0'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            { Assert-PfbApiCapability -Array $array -Method GET -Endpoint 'not-in-map' } | Should -Not -Throw
        }
    }

    It 'includes the Purity//FB version in the message when the version map has an entry for both sides' {
        $array = New-TestArray -ApiVersion '9.0'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            { Assert-PfbApiCapability -Array $array -Method POST -Endpoint 'widgets' } |
                Should -Throw -ExpectedMessage '*Purity//FB 5.1.0*Purity//FB 5.0.0*'
        }
    }

    It 'omits the Purity//FB parenthetical cleanly when no version map is available' {
        InModuleScope PureStorageFlashBladePowerShell { $script:PfbVersionMap = $null }
        $array = New-TestArray -ApiVersion '9.0'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            $errorMessage = $null
            try { Assert-PfbApiCapability -Array $array -Method POST -Endpoint 'widgets' }
            catch { $errorMessage = $_.Exception.Message }
            $errorMessage | Should -BeLike '*requires REST 9.1*'
            $errorMessage | Should -Not -BeLike '*Purity*'
        }
    }

    It 'no-ops entirely when the capability map itself is unavailable' {
        InModuleScope PureStorageFlashBladePowerShell {
            $script:PfbCapabilityMap = $null
            $script:PfbModuleRoot = 'TestDrive:\nonexistent'
        }
        $array = New-TestArray -ApiVersion '1.0'
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            { Assert-PfbApiCapability -Array $array -Method GET -Endpoint 'widgets' } | Should -Not -Throw
        }
    }
}
